#!/bin/bash

# エラーが発生した時点でスクリプトを終了
set -e

# docker-composeの絶対パスを指定
DOCKER_COMPOSE="/usr/local/bin/docker-compose"

# 自動モードフラグ
AUTO_MODE=false

# 引数の解析
for arg in "$@"; do
    case $arg in
        -auto|--auto)
        AUTO_MODE=true
        shift
        ;;
        *)
        # 不明な引数はスキップ
        shift
        ;;
    esac
done

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# ハッシュファイルの保存場所
HASH_FILE=".docker_files_hash"

# 初期セットアップ確認
setup_initial_environment() {
    # 必要なディレクトリの作成
    if [ ! -d "docker-data" ]; then
        echo "docker-dataディレクトリを作成します..."
        mkdir -p docker-data
        
        # .gitignoreを作成してSSH鍵などを除外
        if [ ! -f "docker-data/.gitignore" ]; then
            echo "docker-data/.gitignoreを作成してSSH鍵などの機密情報をGitから除外します..."
            cat > docker-data/.gitignore << EOL
# SSH keys and config
.ssh/
# Bash history
.bash_history
# Python cache
__pycache__/
*.pyc
# Jupyter
.jupyter/
.ipynb_checkpoints/
# VS Code
.vscode/
EOL
            echo "docker-data/.gitignoreを作成しました"
        fi
    fi
    
    if [ ! -d "backups" ]; then
        echo "backupsディレクトリを作成します..."
        mkdir -p backups
    fi
    
    # code-server設定ファイルの確認
    if [ ! -f "code-server-config.yaml" ]; then
        echo "code-server-config.yamlが見つかりません。デフォルト設定を作成します..."
        cat > code-server-config.yaml << EOL
bind-addr: 0.0.0.0:8080
auth: password
password: password
cert: false
EOL
        echo "code-server-config.yamlを作成しました"
        echo "⚠️  警告: デフォルトパスワード 'password' が設定されています。"
        echo "⚠️  セキュリティのため、必ず変更してください！"
    fi
    
    # ハッシュファイルの初期化
    if [ ! -f "$HASH_FILE" ]; then
        echo "初回実行: Docker設定ファイルのハッシュを初期化します..."
        touch "$HASH_FILE"
    fi
    
    # プロジェクトルートの.gitignoreの確認
    if [ ! -f ".gitignore" ]; then
        echo "プロジェクトの.gitignoreを作成します..."
        cat > .gitignore << 'EOL'
# Docker data directory
docker-data/

# Backup files
backups/

# Docker files hash
.docker_files_hash
.docker_files_hash.new

# macOS
.DS_Store

# IDE
.vscode/
.idea/

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python

# Jupyter
.ipynb_checkpoints/

# Environment variables
.env

# Logs
*.log

# Code-server config (contains password)
code-server-config.yaml
EOL
        echo ".gitignoreを作成しました"
    fi
    
    # スクリプトの実行権限確認
    for script in start-jupyter.sh start-code-server.sh backup-restore.sh schedule-backup.sh cleanup-old-backups.sh debug-code-server.sh quick-test-code-server.sh; do
        if [ -f "$script" ] && [ ! -x "$script" ]; then
            echo "${script}に実行権限を付与します..."
            chmod +x "$script"
        fi
    done
}

# 最新のバックアップファイルを見つける
find_latest_backup() {
    local latest_backup=$(find "./backups" -name "ml_env_backup_*.tar.gz" -type f 2>/dev/null | sort -r | head -n 1)
    echo "$latest_backup"
}

# 環境を復元する
restore_environment() {
    local latest_backup=$1
    
    if [ -z "$latest_backup" ] || [ ! -f "$latest_backup" ]; then
        echo "有効なバックアップファイルが見つかりません。新規環境として起動します。"
        return 1
    fi
    
    echo "前回の環境を復元しています: $latest_backup"
    ./backup-restore.sh restore "$latest_backup"
    
    if [ $? -eq 0 ]; then
        echo "環境の復元が完了しました。"
        return 0
    else
        echo "環境の復元に失敗しました。新規環境として起動します。"
        return 1
    fi
}

# bashrcの設定内容
BASHRC_CONTENT='
# カラー設定
export PS1="\[\033[38;5;040m\]\u\[\033[38;5;243m\]@\[\033[38;5;033m\]\h\[\033[38;5;243m\]:\[\033[38;5;045m\]\w\[\033[38;5;243m\]\\$ \[\033[0m\]"

# ls コマンドの色設定
export LS_COLORS="di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
alias ls="ls --color=auto"

# その他のエイリアス
alias ll="ls -la"
alias l="ls -l"
'

# 不要なイメージを削除
cleanup_images() {
    echo "未使用のDockerイメージを確認しています..."
    
    # <none>タグのイメージを取得
    NONE_IMAGES=$(docker images -f "dangling=true" -q)
    
    if [ ! -z "$NONE_IMAGES" ]; then
        echo "未使用のイメージが見つかりました。削除しています..."
        docker rmi $NONE_IMAGES 2>/dev/null || true
        echo "クリーンアップが完了しました。"
    else
        echo "未使用のイメージはありません。"
    fi
}

# コンテナの状態確認
container_status() {
    $DOCKER_COMPOSE ps --quiet ml_env 2>/dev/null
}

# Dockerファイルのハッシュを計算（docker-compose.yamlも含める）
calculate_hash() {
    find . -maxdepth 1 -type f \( -name "Dockerfile" -o -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "code-server-config.yaml" \) -exec sha256sum {} \; 2>/dev/null | sort > "${HASH_FILE}.new"
}

# ファイルの変更を確認
check_files_changed() {
    if [ ! -f "$HASH_FILE" ]; then
        return 0
    fi
    
    calculate_hash
    if ! diff -q "${HASH_FILE}.new" "$HASH_FILE" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ハッシュファイルを更新
update_hash() {
    if [ -f "${HASH_FILE}.new" ]; then
        mv "${HASH_FILE}.new" "$HASH_FILE"
    fi
}

# シェルの設定を更新
setup_shell() {
    echo "カラフルなシェルプロンプトを設定しています..."
    $DOCKER_COMPOSE exec ml_env bash -c "echo '$BASHRC_CONTENT' > ~/.bashrc"
    
    # SSH設定ディレクトリのパーミッション修正
    echo "SSHディレクトリのパーミッションを設定しています..."
    $DOCKER_COMPOSE exec ml_env bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
}

# Jupyterの起動
start_jupyter() {
    echo "Starting JupyterLab..."
    $DOCKER_COMPOSE exec -d ml_env bash -c "cd ~ && jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=''"
    echo "JupyterLab started. Access at http://localhost:8888"
}

# Code-Serverの起動
start_code_server() {
    echo "Starting Code-Server..."
    
    # 既存のプロセスを停止
    $DOCKER_COMPOSE exec ml_env bash -c "pkill code-server || true"
    sleep 2
    
    # 新しいプロセスを起動
    $DOCKER_COMPOSE exec -d ml_env bash -c "code-server --config ~/.config/code-server/config.yaml ~"
    
    # 少し待機してから確認
    sleep 3
    
    if $DOCKER_COMPOSE exec ml_env bash -c "ps aux | grep -q '[c]ode-server'"; then
        echo "Code-Server started. Access at http://localhost:8080"
        
        # 設定ファイルからパスワードを読み取って表示（改行を削除）
        PASSWORD=$($DOCKER_COMPOSE exec ml_env bash -c "grep 'password:' ~/.config/code-server/config.yaml | awk '{print \$2}'" | tr -d '\r\n')
        echo "Password: $PASSWORD (configured in code-server-config.yaml)"
    else
        echo "Warning: Code-Server may not have started properly"
        echo "Run ./debug-code-server.sh for more information"
    fi
}

# 自動バックアップのセットアップ
setup_auto_backup() {
    local option="$1"
    
    echo "自動バックアップの設定"
    
    if [ "$AUTO_MODE" = true ]; then
        echo "自動モード: デフォルト設定を適用します（24時間ごとのバックアップ、30日間保持）"
        ./schedule-backup.sh 24 30
        return
    fi
    
    echo "Macが予期せず終了した場合でもデータを保護するため、定期的なバックアップをスケジュールします"
    echo "----------------------------------------"
    echo "1. 6時間ごとに自動バックアップ"
    echo "2. 12時間ごとに自動バックアップ"
    echo "3. 24時間ごとに自動バックアップ(デフォルト)"
    echo "4. 自動バックアップを設定しない"
    echo "5. カスタム間隔を設定する"
    echo "----------------------------------------"
    
    read -p "オプションを選択してください [1-5]: " BACKUP_OPTION
    option=${BACKUP_OPTION:-3}
    
    case $option in
        1)
            ./schedule-backup.sh 6 30
            ;;
        2)
            ./schedule-backup.sh 12 30
            ;;
        3)
            ./schedule-backup.sh 24 30
            ;;
        4)
            ./schedule-backup.sh 0
            ;;
        5)
            read -p "バックアップ間隔を時間単位で入力してください: " CUSTOM_HOURS
            read -p "バックアップの保持日数を入力してください (デフォルト: 30): " CUSTOM_DAYS
            CUSTOM_DAYS=${CUSTOM_DAYS:-30}
            ./schedule-backup.sh $CUSTOM_HOURS $CUSTOM_DAYS
            ;;
        *)
            # デフォルト: 24時間
            ./schedule-backup.sh 24 30
            ;;
    esac
}

# 自動モードでサービス選択
select_services_auto() {
    echo "自動モード: JupyterLabとCode-Serverの両方を起動します"
    start_jupyter
    start_code_server
}

# メイン処理
main() {
    # 初期セットアップの確認
    setup_initial_environment
    
    # 不要なイメージを削除
    cleanup_images
    
    echo "Dockerファイルの変更を確認しています..."
    
    # Dockerファイルの変更をチェック
    if check_files_changed; then
        echo "Dockerファイルが変更されています。コンテナを再ビルドします..."
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE build
        update_hash
        echo "再ビルドが完了しました。"
        
        # ビルド後に再度クリーンアップを実行
        cleanup_images
    fi
    
    echo "Dockerコンテナを起動しています..."
    
    # コンテナが存在するか確認
    if [ -z "$(container_status)" ]; then
        echo "コンテナが見つかりません。新しいコンテナを起動します..."
        $DOCKER_COMPOSE up -d
        
        # コンテナの起動を待機
        echo "コンテナの準備を待っています..."
        sleep 5
        
        # 新規コンテナの場合はシェル設定を実行
        setup_shell
    else
        # コンテナが停止している場合は起動（修正版）
        if ! $DOCKER_COMPOSE ps | grep "ml_env" | grep -q "Up"; then
            echo "コンテナは存在しますが実行されていません。起動します..."
            $DOCKER_COMPOSE start
            sleep 5
        fi
    fi
    
    # コンテナの状態を確認
    if [ -z "$(container_status)" ]; then
        echo "コンテナの起動に失敗しました。docker-compose.yml（またはdocker-compose.yaml）を確認してもう一度お試しください。"
        exit 1
    fi
    
    # バックアップスクリプトに実行権限があるか確認
    if [ -f "./backup-restore.sh" ]; then
        if [ ! -x "./backup-restore.sh" ]; then
            chmod +x ./backup-restore.sh
        fi
        
        # 最新のバックアップがあれば復元する
        latest_backup=$(find_latest_backup)
        if [ ! -z "$latest_backup" ]; then
            if [ "$AUTO_MODE" = true ]; then
                # 自動モードでは自動的に復元
                restore_environment "$latest_backup"
            else
                # 対話モードでは確認を取る
                read -p "前回のバックアップから環境を復元しますか？ [Y/n]: " RESTORE_ENV
                if [[ ! "$RESTORE_ENV" =~ ^[Nn]$ ]]; then
                    restore_environment "$latest_backup"
                else
                    echo "環境の復元をスキップします。"
                fi
            fi
        else
            echo "利用可能なバックアップが見つかりません。新規環境として起動します。"
        fi
    fi
    
    # 自動バックアップのセットアップ
    if [ -f "./schedule-backup.sh" ]; then
        if [ ! -x "./schedule-backup.sh" ]; then
            chmod +x ./schedule-backup.sh
        fi
        
        # 自動モードの場合はデフォルト設定を使用
        if [ "$AUTO_MODE" = true ]; then
            setup_auto_backup 3
        else
            # 自動バックアップを設定するか質問
            read -p "定期的な自動バックアップを設定しますか？ [Y/n]: " SETUP_BACKUP
            if [[ "$SETUP_BACKUP" =~ ^[Nn]$ ]]; then
                echo "自動バックアップは設定されていません。必要に応じて手動で ./backup-restore.sh backup を実行してください。"
            else
                setup_auto_backup
            fi
        fi
    else
        echo "注意: バックアップスクリプトが見つかりません。自動バックアップは設定されません。"
    fi
    
    # サービスの起動選択
    if [ "$AUTO_MODE" = true ]; then
        select_services_auto
    else
        echo "起動するサービスを選択してください:"
        echo "1. JupyterLab"
        echo "2. Code-Server"
        echo "3. 両方"
        echo "4. なし"
        read -p "選択 [1-4]: " SERVICE_CHOICE
        
        case $SERVICE_CHOICE in
            1)
                start_jupyter
                ;;
            2)
                start_code_server
                ;;
            3)
                start_jupyter
                start_code_server
                ;;
            *)
                echo "サービスは起動されませんでした。"
                ;;
        esac
    fi
    
    echo "コンテナに接続しています..."
    # ホームディレクトリに移動してからシェルを起動
    $DOCKER_COMPOSE exec -w /root ml_env /bin/bash --login
}

# スクリプト実行
main