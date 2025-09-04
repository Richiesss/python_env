# Linux(WSL2)上で動作するx86機械学習・開発環境

本番環境(x86)との互換性を保ちながらLinux(WSL2)上で開発できる機械学習環境のDockerセットアップである。x86 Dockerコンテナを使用している。

## 構成(読み飛ばしてもOK！！)
### コンポーネント構成

#### 1. コンテナレイヤー
- **ベースOS**: Ubuntu 22.04 (x86_64)
- **Python環境**: Python 3.11 + 機械学習ライブラリスタック
- **開発環境**: Code-Server (VS Code互換) + Jupyter Lab
- **システムツール**: Git, SSH, curl, vim等の開発ツール

#### 2. サービス構成
| サービス | ポート | 説明 | アクセス方法 |
|----------|--------|------|-------------|
| Code-Server | 8080 | VS Code互換のWeb IDE | http://localhost:8080 |
| Jupyter Lab | 8888 | データ分析・機械学習環境 | http://localhost:8888 |
| SSH | 22 | リモートアクセス（内部） | コンテナ内で利用 |

#### 3. ストレージ構成
```
Host側ストレージ:
├── docker-data/          # ホームディレクトリマウント
│   ├── .ssh/            # SSH鍵（永続化）
│   ├── .bashrc          # シェル設定
│   ├── .gitconfig       # Git設定
│   └── workspace/       # 作業ディレクトリ
├── backups/             # 自動バックアップファイル
└── code-server-config.yaml  # Code-Server設定

Docker Volumes:
├── ml_env_vscode_data   # VS Code拡張機能・設定
├── ml_env_pip_cache     # Pythonパッケージキャッシュ
└── ml_env_apt_cache     # システムパッケージキャッシュ
```

#### 4. ネットワーク構成
- **ブリッジネットワーク**: デフォルトのDockerネットワーク
- **ポートマッピング**: 
  - 8080:8080 (Code-Server)
  - 8888:8888 (Jupyter Lab)
- **内部通信**: コンテナ内サービス間は直接通信
- **外部アクセス**: LAN内の他デバイス（iPad等）からアクセス可能

### データフロー

#### 1. 開発フロー
```
開発者 → Web Browser → WSL2:8080/8888 → Docker Container → Python/ML Libraries
   ↑                                                              ↓
   └──────────────── Results/Outputs ←─────────────────────────────┘
```

#### 2. データ永続化フロー
```
コンテナ内変更 → Volume/Mount → Host File System → 自動バックアップ → ./backups/
     ↑                                                      ↓
     └─────────────── 復元時 ←─────────────────────────────────┘
```

#### 3. バックアップ・復元フロー
```
定期実行 → 環境スキャン → アーカイブ作成 → ./backups/保存
    ↓           ↓              ↓            ↓
スケジューラ → パッケージ一覧 → tar.gz → 古いファイル削除
            → 拡張機能一覧
            → 設定ファイル
            → bashヒストリー
```

### セキュリティ構成

#### 1. アクセス制御
- **Code-Server**: パスワード認証（設定可能）
- **Jupyter Lab**: トークン認証（自動生成）
- **SSH**: 鍵認証（GitHub連携）

#### 2. ネットワークセキュリティ
- **ローカルバインド**: デフォルトでlocalhost限定
- **ファイアウォール**: WSL2のファイアウォール設定に依存
- **HTTPS**: 必要に応じて設定可能（証明書要）

#### 3. データ保護
- **権限管理**: ファイルパーミッションの適切な設定
- **バックアップ暗号化**: 必要に応じて実装可能
- **機密情報除外**: `.gitignore`による自動除外

### パフォーマンス構成

#### 1. リソース割り当て
- **CPU**: ホストCPUをコンテナで共有
- **メモリ**: Docker Desktopの設定に依存（推奨4GB以上）
- **ストレージ**: SSDストレージ推奨

#### 2. キャッシュ戦略
- **Pipキャッシュ**: パッケージインストール高速化
- **Aptキャッシュ**: システムパッケージインストール高速化
- **Docker Build Cache**: イメージビルド高速化

#### 3. 最適化ポイント
- **Volume Mount**: ホストファイルシステムとの高速アクセス
- **Layer Caching**: Dockerfileの階層化による効率的ビルド
- **Resource Limits**: 必要に応じてリソース制限設定

## 特徴(読み飛ばしてOK)

- **x86互換性**: 本番環境と同じx86アーキテクチャで動作
- **PyTorch対応**: x86版PyTorch 2.5.1がプリインストール済み
- **Jupyter Lab統合**: データ分析作業用のJupyter Lab環境
- **VS Code統合**: iPadのブラウザからコーディングできるCode-Server環境
- **Git/SSH対応**: GitHubなどからのリポジトリクローンが可能
- **簡単セットアップ**: スクリプト一発で環境構築
- **自動管理**: ファイル変更検知による自動リビルド機能
- **永続データ**: 再起動時も拡張機能やライブラリを保持
- **完全バックアップ**: システムパッケージ、Pythonライブラリ、VS Code拡張機能、設定ファイルすべてをバックアップ
- **自動バックアップ**: 定期的なバックアップによるデータ保護
- **環境復元**: 再起動時に前回のバックアップから自動復元
- **手動管理**: コンテナの自動再起動を無効化し、スクリプトによる制御を実現

## セットアップ手順(ここから大事！！)

> [!TIP]
> いろいろファイルがあるが、とりあえずこれをやれば使えるようになるのでOK。

### 初回セットアップ

#### WSL2(Windows Subsystem for Linux2)の導入
WSL2とはなんぞや？
[解説](https://zenn.dev/oit2003/articles/2f3f8576df0d71)


1. **管理者権限でPowerShellを開く**
2. **以下のコマンドを入力してWSLを有効化する**

```powershell
#WSLのインストール
wsl --install

#WSLを起動
wsl
```



#### Dockerの導入
Dockerとはなんぞや？
[解説](https://qiita.com/michiru-miyagawa/items/fb41563df9dc98fdf549)

1. **WSLを起動した状態で以下のコマンドを入力する**
```bash
#Dockerのインストール
sudo snap install docker
```

#### いよいよ環境構築
基本的には以下のコマンドを上から順番に叩けばよい
```bash
# リポジトリをクローン
git clone https://github.com/Richiesss/python_env.git
cd python_env

# 実行権限を付与
chmod +x *.sh

# code-server設定ファイルをサンプルからコピー（推奨）
cp code-server-config.yaml.sample code-server-config.yaml

# code-server設定ファイルのパスワードを変更（重要）
code code-server-config.yaml
# passwordの値を任意のパスワードに変更

# コンテナを起動（必要なディレクトリは自動作成される）
./start-container.sh
```

### 起動前に確認すること

1. **ポートの空き状況**
   ```bash
   # 8080番（Code-Server）と8888番（JupyterLab）が空いているか確認
   lsof -i:8080
   lsof -i:8888
   ```

2. **Docker Desktopの設定**
   - Rosetta 2エミュレーションが有効になっているか確認
   - メモリ割り当てが十分か確認（最低4GB推奨）

3. **セキュリティ設定**
   - `code-server-config.yaml`のパスワードを変更したか確認
   - 外部からアクセスする場合はファイアウォール設定を確認

### 自動モードの使用

対話的な入力をスキップしてデフォルト設定で起動する場合、`-auto`または`--auto`オプションを使用できる：

```bash
./start-container.sh --auto
```

自動モードでは以下のデフォルト設定が適用される：

- 24時間ごとの自動バックアップ（30日間保持）
- JupyterLabとCode-Serverの両方が自動起動
- 前回のバックアップからの自動復元
- すべてのユーザー入力をスキップ

<!-- これは、Launch Agent経由での自動起動や、スクリプトでの呼び出しに最適である。例えば、Mac起動時に自動的に環境を立ち上げる場合は以下のようにLaunch Agentを設定できる：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yourname.ml-env</string>
    <key>RunAtLoad</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>cd /path/to/repo && ./start-container.sh --auto</string>
    </array>
</dict>
</plist>
``` -->

### ファイルと役割

| ファイル名 | 役割 | 実行方法 |
|------------|------|---------|
| `docker-compose.yml` | Docker環境の定義ファイル | - |
| `Dockerfile` | コンテナのビルド定義 | - |
| `code-server-config.yaml` | Code-Serverの設定ファイル | - |
| `code-server-config.yaml.sample` | Code-Server設定ファイルのサンプル | - |
| `.gitignore` | Gitから除外するファイルの設定 | - |
| `start-container.sh` | メインの起動スクリプト | `./start-container.sh` |
| `start-jupyter.sh` | Jupyter Lab起動スクリプト | `./start-jupyter.sh` |
| `start-code-server.sh` | Code-Server起動スクリプト | `./start-code-server.sh` |
| `debug-code-server.sh` | Code-Serverのデバッグスクリプト | `./debug-code-server.sh` |
| `quick-test-code-server.sh` | Code-Serverの簡易テストスクリプト | `./quick-test-code-server.sh` |
| `backup-restore.sh` | バックアップと復元用スクリプト | `./backup-restore.sh [backup|restore]` |
| `schedule-backup.sh` | 定期バックアップのスケジューラ | `./schedule-backup.sh [hours] [days]` |
| `cleanup-old-backups.sh` | 古いバックアップを削除するスクリプト | `./cleanup-old-backups.sh [days]` |

<!-- ## iPadからアクセスする方法

1. MacとiPadが同じWiFiネットワークに接続されていることを確認
2. Macのプライベートネットワークアドレスを確認（システム環境設定→ネットワーク）
3. iPadのSafari/Chromeブラウザで以下のURLにアクセス:
   - JupyterLab: `http://[Macのアドレス]:8888`
   - Code-Server: `http://[Macのアドレス]:8080`
   - パスワード: `code-server-config.yaml`で設定した値

**重要**: code-server-config.yamlのパスワードは必ず変更すること。 -->

## 自動バックアップと復元機能(あまり気にしなくてもいい)

突然のシャットダウンや電源喪失からデータを保護するため、自動バックアップ機能がある：

- **スケジュール設定**: コンテナ起動時に自動バックアップの間隔を設定できる
- **デフォルト設定**: 24時間ごとのバックアップ、30日間保持
- **自動復元**: コンテナ再起動時に最新のバックアップから環境を復元
- **バックアップ内容**:
  - インストール済みのPythonパッケージ
  - インストール済みのシステムパッケージ（aptでインストールしたもの）
  - VS Code拡張機能
  - code-serverの設定
  - bashヒストリー
- **手動での調整**: 
```bash
# カスタム間隔と保持期間の設定（例：12時間ごと、7日間保持）
./schedule-backup.sh 12 7

# 自動バックアップを無効化
./schedule-backup.sh 0
```

## 手動バックアップと復元(あまり気にしなくてもいい)

必要に応じて手動でバックアップと復元を行うことも可能である：

```bash
# 現在の環境をバックアップ
./backup-restore.sh backup

# バックアップから環境を復元
./backup-restore.sh restore ./backups/ml_env_backup_20250410_120000.tar.gz
```

## データの永続性(あまり気にしなくてもいい)

以下のデータは永続化される：

**ホストディレクトリにマウント（./docker-data/）:**
- ホームディレクトリのファイル全般
- SSH鍵と設定（~/.ssh）
- bashヒストリーなど

**Docker ボリュームに保存:**
- code-server 拡張機能と設定
- VSCode ユーザー設定
- pip キャッシュ
- Python ライブラリ
- apt キャッシュ

これにより、コンテナを再起動または再作成しても、インストールした拡張機能やライブラリ、SSH鍵が保持される。また、バックアップと復元機能により、万が一データが破損した場合でも前の状態に戻すことができる。

## よくある操作(あまり気にしなくてもいい)

### 環境の起動/再起動と自動復元

```bash
# 環境を起動/再起動（最新バックアップから復元するか確認）
./start-container.sh

# 環境を起動/再起動（自動的に最新バックアップから復元）
./start-container.sh --auto
```

### Jupyter Labだけを起動

```bash
./start-jupyter.sh
```

### Code-Serverだけを起動

```bash
./start-code-server.sh
```

### Code-Serverのトラブルシューティング

```bash
# 詳細なデバッグ情報を表示
./debug-code-server.sh

# 最小設定で動作確認（認証なし）
./quick-test-code-server.sh
```

### 古いバックアップの削除

```bash
# 14日より古いバックアップを削除
./cleanup-old-backups.sh 14
```

## 前提条件

- M1/M2/M3 Mac（Apple Silicon）
- Docker Desktop for Mac
- Docker DesktopでRosetta 2エミュレーションが有効化されていること

## セキュリティとバージョン管理

プロジェクトには2つの`.gitignore`ファイルが含まれている：

1. **プロジェクトルートの`.gitignore`**: 
   - `docker-data/`とバックアップファイルをGitから除外
   - `code-server-config.yaml`（パスワード含む）を除外
2. **`docker-data/.gitignore`**: SSH鍵などの機密情報を除外（自動生成）

これにより、機密情報が誤ってGitにコミットされることを防ぐ。

**注意**: `code-server-config.yaml`はGitで管理されない。サンプルファイル（`code-server-config.yaml.sample`）をコピーして使用すること。

## ディレクトリ構造

```
.
├── Dockerfile                # x86環境の定義
├── code-server-config.yaml   # Code-Serverの設定ファイル（Gitで管理されない）
├── code-server-config.yaml.sample # Code-Server設定ファイルのサンプル
├── .docker_files_hash        # Dockerfile差分検査用のハッシュファイル
├── .gitignore               # Git除外設定
├── docker-compose.yml        # Docker Compose設定
├── start-container.sh        # 環境起動スクリプト
├── start-jupyter.sh          # Jupyter Lab起動スクリプト
├── start-code-server.sh      # Code-Server起動スクリプト
├── debug-code-server.sh      # Code-Serverデバッグスクリプト
├── quick-test-code-server.sh # Code-Server簡易テストスクリプト
├── backup-restore.sh         # 環境バックアップ/復元スクリプト
├── schedule-backup.sh        # 自動バックアップスケジュール設定
├── cleanup-old-backups.sh    # 古いバックアップの削除
├── backups/                  # バックアップファイル保存ディレクトリ
└── docker-data/              # ホームディレクトリのデータ（~/にマウント）
    └── .gitignore           # docker-data内の除外設定（自動生成）
```

## GitHubからのリポジトリクローン（SSH設定）

コンテナにはSSHクライアントがインストールされており、GitHubなどからSSH経由でリポジトリをクローンできる。

### SSH鍵の設定方法

#### 方法1: コンテナ内で新しいSSH鍵を生成（推奨）

```bash
# コンテナ内で実行
ssh-keygen -t ed25519 -C "your_email@example.com"

# 公開鍵を表示してGitHubに登録
cat ~/.ssh/id_ed25519.pub
```

生成した公開鍵をGitHubの Settings > SSH and GPG keys > New SSH key に追加する。

SSH鍵は`./docker-data/.ssh/`に保存されるため、ホスト側からも以下のように確認できる：
```bash
# ホスト側から確認
cat ./docker-data/.ssh/id_ed25519.pub
```

#### 方法2: ホストのSSH鍵をコピー

ホストのSSH鍵を使用したい場合は、コピーすることができる：

```bash
# ホスト側で実行（秘密鍵のパーミッションに注意）
cp ~/.ssh/id_ed25519 ./docker-data/.ssh/
cp ~/.ssh/id_ed25519.pub ./docker-data/.ssh/
chmod 600 ./docker-data/.ssh/id_ed25519
chmod 644 ./docker-data/.ssh/id_ed25519.pub
```

### GitHubからのクローン

SSH鍵の設定後、以下のようにリポジトリをクローンできる：

```bash
# 初回接続時はGitHubのホスト鍵を承認
ssh -T git@github.com

# リポジトリをクローン
git clone git@github.com:username/repository.git
```

### Git設定

```bash
# ユーザー名とメールアドレスを設定
git config --global user.name "Your Name"
git config --global user.email "your_email@example.com"
```

**注意**: SSH鍵は`./docker-data/.ssh/`に保存されるため、コンテナを再起動しても保持される。このディレクトリはホスト側からも確認できるが、セキュリティのため適切なパーミッション（700）が設定されている。

## パスワード変更方法

Code-Serverのパスワードを変更するには、`code-server-config.yaml`ファイルを編集する：

```yaml
bind-addr: 0.0.0.0:8080
auth: password
password: 新しいパスワード
cert: false
```

**注意**: 現在の設定ファイルにはサンプルパスワードが設定されている。セキュリティのため、必ず変更すること。

変更後の手順：
1. コンテナを再ビルド: `docker-compose build`
2. コンテナを再起動: `./start-container.sh`

または、コンテナ内で直接編集：
```bash
# コンテナ内で実行
vi ~/.config/code-server/config.yaml
# code-serverを再起動
pkill code-server
code-server --config ~/.config/code-server/config.yaml ~
```

## トラブルシューティング(困ったらここ)

### コンテナが起動しない場合

```bash
# Dockerログを確認
/usr/local/bin/docker-compose logs

# コンテナを強制的に再ビルド
/usr/local/bin/docker-compose down
/usr/local/bin/docker-compose build --no-cache
/usr/local/bin/docker-compose up -d
```

### Code-Serverにアクセスできない場合

```bash
# Code-Serverの状態を詳しく確認
./debug-code-server.sh

# 最小設定でのテスト（認証なし）
./quick-test-code-server.sh

# Code-Serverのプロセスを確認
/usr/local/bin/docker-compose exec ml_env ps aux | grep code-server

# 手動で再起動
/usr/local/bin/docker-compose exec ml_env pkill code-server || true
./start-code-server.sh

# ログを確認しながら起動
/usr/local/bin/docker-compose exec ml_env code-server --config ~/.config/code-server/config.yaml --bind-addr 0.0.0.0:8080 ~
```

よくある原因と解決方法：

1. **ポート8080が既に使用されている**
   ```bash
   # ホスト側で確認
   lsof -i:8080
   # 別のポートに変更する場合はdocker-compose.ymlを編集
   ```

2. **設定ファイルの形式エラー**
   ```bash
   # YAMLの検証
   /usr/local/bin/docker-compose exec ml_env cat ~/.config/code-server/config.yaml
   ```

3. **パスワードの問題**
   - 特殊文字が含まれている場合は引用符で囲む
   - デフォルトパスワードから変更していない

4. **Dockerの再ビルドが必要**
   ```bash
   /usr/local/bin/docker-compose down
   /usr/local/bin/docker-compose build --no-cache
   ./start-container.sh
   ```

### docker-composeコマンドでエラーが出る場合

スクリプト内では`/usr/local/bin/docker-compose`のパスを使用している。異なるパスにインストールされている場合は、各スクリプト内のDOCKER_COMPOSE変数を修正すること：

```bash
# docker-composeの絶対パスを確認
which docker-compose

# 各スクリプトの先頭部分を編集
DOCKER_COMPOSE="/正しいパス/docker-compose"
```

### バックアップからの復元に失敗する場合

```bash
# バックアップファイルの内容を確認
tar -tvf ./backups/ml_env_backup_YYYYMMDD_HHMMSS.tar.gz

# 手動で復元を試みる
./backup-restore.sh restore ./backups/ml_env_backup_YYYYMMDD_HHMMSS.tar.gz
```

### 作業ディレクトリについて

コンテナ内の作業ディレクトリは`/root`（ホームディレクトリ）である。`docker-data`ディレクトリの内容がここにマウントされるため、ホスト側の`docker-data`内のファイルがコンテナ内の`/root`で利用できる。

## ライセンス
MITライセンス

## 貢献

問題報告や機能リクエストは、GitHubのIssuesで受け付けている。Pull Requestも歓迎する。
