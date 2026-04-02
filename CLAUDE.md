# CLAUDE.md - perpet

## Project Overview

perpet は初心者向けの dotfiles 管理 CLI ツール。Zig 0.15.2 で開発。

## Build & Test

```bash
zig build                    # ビルド（バイナリ: zig-out/bin/perpet）
zig build run -- <args>      # ビルド＋実行
zig build test               # 全テスト実行
```

## Architecture

### ディレクトリ構成

```
src/
  main.zig          # エントリポイント: 引数パース → cli/mod.zig にディスパッチ
  root.zig          # ライブラリモジュール（core/ を再エクスポート）
  cli/              # サブコマンド実装。各ファイルが pub fn run(args: *ArgIterator) !void をエクスポート
    mod.zig         # ディスパッチャ + ヘルプテキスト
  core/             # ビジネスロジック。CLI に依存しない
    config.zig      # Config 型の定義とロード/セーブ
    manifest.zig    # ManagedFile 列挙、ソース→ターゲットのパス解決
    template.zig    # {{ .var }} / {{ if }} テンプレートエンジン
    fs_ops.zig      # symlink/copy/diff のファイルシステム操作
    git_ops.zig     # std.process.Child で git をサブプロセス実行
    paths.zig       # クロスプラットフォームのホーム/ソースディレクトリ解決
    toml.zig        # perpet.toml 用の最小限 TOML パーサー
```

### 設計原則

- **外部依存ゼロ**: Zig 標準ライブラリのみ使用
- **core/ は CLI に依存しない**: core/ のモジュールは cli/ をインポートしない
- **各 CLI サブコマンドは独立**: `cli/<command>.zig` が `pub fn run` をエクスポート
- **テンプレートエンジンはシングルパス**: AST を構築せずストリーミング処理

### ユーザーデータ構造

```
~/.perpet/                 # ソースディレクトリ (git repo)
  perpet.toml              # 設定 + 変数 + ファイル個別設定
  home/                    # $HOME のミラー構造（実ファイル名をそのまま使用）
    .bashrc
    .gitconfig.tmpl        # .tmpl = テンプレート処理対象
```

## Conventions

- エラーメッセージは stderr に出力し、ユーザーが理解できる文面にする
- 破壊的操作（上書き/削除）前は確認プロンプトを表示する（`--force` でスキップ可）
- TOML パーサーは完全な TOML 仕様ではなく、perpet.toml に必要な最小限のサブセットのみ実装
- クロスプラットフォーム対応: パス操作には必ず `std.fs.path` を使用
- テストは各 core/ モジュールに `test` ブロックとして記述
- Zig 0.15 の API 注意点:
  - `std.ArrayList(T)` は unmanaged: `.empty` で初期化、`deinit(allocator)` / `append(allocator, item)` / `toOwnedSlice(allocator)`
  - `std.StringHashMap(V)` は managed: `.init(allocator)` で初期化、`deinit()` で解放
  - `std.process.Child.StdIo` は PascalCase: `.Pipe`, `.Inherit`, `.Ignore`
  - `File.writer(buffer)` は `[]u8` バッファが必要。直接 `File.writeAll()` の方がシンプル
  - CLI サブコマンドは `@import("../core/mod.zig")` で core にアクセス（`@import("perpet")` は不可）
