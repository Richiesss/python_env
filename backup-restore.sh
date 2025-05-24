#!/bin/bash

# 環境設定のバックアップと復元を行うスクリプト
# このスクリプトはコンテナ内の拡張機能やライブラリの状態を保存・復元します

# エラーが発生した時点でスクリプトを終了
set -e

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# docker-composeの絶対パスを指定
DOCKER_COMPOSE="/usr/local/bin/docker-compose"

# バックアップディレクトリ
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"

# コンテナ名
CONTAINER_NAME="ml_env"

# バックアップファイル名（日付入り）
BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/ml_env_backup_${BACKUP_TIMESTAMP}.tar.gz"

# バックアップの作成
backup() {
    echo "Creating backup of container environment..."
    
    # コンテナ起動チェック（修正版）
    if ! $DOCKER_COMPOSE ps | grep "$CONTAINER_NAME" | grep -q "Up"; then
        echo "Container is not running. Starting container..."
        $DOCKER_COMPOSE start
        sleep 5
    fi
    
    # 一時ディレクトリの作成
    local temp_dir="${BACKUP_DIR}/temp_${BACKUP_TIMESTAMP}"
    mkdir -p "$temp_dir"
    
    # インストール済みPythonパッケージのリストを取得
    echo "Listing installed Python packages..."
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" pip freeze > "${temp_dir}/requirements.txt"
    
    # VSCode拡張機能のリストを取得
    echo "Listing installed VS Code extensions..."
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" code-server --list-extensions > "${temp_dir}/extensions.txt" 2>/dev/null || echo "" > "${temp_dir}/extensions.txt"
    
    # インストール済みシステムパッケージのリストを取得
    echo "Listing installed system packages..."
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "dpkg --get-selections | grep -v deinstall | awk '{print \$1}'" > "${temp_dir}/apt_packages.txt"
    
    # バッシュ履歴のバックアップ
    echo "Backing up bash history..."
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "cat ~/.bash_history 2>/dev/null || echo ''" > "${temp_dir}/bash_history.txt"
    
    # code-server設定のバックアップ
    echo "Backing up code-server config..."
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "cat ~/.config/code-server/config.yaml 2>/dev/null || echo ''" > "${temp_dir}/code_server_config.yaml"
    
    # バックアップファイルを一つのアーカイブにまとめる
    echo "Creating final backup archive..."
    tar -czf "$BACKUP_FILE" -C "$temp_dir" .
    
    # 一時ディレクトリの削除
    rm -rf "$temp_dir"
    
    echo "Backup completed: $BACKUP_FILE"
    echo "To restore this backup later, run: $0 restore $BACKUP_FILE"
}

# バックアップからの復元
restore() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        echo "Error: No backup file specified."
        echo "Usage: $0 restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        exit 1
    fi
    
    echo "Restoring from backup: $backup_file"
    
    # 一時ディレクトリの作成
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # バックアップファイルの展開
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # コンテナ起動チェック（修正版）
    if ! $DOCKER_COMPOSE ps | grep "$CONTAINER_NAME" | grep -q "Up"; then
        echo "Container is not running. Starting container..."
        $DOCKER_COMPOSE start
        sleep 5
    fi
    
    # コンテナ内にファイルをコピーする一時ディレクトリを作成
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" mkdir -p /tmp/restore
    
    # システムパッケージの復元（基本パッケージとの差分のみ）
    if [ -f "$temp_dir/apt_packages.txt" ]; then
        echo "Checking system packages to restore..."
        docker cp "$temp_dir/apt_packages.txt" "$CONTAINER_NAME:/tmp/restore/apt_packages.txt"
        
        # 現在のパッケージリストを取得
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "dpkg --get-selections | grep -v deinstall | awk '{print \$1}' > /tmp/restore/current_packages.txt"
        
        # 差分を計算してインストール
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "
            comm -13 <(sort /tmp/restore/current_packages.txt) <(sort /tmp/restore/apt_packages.txt) > /tmp/restore/packages_to_install.txt
            if [ -s /tmp/restore/packages_to_install.txt ]; then
                echo 'Installing missing system packages...'
                apt-get update
                xargs -a /tmp/restore/packages_to_install.txt apt-get install -y
            else
                echo 'All system packages are already installed.'
            fi
        "
    fi
    
    # Pythonパッケージの復元
    if [ -f "$temp_dir/requirements.txt" ]; then
        echo "Restoring Python packages..."
        docker cp "$temp_dir/requirements.txt" "$CONTAINER_NAME:/tmp/restore/requirements.txt"
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" pip install -r /tmp/restore/requirements.txt
    fi
    
    # VSCode拡張機能の復元
    if [ -f "$temp_dir/extensions.txt" ] && [ -s "$temp_dir/extensions.txt" ]; then
        echo "Restoring VS Code extensions..."
        docker cp "$temp_dir/extensions.txt" "$CONTAINER_NAME:/tmp/restore/extensions.txt"
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "
            while IFS= read -r extension; do 
                [ -z \"\$extension\" ] && continue
                echo \"Installing extension: \$extension\"
                code-server --install-extension \"\$extension\" || echo \"Failed to install: \$extension\"
            done < /tmp/restore/extensions.txt
        "
    fi
    
    # バッシュ履歴の復元
    if [ -f "$temp_dir/bash_history.txt" ]; then
        echo "Restoring bash history..."
        docker cp "$temp_dir/bash_history.txt" "$CONTAINER_NAME:/tmp/restore/bash_history.txt"
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "cat /tmp/restore/bash_history.txt > ~/.bash_history"
    fi
    
    # code-server設定の復元
    if [ -f "$temp_dir/code_server_config.yaml" ] && [ -s "$temp_dir/code_server_config.yaml" ]; then
        echo "Restoring code-server config..."
        docker cp "$temp_dir/code_server_config.yaml" "$CONTAINER_NAME:/tmp/restore/code_server_config.yaml"
        $DOCKER_COMPOSE exec "$CONTAINER_NAME" bash -c "mkdir -p ~/.config/code-server && cp /tmp/restore/code_server_config.yaml ~/.config/code-server/config.yaml"
    fi
    
    # 一時ディレクトリのクリーンアップ
    $DOCKER_COMPOSE exec "$CONTAINER_NAME" rm -rf /tmp/restore
    
    echo "Restoration completed."
}

# スクリプト使用法の表示
usage() {
    echo "Usage: $0 [backup|restore <backup_file>]"
    echo ""
    echo "Commands:"
    echo "  backup                Create a new backup of the container environment"
    echo "  restore <backup_file> Restore container environment from a backup file"
    echo ""
    echo "Examples:"
    echo "  $0 backup                     # Create a new backup"
    echo "  $0 restore ./backups/ml_env_backup_20250410_120000.tar.gz  # Restore from backup"
}

# メイン関数
main() {
    case "$1" in
        backup)
            backup
            ;;
        restore)
            restore "$2"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# スクリプトの実行
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

main "$@"