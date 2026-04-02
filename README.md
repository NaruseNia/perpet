# perpet

Beginner-friendly dotfiles manager written in Zig.

Less complex than chezmoi, more powerful than GNU Stow — the sweet spot for dotfiles management.

**[日本語版 README はこちら](README_ja.md)**

## Features

- **Simple file mapping** - The `home/` directory directly mirrors `$HOME`. No special filename conventions
- **Symlink & copy** - Choose the management method per file
- **Template engine** - Manage per-machine configurations with `{{ .variable }}` syntax
- **Git integration** - Built-in basic Git operations, from repository init to push
- **Cross-platform** - macOS / Linux / Windows support
- **Single binary** - Zero external dependencies. Download and use immediately

## Quick Start

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/NaruseNia/perpet/main/scripts/install.sh | sh
```

Or build from source (requires Zig 0.15.2 or later):

```bash
git clone https://github.com/NaruseNia/perpet.git
cd perpet
zig build -Doptimize=ReleaseSafe
# Binary is output to zig-out/bin/perpet
```

### Initial Setup

```bash
# Initialize a dotfiles repository
perpet init

# Set up from an existing remote repository
perpet init https://github.com/yourname/dotfiles.git
```

### Basic Usage

```bash
# Add a dotfile to management
perpet add .bashrc
perpet add .config/nvim/init.lua

# Add as a template (for per-machine customization)
perpet add .gitconfig --template

# List managed files
perpet list

# Apply dotfiles (create symlinks/copies in $HOME)
perpet apply

# Check sync status
perpet status

# Show differences between source and target
perpet diff

# Pull remote changes and apply
perpet update
```

## How It Works

perpet manages dotfiles using the `~/.perpet/` directory.

```
~/.perpet/
  perpet.toml              # Configuration file
  home/                    # Mirror of $HOME
    .bashrc                # → symlinked to ~/.bashrc
    .config/
      nvim/
        init.lua           # → symlinked to ~/.config/nvim/init.lua
    .gitconfig.tmpl        # → template-rendered and copied to ~/.gitconfig
```

The structure of the `home/` directory maps directly to `$HOME`. Files with the `.tmpl` suffix are processed as templates — variables are expanded before deployment.

## Configuration

Configuration is written in `~/.perpet/perpet.toml`.

```toml
[perpet]
version = 1

[settings]
default_mode = "symlink"     # Default management method: "symlink" or "copy"
editor = ""                  # Empty = use $EDITOR
git_auto_commit = false      # Auto-commit on add/remove
git_remote = "origin"

[variables]
email = "you@example.com"
name = "Your Name"
is_work = false

# Per-file settings (optional)
[[files]]
path = ".ssh/config"
mode = "copy"                # Manage this file using copy method
```

## Templates

Files with the `.tmpl` suffix are processed as templates.

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

### Supported Syntax

| Syntax | Description |
|--------|-------------|
| `{{ .variable }}` | Variable substitution |
| `{{ if .condition }}...{{ end }}` | Output block when condition is true |
| `{{ if .condition }}...{{ else }}...{{ end }}` | if/else |
| `{{ if not .condition }}...{{ end }}` | Negated condition |

## Commands

| Command | Description |
|---------|-------------|
| `perpet init [url]` | Initialize a dotfiles repository |
| `perpet add <path>` | Add a file to management |
| `perpet remove <path>` | Remove a file from management |
| `perpet apply` | Apply dotfiles to `$HOME` |
| `perpet diff [path]` | Show differences between source and target |
| `perpet status` | Show sync status of managed files |
| `perpet edit <path>` | Open a source file in your editor |
| `perpet list` | List all managed files |
| `perpet update` | Pull from remote and apply |
| `perpet cd` | Print the source directory path |
| `perpet git <args>` | Run git commands in the source repository |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PERPET_SOURCE_DIR` | Override source directory path | `~/.perpet/` |
| `EDITOR` | Editor used by `perpet edit` | - |

## Requirements

- Zig 0.15.2 or later (build time only)
- Git (if using Git integration features)

## License

MIT
