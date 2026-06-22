# SpecStory Autopilot

_Zero-touch AI coding-history capture for any repo, any agent, any machine._

> **The north star:** a tech lead commits **one thing** to a repo. From then on,
> every teammate — on macOS, Linux, or WSL, using Claude Code, Cursor, Codex,
> Gemini, or Droid — has their AI coding sessions captured automatically. No
> install step. No `sudo`. No "did you remember to run specstory?" Nothing on
> the machine to set up. SpecStory becomes a property of the **repo**, not the
> workstation.

This is the same shape as `.editorconfig`, `.gitattributes`, or a `pre-commit`
config: check it in once, and it "just works" for everyone who touches the repo
— except here the payload is *complete, durable history of how the code was
actually built with AI*.

---

## Why this is worth building

Today, getting a team onto SpecStory means asking every developer to install a
CLI and remember to run it. That fails the way all "remember to" workflows fail:
unevenly, and worst for exactly the busy senior engineers whose sessions are
most valuable. The history you capture is only as complete as your least
disciplined teammate's habits.

Autopilot inverts that. The unit of adoption becomes the **repository**, decided
once by one person. Coverage goes from "whoever opted in" to "everyone who
clones it." That is the difference between a tool and infrastructure.

---

## Design principles (the non-negotiables)

These are not aspirations — every one was forced on us by a real failure or
finding during prototyping (see [What we've validated](#what-weve-already-validated)).

1. **Fail open, always.** A capture mechanism must *never* block, slow, or break
   a developer's actual coding session. Offline, GitHub down, wrong arch, no
   download tool — every failure path logs quietly and exits `0`. The first time
   it breaks someone's session, the team rips it out forever.
2. **No `sudo`, no PATH surgery.** Install one static binary into `~/.specstory/bin`.
   Reference it by absolute path. Works on locked-down corp laptops with no admin
   rights. PATH manipulation is the #1 source of "works on my machine."
3. **Pinned and reproducible.** The whole team runs one version, pinned in a
   committed file. Bumping it is a normal PR. No "latest" drift.
4. **Invisible by default, observable on demand.** Steady state is silent. But a
   developer can always see that capture is active and what it did.
5. **Bootstrap ≠ capture.** Installing the tool and recording a session are
   different events that happen at different moments. Conflating them is the
   single most common design mistake here.
6. **One asset, many platforms.** A single static Go binary that runs on
   macOS/Linux, arm64/x86_64, glibc/musl. Distribution is "download one file."

---

## Dead-simple setup: three tiers

The same engine powers all three. You pick the scope.

### Tier 0 — Just me, everywhere (global)

```zsh
specstory init --global
```

Writes a user-level agent hook (`~/.claude/settings.json`, etc.) and
`~/.specstory/cli/config.toml`. Every repo you open in a supported agent is now
captured. Nothing committed anywhere. This is the "I'm a solo dev / I want this
on all my own projects" path.

### Tier 1 — This repo, my whole team (committed)

```zsh
specstory init        # run once in the repo, commit the result
```

Scaffolds the committed enrollment (below), so **anyone** who clones the repo
gets capture automatically — the bootstrap installs the CLI on their machine on
first agent session. This is the tech-lead path and the heart of Autopilot.

### Tier 2 — My whole org, many repos (GitHub App)

Install the **SpecStory GitHub App** on the org. It opens a one-click enrollment
PR (Tier 1's files) into each selected repo, and keeps the pinned version current
with automated bump PRs thereafter. This is "I have 40 repos and I'm not editing
40 of them by hand." See [The GitHub App](#the-github-app).

---

## What gets committed (Tier 1)

Only **declarative config** — no shell scripts:

```
.specstory/cli/config.toml    # pinned version + behavior (repo-specific)
.specstory/cli/checksums.txt  # SHA-256 of each release artifact — the in-repo audit anchor
.claude/settings.json         # one-line hook per event → calls `specstory hook …`
.cursor/… etc.                # one stanza per agent the repo enables
.gitignore                    # ignores generated history/debug + per-user local overrides
```

There is deliberately **no `bootstrap.sh` or `install.sh` in the repo.** All
imperative logic lives in the `specstory` binary (a `specstory hook` subcommand)
and in the delivery channels (the npm package / a central installer) — one
canonical copy each, never duplicated across repos. A bug fix ships in the next
release, not in N pull requests. The committed footprint is a few lines of config
plus a list of checksums; a teammate can audit all of it in under a minute.

> The prototype repo (`specstoryai/hook-sample`) still carries `hook.sh` +
> `install.sh` because the `specstory hook` subcommand and the npm package don't
> exist yet. Those scripts are the *spelled-out* version of what the binary will
> do — a staging ground, not the end state.

---

## Architecture

```
                   ┌─────────────────────────────────────────────┐
   teammate opens  │  Coding agent (Claude Code / Cursor / …)     │
   the repo  ─────▶│   • loads committed hook config from repo    │
                   │   • one-time "trust this folder" prompt      │
                   └───────────────┬─────────────────────────────┘
                                   │ fires hooks
                   ┌───────────────▼─────────────────────────────┐
        SessionStart  ──▶  bootstrap.sh  ──▶  install.sh          │
                   │      (ensure binary present, no sudo)        │
        Stop / End    ──▶  bootstrap.sh  ──▶  specstory sync       │
                   └───────────────┬─────────────────────────────┘
                                   │
                   ┌───────────────▼─────────────────────────────┐
                   │  ~/.specstory/bin/specstory  (cached, pinned)│
                   │   • reads agent transcript (JSONL)           │
                   │   • writes .specstory/history/*.md           │
                   │   • optional cloud sync (if logged in)       │
                   └──────────────────────────────────────────────┘
```

### Delivery — getting the binary onto the machine

This is the crux. The committed hook calls `specstory hook <agent> <event>`. If
the pinned binary is already present (on `PATH` or in `~/.specstory/bin`) it just
runs — instant. If it's missing, it installs through the most trusted channel
available, in order:

1. **`npx @specstory/cli@<pinned>`** — primary. `npx` *is* download-cache-and-run:
   it pulls the right platform binary (the Go binary wrapped as platform
   `optionalDependencies`) from the **npm registry** (signing + provenance) and
   runs the `hook` subcommand. Version-pinned inline, no committed script, no
   `curl|sh`. The kicker: **Claude Code is itself an npm package, so Node/`npx`
   is already present** in any Claude Code environment — zero new prerequisite.
2. **Homebrew tap** (`brew install specstoryai/tap/specstory`) — **live today**
   (`specstoryai/homebrew-tap`). Works on **macOS and Linux/WSL** (Homebrew runs
   on both). For non-Node environments. Trusted, no sudo, auditable, standard
   upgrade/uninstall.
3. **Checksum-verified GitHub Release download** — the zero-prerequisite fallback
   (needs only `curl` or `wget`). The downloaded tarball is verified against the
   SHA-256 committed in `.specstory/cli/checksums.txt` before it runs.
4. **Fail open** — none available? Print a one-line `brew install …` hint and
   exit 0. The agent session is never blocked.

**A GitHub App cannot perform this step** — it runs server-side against GitHub
and has no path onto a developer's laptop. Binary delivery is always local
(npx / brew / download); the App's role is enrollment only (below).

#### Why this feels safe — the levers

Independent of channel:

- **Version pinning** — `@1.13.0`, a tag, a versioned URL. Never "latest."
- **Checksum committed in-repo** — the expected SHA-256 lives in
  `.specstory/cli/checksums.txt` (declarative, ~four lines). The artifact cannot
  change underneath you without the hash mismatching. A mismatch is fatal; the
  install refuses to run a tampered binary.
- **Registry provenance** — npm `--provenance` (Sigstore) ties the published
  package to the exact CI build; Homebrew inherits the tap's audit trail.
- **Signed + notarized binary** — Developer-ID signing + notarization on macOS
  (closes the Gatekeeper gap), cosign/Sigstore attestation on the artifact.

Version detection tolerates the tag-vs-bare-number mismatch (pin is `v1.13.0`,
binary reports `1.13.0`).

#### Status today

Two of the three channels are real right now — before any new work:

| Tier | Channel | Status |
| --- | --- | --- |
| 1 | `npx @specstory/cli@<pinned>` | ⏳ pending npm publish (the one remaining build item) |
| 2 | `brew install specstoryai/tap/specstory` | ✅ live — macOS **and** Linux/WSL; tracks stable |
| 3 | checksum-verified GitHub Release download | ✅ live & tested (macOS; glibc + musl Linux; arm64 + x86_64) |
| — | fail open | ✅ |

So a clean machine already has two trusted channels (brew on macOS/Linux, the
checksum-verified download everywhere); the npx tier slots in on top once the
package is published. The prototype proves the chain degrades gracefully until
then — an unpublished `npx` falls straight through to the verified download.

Resolution order in the hook: **already-installed → npx → brew → checksum-verified
download → fail open.**

### Capture timing — the part that matters

| Hook event | Role | Why |
| --- | --- | --- |
| `SessionStart` | **bootstrap** (install the CLI) | The transcript doesn't exist yet, so there is nothing to capture — but it's the perfect moment to guarantee the tool is present. |
| `Stop` | **capture after each turn** | Fires when the agent finishes responding; the transcript now has content. Continuous, near-live history. |
| `SessionEnd` | **capture once at the end** | Lower overhead alternative to `Stop` if per-turn syncing is too chatty. |

A future refinement is starting a **background watcher** at `SessionStart`
(`specstory watch`) for truly live capture, with `Stop`/`SessionEnd` as the
guaranteed flush.

---

## Lifecycle

**First session on a clean machine**

```
clone repo → open agent → trust prompt (one time) →
  SessionStart: download v1.13.0 → ~/.specstory/bin  (≈1s, once ever) →
  …developer works… →
  Stop: specstory sync → .specstory/history/<ts>-<slug>.md appears
```

**Every session after that**

```
open agent → (already trusted) →
  SessionStart: version match → instant, no download →
  Stop: sync → history updated
```

**Version bump (tech lead edits the pin, merges PR)**

```
teammate pulls → next SessionStart: installed version ≠ pin →
  download new version once → continue
```

Self-healing: delete the cache, corrupt the binary, switch machines — the next
session re-bootstraps.

---

## Cross-platform matrix

| Platform | Status | Notes |
| --- | --- | --- |
| macOS arm64 | ✅ validated | Gatekeeper: see below |
| macOS x86_64 | ✅ (asset + detection correct) | needs notarization for clean machines |
| Linux x86_64 — glibc | ✅ validated (Debian) | |
| Linux x86_64 — musl | ✅ validated (Alpine) | static binary runs on musl |
| Linux arm64 — musl | ✅ validated (Alpine) | |
| **WSL** | ✅ by construction | WSL is Linux; the Linux binary + shim apply unchanged |
| Download tool | ✅ `curl` **or** `wget` | minimal images often have only one |

**The macOS Gatekeeper item is the one true productization gap.** The released
binary is currently only adhoc-signed and fails `spctl` assessment; it runs after
a `curl|tar` download only because that path sets no quarantine attribute. To be
bulletproof on clean Macs (and survive MDM policies), the release binary should
be **Developer-ID signed and notarized**. This is a build-pipeline change, not an
Autopilot change.

---

## Multi-agent matrix

The bootstrap is agent-agnostic; only the *trigger surface* differs. The engine
covers any agent two ways: native hooks where they exist, a fallback where they
don't.

| Agent | Trigger surface | Mechanism |
| --- | --- | --- |
| Claude Code | `.claude/settings.json` hooks | ✅ validated (SessionStart + Stop) |
| Cursor | project rules / hooks | native if available |
| Codex CLI | project config | native if available |
| Gemini CLI | project config | native if available |
| Droid CLI | project config | native if available |
| _any agent_ | **git hooks** (`post-commit`, `post-checkout`) | fallback: `specstory sync` after the fact |
| _any agent_ | **`specstory run <agent>`** | fallback: live-wrapper model |

The fallbacks matter: even for an agent with no hook system, a committed git hook
(activated once via `core.hooksPath`) still captures history. No agent is left out.

---

## The GitHub App (enrollment only — never binary delivery)

To be explicit: the App **never** installs the binary on anyone's machine — it
can't reach a laptop. It operates server-side on your repos. The binary always
arrives locally via npx / brew / download (above). With that boundary clear, the
App turns Tier 1 into a fleet operation and adds an optional server-side half.

**Enrollment at scale**

- Install on an org or selected repos.
- For each repo, open a clean PR that adds the committed enrollment files. One
  review, one merge, done — no hand-editing dozens of repos.
- A repo is "enrolled" when that PR merges; the App can show enrollment status
  across the org at a glance.

**Maintenance**

- Dependabot-style **version-bump PRs** when a new pinned SpecStory release ships.
- A CI check (`specstory verify-enrollment`) that fails a PR if someone deletes or
  breaks the hook wiring — enrollment can't silently rot.

**Optional server-side value (only if cloud sync is on)**

- Receive cloud-synced sessions and provide an org dashboard: who's building what,
  searchable history, links from PRs back to the sessions that produced them.
- Annotate PRs with "this change came from these SpecStory sessions."

**Security posture**

- The App writes only the enrollment files; it never needs code-read access to do
  Tier 1. Cloud/dashboard features are strictly opt-in and scoped separately.

---

## Robustness & security

- **Trust model.** Capture rides the agent's existing folder-trust gate (Claude
  Code: one "trust this folder" acceptance per machine, then hooks run; no
  per-hook nag). That one click is the entire per-developer friction, and it's a
  *feature* — it's the human reviewing what the repo will run.
- **Auditable payload.** The repo commits only declarative config + a checksum
  list — no executable script. A security-minded teammate can read all of it in
  under a minute, and the checksum pins exactly which binary may run.
- **Pinned + checksummed.** Pin a version (never "latest"); verify the release
  checksum (and signature once notarized) before executing.
- **No secrets committed.** Cloud auth is per-user (`specstory login`), never in
  the repo.
- **Offline-safe.** No network? Bootstrap fails open; the session proceeds; next
  online session catches up.
- **Idempotent + fast.** Steady state is a version check and an exec — no
  re-download, negligible overhead.

---

## Observability

To avoid "is this even on?", a `SessionStart` hook can emit a one-line,
friendly confirmation into the session (via the agent's context-injection
output): _"SpecStory capture active (v1.13.0) — history → .specstory/history/."_
Deliberate, quiet, and enough to build trust without nagging. `specstory status`
gives the full picture on demand (enrolled agents, pinned version, last capture).

---

## What we've already validated

Not theory — exercised end-to-end during prototyping (`specstoryai/hook-sample`):

- **Auto-install via SessionStart hook** on a clean Linux container: specstory
  went from absent → `v1.13.0` in `~/.specstory/bin`, with no manual step and no
  sudo.
- **Trust model confirmed:** Claude Code recorded `hasTrustDialogAccepted: true`;
  after that single folder-trust acceptance the committed hook ran with no
  per-hook approval. `/hooks` showed the SessionStart hook registered.
- **Capture confirmed:** after a real exchange (`what is 2+2` → `4`), `specstory
  sync` produced correct, attributed markdown in `.specstory/history/`.
- **Cross-platform:** binary selection matches published assets for all four
  OS×arch combos; ran on macOS arm64, Debian (glibc), Alpine (musl), and Linux
  arm64.
- **Download robustness:** added `curl`-or-`wget` fallback after a clean
  `debian:stable-slim` (no curl) silently no-op'd — caught only because we tested
  on a genuinely bare image.
- **Fail-open:** every "nothing to capture" / "not logged in" path exited cleanly
  without disturbing the session.

The two known gaps: macOS **notarization** for pristine Macs, and wiring the
**`Stop`/`SessionEnd`** hook so capture (not just install) is automatic.

---

## Build order

Each phase is independently shippable and useful on its own.

1. **Publish `@specstory/cli` to npm.** Platform-binary packages
   (`optionalDependencies`, no `postinstall`), versioned to the release, published
   from CI with `--provenance`. This unlocks the primary delivery channel.
2. **Add the `specstory hook` subcommand + `specstory init`.** Move the tiering
   (npx → brew → checksum-verified download → fail open) and capture logic *into
   the binary*, so a repo commits only declarative config. `init` generates that
   config (incl. the `Stop` hook) and the checksums file.
3. **Notarize the macOS binary.** Closes the last clean-machine gap.
4. **Multi-agent stanzas.** Cursor/Codex/Gemini/Droid hook generators + the git-hook
   and `specstory run` fallbacks.
5. **`specstory status` / observability.** The "capture active" signal and a
   status command.
6. **GitHub App — enrollment.** Fleet PRs + version-bump PRs + the CI verify check.
7. **GitHub App — dashboard.** Opt-in server-side history, PR↔session links.

---

## Open questions

- **Per-agent trust UX.** We confirmed Claude Code's gate; each other agent's
  first-run trust/hook-approval behavior needs the same empirical check.
- **`Stop` overhead.** Per-turn `sync` vs `SessionEnd` once — measure before
  defaulting.
- **Committed-executable comfort.** Some orgs are wary of any repo that ships a
  script its agents auto-run. The git-hook fallback and a "review the 30-line
  shim" story are the answer; worth a short SECURITY.md.
- **Monorepo placement.** Where the `.specstory/` lives and how history is scoped
  when many projects share one repo.
