#!/bin/sh
# Minimal, no-sudo SpecStory installer.
#
# Why this exists separately from the repo's top-level install.sh:
#   - It installs ONE static binary into a user-writable dir (no sudo).
#   - It is driven entirely by env vars so the hook shim can pin a version.
# It downloads the same release artifact published on GitHub Releases.
set -e

REPO="specstoryai/getspecstory"
BIN_NAME="specstory"
BIN_DIR="${SPECSTORY_BIN_DIR:-$HOME/.specstory/bin}"
VERSION="${SPECSTORY_VERSION:-latest}"

# Detect platform (matches the release artifact naming convention).
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "specstory-install: unsupported arch '$ARCH'" >&2; exit 1 ;;
esac
case "$OS" in
  darwin) OS="Darwin" ;;
  linux) OS="Linux" ;;
  *) echo "specstory-install: unsupported os '$OS'" >&2; exit 1 ;;
esac

# Download $1 to stdout using whatever HTTP client the machine has. Clean macOS
# ships curl; many minimal Linux images ship only wget (or neither).
fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$1"
  else
    echo "specstory-install: need 'curl' or 'wget' on PATH" >&2
    return 1
  fi
}

# Resolve "latest" to a concrete tag if no version was pinned.
if [ "$VERSION" = "latest" ]; then
  VERSION=$(fetch "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi
[ -n "$VERSION" ] || { echo "specstory-install: could not resolve version" >&2; exit 1; }

FILENAME="SpecStoryCLI_${OS}_${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$FILENAME"

mkdir -p "$BIN_DIR"
TMP=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

echo "specstory-install: downloading $VERSION ($OS/$ARCH)..." >&2
fetch "$URL" | tar -xz -C "$TMP"
mv "$TMP/$BIN_NAME" "$BIN_DIR/$BIN_NAME"
chmod +x "$BIN_DIR/$BIN_NAME"
echo "specstory-install: installed -> $BIN_DIR/$BIN_NAME" >&2
