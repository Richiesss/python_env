#!/bin/bash

# エラーが発生した時点でスクリプトを終了
set -e

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# docker-composeの絶対パスを指定
# DOCKER_COMPOSE="/usr/local/bin/docker-compose"
DOCKER_COMPOSE="/snap/bin/docker-compose"

# コンテナ名
CONTAINER_NAME="ml_env"

# コンテナの状態確認
echo "コンテナの状態を確認しています..."
if ! $DOCKER_COMPOSE ps | grep "$CONTAINER_NAME" | grep -q "Up"; then
    echo "エラー: コンテナが起動していません。./start-container.sh で起動してください"
    exit 1
fi

# 既存のcode-serverプロセスを確認
echo "既存のcode-serverプロセスを確認しています..."
if $DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ps aux | grep -q '[c]ode-server'"; then
    echo "code-serverは既に実行中です。再起動しますか？ [Y/n]: "
    read -r RESTART
    if [[ ! "$RESTART" =~ ^[Nn]$ ]]; then
        echo "既存のcode-serverを停止しています..."
        $DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "pkill code-server || true"
        sleep 2
    else
        echo "既存のcode-serverを使用します。"
        exit 0
    fi
fi

# Code-Serverの起動
echo "Code-Serverを起動しています..."
$DOCKER_COMPOSE exec -d $CONTAINER_NAME bash -c "code-server --config ~/.config/code-server/config.yaml ~"

# 起動の確認（少し待機）
echo "起動を確認しています..."
sleep 3

# プロセスの確認
if $DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ps aux | grep -q '[c]ode-server'"; then
    echo "✓ Code-Serverが正常に起動しました"
    echo "アクセス: http://localhost:8080"
    
    # パスワードの表示
    PASSWORD=$($DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "grep 'password:' ~/.config/code-server/config.yaml | awk '{print \$2}'" | tr -d '\r')
    echo "パスワード: $PASSWORD"
else
    echo "✗ Code-Serverの起動に失敗しました"
    echo "デバッグ情報を確認するには ./debug-code-server.sh を実行してください"
    exit 1
fi