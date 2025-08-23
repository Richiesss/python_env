#!/bin/bash

# Code-Serverのデバッグスクリプト

# エラーが発生した時点でスクリプトを終了
set -e

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# docker-composeの絶対パスを指定
# DOCKER_COMPOSE="/usr/local/bin/docker-compose"
DOCKER_COMPOSE="/snap/bin/docker-compose"

# コンテナ名
CONTAINER_NAME="ml_env"

echo "=== Code-Server デバッグ情報 ==="
echo ""

# コンテナの状態確認（修正版）
echo "1. コンテナの状態確認..."
if $DOCKER_COMPOSE ps | grep "$CONTAINER_NAME" | grep -q "Up"; then
    echo "✓ Container is running"
else
    echo "✗ コンテナが起動していません。./start-container.sh で起動してください"
    exit 1
fi

echo ""
echo "2. code-serverのインストール確認..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "which code-server || echo '✗ code-serverが見つかりません'"

echo ""
echo "3. code-serverのバージョン確認..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "code-server --version || echo '✗ バージョンを取得できません'"

echo ""
echo "4. 設定ファイルの確認..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ls -la ~/.config/code-server/config.yaml || echo '✗ 設定ファイルが見つかりません'"

echo ""
echo "5. 設定ファイルの内容:"
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "cat ~/.config/code-server/config.yaml || echo '✗ 設定ファイルを読み込めません'"

echo ""
echo "6. code-serverプロセスの確認..."
if $DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ps aux | grep -q '[c]ode-server'"; then
    echo "✓ code-serverプロセスが実行中です"
    $DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ps aux | grep code-server"
else
    echo "✗ code-serverが実行されていません"
fi

echo ""
echo "7. ポート8080の確認..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "ss -tlnp 2>/dev/null | grep 8080 || netstat -tlnp 2>/dev/null | grep 8080 || echo 'ポート8080はリッスンしていません'"

echo ""
echo "8. Dockerポートマッピングの確認..."
docker port $CONTAINER_NAME | grep 8080 || echo "ポート8080のマッピングが見つかりません"

echo ""
echo "9. code-serverの起動テスト..."
echo "既存のcode-serverプロセスを停止..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "pkill code-server || true"
sleep 2

echo ""
echo "10. ホスト側のポート8080の使用状況を確認..."
if lsof -i:8080 >/dev/null 2>&1; then
    echo "✗ ポート8080は既に使用されています:"
    lsof -i:8080
else
    echo "✓ ポート8080は利用可能です"
fi

echo ""
echo "フォアグラウンドモードでcode-serverを起動してテストします..."
echo "成功すれば 'HTTP server listening on http://0.0.0.0:8080' と表示されます"
echo "Ctrl+C で終了"
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "code-server --config ~/.config/code-server/config.yaml --bind-addr 0.0.0.0:8080 ~"