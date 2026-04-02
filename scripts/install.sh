#!/bin/sh
set -eu

REPO="NaruseNia/perpet"
INSTALL_DIR="/usr/local/bin"

# Detect OS
case "$(uname -s)" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
    *)
        echo "error: unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

# Detect architecture
case "$(uname -m)" in
    x86_64|amd64)  ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *)
        echo "error: unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

# Get latest version
VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
    echo "error: failed to fetch latest version" >&2
    exit 1
fi

ARCHIVE="perpet-${VERSION}-${ARCH}-${OS}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE}"

echo "Installing perpet ${VERSION} (${OS}/${ARCH})..."

# Download and extract
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "${TMPDIR}/${ARCHIVE}"
tar xzf "${TMPDIR}/${ARCHIVE}" -C "$TMPDIR"

# Install binary
if [ -w "$INSTALL_DIR" ]; then
    cp "${TMPDIR}/perpet-${VERSION}-${ARCH}-${OS}/perpet" "${INSTALL_DIR}/perpet"
else
    echo "Installing to ${INSTALL_DIR} (requires sudo)..."
    sudo cp "${TMPDIR}/perpet-${VERSION}-${ARCH}-${OS}/perpet" "${INSTALL_DIR}/perpet"
fi

chmod +x "${INSTALL_DIR}/perpet"

echo "Installed perpet ${VERSION} to ${INSTALL_DIR}/perpet"
echo ""
echo "Get started:"
echo "  perpet init          Initialize a new dotfiles repo"
echo "  perpet --help        Show all commands"
