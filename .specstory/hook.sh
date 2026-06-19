#!/bin/sh
# SpecStory bootstrap shim — committed to the repo by the tech lead.
#
# Contract: "ensure, then run." It guarantees the pinned specstory binary is
# present (installing it into the user's home dir with no sudo if needed),
# then runs it.
#
# This script FAILS OPEN. Any problem here (offline, GitHub down, bad version)
# must never block or break the developer's coding-agent session. Every failure
# path logs to stderr and exits 0.

# --- The one knob a tech lead turns: pin the team's version here. ----------
VERSION="v1.13.0"
# ---------------------------------------------------------------------------

BIN_DIR="$HOME/.specstory/bin"
BIN="$BIN_DIR/specstory"
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# True if the binary at $1 reports our pinned version.
# The pin is a git tag (e.g. "v1.13.0") but `specstory version` prints the bare
# number ("1.13.0 (SpecStory)"), so strip a leading "v" and match the first token.
have_version() {
  want="${VERSION#v}"
  got=$("$1" version 2>/dev/null | awk '{print $1}')
  [ "$got" = "$want" ]
}

# 1. Prefer an already-installed matching binary: PATH first, then our cache.
if command -v specstory >/dev/null 2>&1 && have_version specstory; then
  RESOLVED="specstory"
elif have_version "$BIN"; then
  RESOLVED="$BIN"
else
  # 2. Missing or wrong version -> install the pinned version (no sudo).
  if SPECSTORY_VERSION="$VERSION" SPECSTORY_BIN_DIR="$BIN_DIR" \
       sh "$HOOK_DIR/install.sh" >&2; then
    RESOLVED="$BIN"
  else
    echo "specstory-hook: install failed; skipping capture" >&2
    exit 0   # fail open
  fi
fi

# 3. Do the actual work. `sync` is a one-shot, non-interactive capture of
#    existing sessions. Output goes to stderr so we never pollute the hook's
#    stdout protocol, and we swallow failures to stay fail-open.
"$RESOLVED" sync >&2 || echo "specstory-hook: sync failed (ignored)" >&2
exit 0
