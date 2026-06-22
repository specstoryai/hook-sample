#!/bin/sh
# SpecStory bootstrap shim — committed to the repo by the tech lead.
#
# Contract: "ensure, then run." Guarantees the pinned specstory binary is
# available (installing it via the most trusted channel present), then runs it.
# FAILS OPEN: any problem here must never block the coding-agent session.
#
# NOTE: in the productized design this whole file collapses into a one-line
# `specstory hook <agent> <event>` call in settings.json, with the tiering below
# living INSIDE the binary. It is spelled out here only so the prototype is
# testable before the npm package and `specstory hook` subcommand exist.

# --- The one knob a tech lead turns: pin the team's version here. ----------
VERSION="v1.13.0"
NPM_PKG="@specstory/cli"
# ---------------------------------------------------------------------------

BIN_DIR="$HOME/.specstory/bin"
BIN="$BIN_DIR/specstory"
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHECKSUMS="$HOOK_DIR/cli/checksums.txt"

# True if the binary/command in $1 reports our pinned version (tolerates the
# tag-vs-bare-number mismatch: pin "v1.13.0" vs output "1.13.0 (SpecStory)").
have_version() {
  want="${VERSION#v}"
  got=$("$1" version 2>/dev/null | awk '{print $1}')
  [ "$got" = "$want" ]
}

# Resolve a runner, preferring an already-present binary, then trusted channels.
RUN=""
if command -v specstory >/dev/null 2>&1 && have_version specstory; then
  RUN="specstory"                                    # already on PATH
elif have_version "$BIN"; then
  RUN="$BIN"                                          # already in our cache
elif command -v npx >/dev/null 2>&1 && \
     npx --yes "${NPM_PKG}@${VERSION#v}" version >/dev/null 2>&1; then
  RUN="npx --yes ${NPM_PKG}@${VERSION#v}"             # (1) npm registry (Node present)
elif command -v brew >/dev/null 2>&1 && \
     { brew list specstory >/dev/null 2>&1 || brew install specstoryai/tap/specstory >&2 2>&1; } && \
     have_version specstory; then
  RUN="specstory"                                     # (2) Homebrew tap (live today)
elif SPECSTORY_VERSION="$VERSION" SPECSTORY_BIN_DIR="$BIN_DIR" \
       SPECSTORY_CHECKSUMS="$CHECKSUMS" sh "$HOOK_DIR/install.sh" >&2; then
  RUN="$BIN"                                          # (3) checksum-verified download
else
  echo "specstory-hook: no install channel available; skipping capture" >&2
  echo "specstory-hook: tip - 'brew install specstoryai/tap/specstory'" >&2
  exit 0                                              # fail open
fi

# Do the work. Output to stderr (keep the hook's stdout clean); swallow failures.
case "$RUN" in
  npx*) $RUN sync >&2 || echo "specstory-hook: sync failed (ignored)" >&2 ;;
  *)    "$RUN" sync >&2 || echo "specstory-hook: sync failed (ignored)" >&2 ;;
esac
exit 0
