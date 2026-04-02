# perpet

Zig で書かれた、初心者にやさしい dotfiles 管理ツール。

chezmoi ほど複雑ではなく、GNU Stow より高機能な、ちょうどいい dotfiles 管理ツールです。

**[English README](README.md)**

## Features

- **シンプルなファイルマッピング** - `home/` ディレクトリが `$HOME` をそのままミラー。特殊なファイル名規約なし
- **シンボリックリンク & コピー** - ファイルごとに管理方式を選択可能
- **テンプレートエンジン** - `{{ .variable }}` 構文でマシンごとの設定を管理
- **Git 連携** - 基本的な Git 操作を内蔵。リポジトリの初期化からプッシュまで
- **クロスプラットフォーム** - macOS / Linux / Windows 対応
- **シングルバイナリ** - 外部依存なし。ダウンロードして即使える

## Quick Start

### インストール

```bash
# ソースからビルド（Zig 0.15.2 以上が必要）
git clone https://github.com/NaruseNia/perpet.git
cd perpet
zig build -Doptimize=ReleaseSafe
# バイナリは zig-out/bin/perpet に出力されます
```

### 初期セットアップ

```bash
# dotfiles リポジトリを初期化
perpet init

# 既存のリモートリポジトリからセットアップ
perpet init https://github.com/yourname/dotfiles.git
```

### 基本的な使い方

```bash
# dotfile を管理対象に追加
perpet add .bashrc
perpet add .config/nvim/init.lua

# テンプレートとして追加（マシンごとに内容を変えたい場合）
perpet add .gitconfig --template

# 管理対象のファイルを確認
perpet list

# dotfiles を適用（$HOME にシンボリックリンク/コピーを作成）
perpet apply

# 変更状況を確認
perpet status

# ソースとターゲットの差分を表示
perpet diff

# リモートの変更を取得して適用
perpet update
```

## How It Works

perpet は `~/.perpet/` ディレクトリを使って dotfiles を管理します。

```
~/.perpet/
  perpet.toml              # 設定ファイル
  home/                    # $HOME のミラー
    .bashrc                # → ~/.bashrc にシンボリックリンク
    .config/
      nvim/
        init.lua           # → ~/.config/nvim/init.lua にシンボリックリンク
    .gitconfig.tmpl        # → ~/.gitconfig にテンプレート展開してコピー
```

`home/` ディレクトリの構造がそのまま `$HOME` にマッピングされます。`.tmpl` サフィックスを持つファイルはテンプレートとして処理され、変数が展開された上でデプロイされます。

## Configuration

設定は `~/.perpet/perpet.toml` に記述します。

```toml
[perpet]
version = 1

[settings]
default_mode = "symlink"     # デフォルトの管理方式: "symlink" or "copy"
editor = ""                  # 空の場合は $EDITOR を使用
git_auto_commit = false      # add/remove 時に自動コミット
git_remote = "origin"

[variables]
email = "you@example.com"
name = "Your Name"
is_work = false

# ファイルごとの設定（オプション）
[[files]]
path = ".ssh/config"
mode = "copy"                # このファイルはコピー方式で管理
```

## Templates

`.tmpl` サフィックスのファイルはテンプレートとして処理されます。

```gitconfig
# .gitconfig.tmpl
[user]
    name = {{ .name }}
    email = {{ .email }}

{{ if .is_work }}
[url "git@github-work:"]
    insteadOf = https://github.com/
{{ end }}
```

### サポートする構文

| 構文 | 説明 |
|------|------|
| `{{ .variable }}` | 変数を展開 |
| `{{ if .condition }}...{{ end }}` | 条件が true の場合にブロックを出力 |
| `{{ if .condition }}...{{ else }}...{{ end }}` | if/else |
| `{{ if not .condition }}...{{ end }}` | 否定条件 |

## Commands

| コマンド | 説明 |
|---------|------|
| `perpet init [url]` | dotfiles リポジトリを初期化 |
| `perpet add <path>` | ファイルを管理対象に追加 |
| `perpet remove <path>` | ファイルを管理対象から除去 |
| `perpet apply` | dotfiles を `$HOME` に適用 |
| `perpet diff [path]` | ソースとターゲットの差分を表示 |
| `perpet status` | 管理ファイルの同期状態を表示 |
| `perpet edit <path>` | ソースファイルをエディタで開く |
| `perpet list` | 管理対象ファイルの一覧を表示 |
| `perpet update` | リモートから取得して適用 |
| `perpet cd` | ソースディレクトリのパスを出力 |
| `perpet git <args>` | ソースリポジトリで git コマンドを実行 |

## Environment Variables

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `PERPET_SOURCE_DIR` | ソースディレクトリのパスを上書き | `~/.perpet/` |
| `EDITOR` | `perpet edit` で使用するエディタ | - |

## Requirements

- Zig 0.15.2 以上（ビルド時のみ）
- Git（Git 連携機能を使用する場合）

## License

MIT
