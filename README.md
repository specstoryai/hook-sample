# hook-sample

Placeholder project for testing the **curl|sh lazy shim** approach to
auto-installing and auto-running the SpecStory CLI from a Claude Code hook.

The idea: a tech lead commits a couple of files once, and every teammate who
opens this repo in Claude Code gets SpecStory bootstrapped automatically — no
manual install, no `sudo`, no `PATH` edits.

## What's wired up here

| File | Role |
| --- | --- |
| `.claude/settings.json` | Registers a `SessionStart` hook that runs the shim. |
| `.specstory/hook.sh` | "Ensure, then run" shim. Installs the pinned binary if missing, then runs `specstory sync`. Fails open. |
| `.specstory/install.sh` | No-sudo, version-pinnable installer. Drops one static binary into `~/.specstory/bin`. |
| `.specstory/cli/config.toml` | Committed behavior config (the "configure once" layer). |

## How it works

1. A teammate clones this repo and opens Claude Code in it.
2. The `SessionStart` hook fires and runs `.specstory/hook.sh`.
3. The shim checks for the pinned `specstory` version on `PATH` or in
   `~/.specstory/bin`. If it's missing, it downloads it (one tarball from
   GitHub Releases) into `~/.specstory/bin` — no sudo.
4. The shim runs `specstory sync`. Every later session reuses the cached binary
   and is instant.

The pinned version lives in **one place**: the `VERSION=` line at the top of
`.specstory/hook.sh`. Bump it in a PR to roll the whole team forward.

## Try the bootstrap by hand (no Claude Code needed)

You can exercise the exact path the hook takes:

```sh
# Simulate a fresh machine.
rm -rf ~/.specstory/bin

# Run the shim the way the hook does.
sh .specstory/hook.sh

# Confirm the binary landed and matches the pin.
~/.specstory/bin/specstory version
```
