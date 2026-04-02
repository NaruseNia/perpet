# perpet 要件定義書

## 1. プロジェクト概要

| 項目 | 内容 |
|------|------|
| プロダクト名 | perpet |
| 種別 | CLI ツール |
| 開発言語 | Zig 0.15.2 |
| 目的 | 初心者でも直感的に使える dotfiles 管理ツール |
| ポジショニング | chezmoi より軽量・シンプル、GNU Stow より高機能 |

## 2. 対象ユーザー

- dotfiles 管理を始めたい初心者
- chezmoi の学習コストを避けたい中級者
- 複数マシン間で設定を共有したいユーザー

## 3. 対応プラットフォーム

| OS | サポートレベル |
|----|--------------|
| macOS (arm64/x86_64) | Tier 1 |
| Linux (x86_64/arm64) | Tier 1 |
| Windows (x86_64) | Tier 2（ネイティブ対応、シンボリックリンクは開発者モード必須） |

## 4. 機能要件

### 4.1 ファイル管理

#### FR-001: シンボリックリンク方式
- ソースディレクトリのファイルから `$HOME` へシンボリックリンクを作成する
- デフォルトの管理方式とする

#### FR-002: コピー方式
- ソースディレクトリのファイルを `$HOME` にコピーする
- ファイルごとに `perpet.toml` の `[[files]]` セクションで指定可能
- `.ssh/config` のようにシンボリックリンクでは問題が生じるファイル向け

#### FR-003: ファイルマッピング
- `~/.perpet/home/` 配下のディレクトリ構造が `$HOME` にそのままマッピングされる
- マッピング規則: `~/.perpet/home/<relative_path>` → `$HOME/<relative_path>`
- `.tmpl` サフィックスはマッピング時に除去される
- chezmoi 式のファイル名エンコーディング (`dot_`, `executable_` 等) は使用しない

### 4.2 テンプレートエンジン

#### FR-010: 変数展開
- `{{ .variable_name }}` 構文で変数を展開する
- 変数は `perpet.toml` の `[variables]` セクションで定義する
- 未定義変数は空文字列に展開する

#### FR-011: 条件分岐
- `{{ if .condition }}...{{ end }}` 構文で条件分岐を行う
- `{{ if .condition }}...{{ else }}...{{ end }}` 構文で if/else を行う
- `{{ if not .condition }}...{{ end }}` 構文で否定条件を行う
- 条件変数は boolean 値 (`true`/`false`) として評価する

#### FR-012: テンプレート対象ファイルの指定
- `.tmpl` サフィックスを持つファイルは自動的にテンプレート処理対象となる
- `[[files]]` セクションで `template = true` を明示的に指定することも可能

#### FR-013: 組み込み変数
- `os`: 実行時の OS を自動検出 (`"macos"`, `"linux"`, `"windows"`)
- `arch`: 実行時のアーキテクチャを自動検出 (`"x86_64"`, `"aarch64"`)
- `hostname`: システムのホスト名を自動取得
- ユーザー定義変数で上書き可能

### 4.3 Git 連携

#### FR-020: Git 初期化
- `perpet init` でソースディレクトリに `git init` を実行する
- URL 引数指定時は `git clone` を実行する

#### FR-021: Git パススルー
- `perpet git <args...>` でソースディレクトリに対して任意の git コマンドを実行する

#### FR-022: 自動コミット
- `git_auto_commit = true` 設定時、`add` / `remove` 操作後に自動で `git commit` を実行する

#### FR-023: リモート同期
- `perpet update` で `git pull --rebase` を実行後、`apply` を実行する

### 4.4 CLI サブコマンド

#### FR-030: `init [url]`
- 引数なし: `~/.perpet/` ディレクトリ作成、`perpet.toml` 雛形生成、`git init`
- URL 指定: 指定 URL から `git clone` してソースディレクトリに配置
- 既にソースディレクトリが存在する場合はエラー

#### FR-031: `add <path> [--template] [--mode <symlink|copy>]`
- `$HOME/<path>` のファイルを `~/.perpet/home/<path>` にコピー
- `--template` 指定時は `.tmpl` サフィックスを付与
- `--mode` 指定時は `perpet.toml` の `[[files]]` に設定を追加
- ディレクトリ構造を自動作成
- `git_auto_commit = true` の場合、自動で `git add` + `git commit`

#### FR-032: `remove <path> [--restore]`
- `~/.perpet/home/<path>` を削除
- `[[files]]` エントリがあれば削除
- `--restore` 指定時、管理前の状態に復元（シンボリックリンクなら削除、コピーなら元ファイルは残す）
- `git_auto_commit = true` の場合、自動で `git rm` + `git commit`

#### FR-033: `apply [--dry-run] [--force]`
- 全管理ファイルについてテンプレート処理 → シンボリックリンク/コピーを実行
- ターゲットに既存の非管理ファイルがある場合、確認プロンプトを表示
- `--dry-run`: 実際の操作は行わず、実行予定の内容を表示
- `--force`: 確認プロンプトをスキップして上書き

#### FR-034: `diff [path]`
- 管理ファイルのソース（テンプレートレンダリング後）とターゲットの差分を表示
- `path` 指定時は特定ファイルのみ
- 引数なしの場合は全管理ファイルの差分を表示

#### FR-035: `status`
- 各管理ファイルの状態を表示
  - `ok`: ソースとターゲットが一致
  - `modified`: ターゲットが変更されている
  - `missing`: ターゲットが存在しない
  - `unlinked`: シンボリックリンクが壊れている

#### FR-036: `edit <path>`
- `$EDITOR` (または `perpet.toml` の `editor` 設定) でソースファイルを開く
- `$EDITOR` が未設定の場合はエラーメッセージを表示

#### FR-037: `list`
- 全管理ファイルを一覧表示
- 各ファイルについてモード (symlink/copy)、テンプレート有無を表示

#### FR-038: `update`
- `git pull --rebase` を実行
- 成功後 `apply` を実行
- コンフリクト発生時はエラーメッセージを表示し、手動解決を促す

#### FR-039: `cd`
- ソースディレクトリの絶対パスを標準出力に出力
- シェル連携用: `cd $(perpet cd)`

#### FR-040: `git <args...>`
- 残り引数をすべて git コマンドに渡してソースディレクトリで実行
- 標準出力/標準エラー出力はそのまま表示

### 4.5 設定ファイル

#### FR-050: 設定ファイルの場所
- ソースディレクトリ内: `~/.perpet/perpet.toml`
- 環境変数 `PERPET_SOURCE_DIR` でソースディレクトリを上書き可能

#### FR-051: 設定スキーマ

```toml
[perpet]
version = 1                      # スキーマバージョン

[settings]
default_mode = "symlink"         # "symlink" | "copy"
editor = ""                      # 空 = $EDITOR を使用
git_auto_commit = false          # add/remove 時に自動コミット
git_remote = "origin"            # デフォルトのリモート名

[variables]
# ユーザー定義テンプレート変数（型: 文字列 or 真偽値）
hostname = "myhost"
email = "user@example.com"
name = "Jane Doe"
is_work = false

# ファイルごとの設定上書き（オプション）
[[files]]
path = ".bashrc"                 # home/ からの相対パス
mode = "copy"                    # この設定のみ上書き
# template = false               # デフォルト: .tmpl サフィックスに従う
```

## 5. 非機能要件

### NFR-001: パフォーマンス
- 1000 ファイル管理時でも `apply` が 5 秒以内に完了すること

### NFR-002: 外部依存
- Zig 標準ライブラリのみ使用。外部パッケージ依存なし
- git コマンドはシステムにインストール済みであることを前提とする

### NFR-003: エラーハンドリング
- ユーザーフレンドリーなエラーメッセージを表示する
- スタックトレースは `--verbose` フラグ使用時のみ表示
- 破壊的操作（上書き、削除）前に確認プロンプトを表示する

### NFR-004: シングルバイナリ
- Zig のクロスコンパイルを活用し、単一バイナリとして配布可能にする

### NFR-005: 後方互換性
- `perpet.toml` の `version` フィールドでスキーマバージョンを管理
- バージョン変更時はマイグレーションパスを提供する

## 6. ディレクトリ構成（開発側）

```
perpet/
  build.zig
  build.zig.zon
  src/
    main.zig              # エントリポイント
    root.zig              # ライブラリモジュール
    cli/
      mod.zig             # CLI ディスパッチャ
      init.zig
      add.zig
      remove.zig
      apply.zig
      diff.zig
      status.zig
      edit.zig
      list.zig
      update.zig
      cd.zig
      git.zig
    core/
      mod.zig             # core 再エクスポート
      config.zig          # 設定ロード/セーブ
      manifest.zig        # ファイル列挙・パス解決
      template.zig        # テンプレートエンジン
      fs_ops.zig          # ファイルシステム操作
      git_ops.zig         # git subprocess ラッパー
      paths.zig           # クロスプラットフォームパス解決
      toml.zig            # TOML パーサー
  docs/
    requirements.md       # 本ドキュメント
```

## 7. 用語集

| 用語 | 定義 |
|------|------|
| ソースディレクトリ | perpet が管理するファイルを格納するディレクトリ (`~/.perpet/`) |
| ターゲット | ファイルのデプロイ先 (`$HOME` 配下) |
| マニフェスト | 管理対象ファイルの一覧と設定 |
| テンプレート | 変数展開・条件分岐が可能なファイル (`.tmpl` サフィックス) |
| 管理モード | ファイルの展開方式 (symlink または copy) |
