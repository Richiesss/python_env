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

# JupyterLabの起動（ホームディレクトリで実行）
echo "JupyterLabを起動しています..."
$DOCKER_COMPOSE exec -d $CONTAINER_NAME bash -c "cd ~ && jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=''"

echo "JupyterLabが起動しました。アクセス: http://localhost:8888"
echo "Ctrl+C でこのスクリプトを終了しても、JupyterLabはコンテナ内で実行され続けます"
echo "JupyterLabを停止するには、コンテナを再起動するかシャットダウンしてください"

# 任意のキー入力を待つ
read -p "何かキーを押すと続行します..." -n1 -s
echo