#!/bin/bash

# Code-Serverのクイックテストスクリプト
# 最小限の設定でcode-serverが動作するか確認します

# エラーが発生した時点でスクリプトを終了
set -e

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# docker-composeの絶対パスを指定
DOCKER_COMPOSE="/usr/local/bin/docker-compose"

# コンテナ名
CONTAINER_NAME="ml_env"

echo "=== Code-Server クイックテスト ==="
echo ""

# コンテナの確認
if ! $DOCKER_COMPOSE ps | grep -q "Up" | grep "$CONTAINER_NAME"; then
    echo "エラー: コンテナが起動していません。./start-container.sh で起動してください"
    exit 1
fi

# 既存のcode-serverを停止
echo "既存のcode-serverプロセスを停止しています..."
$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "pkill code-server || true"
sleep 2

# シンプルな起動テスト（設定ファイルを使わない）
echo "最小設定でcode-serverを起動します..."
echo "認証なしでポート8080で起動します"
echo ""
echo "アクセスURL: http://localhost:8080"
echo "Ctrl+C で終了"
echo ""

$DOCKER_COMPOSE exec $CONTAINER_NAME bash -c "code-server --auth none --bind-addr 0.0.0.0:8080 ~"