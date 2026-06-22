#!/bin/sh
# Minimal, no-sudo SpecStory installer (the fallback delivery channel).
#
# Downloads ONE static binary from GitHub Releases into a user-writable dir and
# verifies it against a pinned SHA-256 before use. Driven by env vars:
#   SPECSTORY_VERSION    git tag to install (e.g. v1.13.0); default: latest
#   SPECSTORY_BIN_DIR    install dir; default: ~/.specstory/bin
#   SPECSTORY_CHECKSUMS  path to a checksums file to verify against (optional)
#
# In the productized design this logic lives inside the `specstory` binary and a
# central installer; it is spelled out here only so the prototype is testable.
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

# Download $1 to stdout using whatever HTTP client the machine has.
fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
  else echo "specstory-install: need 'curl' or 'wget' on PATH" >&2; return 1; fi
}

# SHA-256 of file $1, using whichever tool exists ("" if none).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo ""; fi
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
fetch "$URL" > "$TMP/$FILENAME"

# Verify against the pinned checksum when one is available. A mismatch is FATAL
# (never install a tampered artifact); a missing tool or entry only warns.
if [ -n "$SPECSTORY_CHECKSUMS" ] && [ -r "$SPECSTORY_CHECKSUMS" ]; then
  expected=$(grep " $FILENAME\$" "$SPECSTORY_CHECKSUMS" | awk '{print $1}')
  actual=$(sha256_of "$TMP/$FILENAME")
  if [ -z "$expected" ]; then
    echo "specstory-install: WARNING no checksum for $FILENAME; proceeding unverified" >&2
  elif [ -z "$actual" ]; then
    echo "specstory-install: WARNING no sha256 tool; proceeding unverified" >&2
  elif [ "$expected" != "$actual" ]; then
    echo "specstory-install: CHECKSUM MISMATCH for $FILENAME" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    exit 1
  else
    echo "specstory-install: checksum verified" >&2
  fi
else
  echo "specstory-install: WARNING no checksums file; proceeding unverified" >&2
fi

tar -xz -C "$TMP" -f "$TMP/$FILENAME"
mv "$TMP/$BIN_NAME" "$BIN_DIR/$BIN_NAME"
chmod +x "$BIN_DIR/$BIN_NAME"
echo "specstory-install: installed -> $BIN_DIR/$BIN_NAME" >&2
