# burree

Self-hosted residential-proxy agent. Pairs with [cloud.burree.org](https://cloud.burree.org), holds a persistent WSS connection to your assigned relay node, and forwards local tunnel traffic over it.

## Install

```sh
curl -fsSL --proto '=https' --tlsv1.2 https://release.burree.org/install.sh | bash
```

The installer downloads the platform-matched binary from [GitHub Releases](https://github.com/clawee-vanguard/burree/releases), verifies its SHA-256, and installs to `$HOME/.local/bin/burree`.

Once installed:

```sh
burree login              # browser-callback auth against cloud.burree.org
burree service install    # launchd / systemd persistence (optional)
burree dash               # loopback UI on 127.0.0.1:16508
```

*(Screenshot of the local dash — coming soon.)*

## Supported platforms

| OS | arm64 | amd64 |
|---|---|---|
| macOS (darwin) | ✓ | ✓ |
| Linux | ✓ | ✓ |

Windows is not supported in this preview.

## For LLM coding agents

If you're driving an LLM (Claude Code, Cursor, Aider, …) to install burree on a user's machine, point it at:

- `install.md` — download + install + verify the binary
- `setup.md` — sign in, register with cloud.burree.org, and choose service vs. foreground

Both are designed for a fresh-context agent to follow end-to-end.

## Mirrors

This repo is the source of truth. `release.burree.org` mirrors a small set of files for short curl-pipe URLs:

| Canonical (this repo) | Mirror URL |
|---|---|
| `install.sh` | `https://release.burree.org/install.sh` |
| `install.md` | `https://release.burree.org/skills/burree-install/SKILL.md` |
| `setup.md`   | `https://release.burree.org/skills/burree-setup/SKILL.md` |

The mirror is refreshed on every release. **Built agent binaries** live only as [GitHub Release](https://github.com/clawee-vanguard/burree/releases) assets on this repo — `release.burree.org` does not host them.

## Status

Preview release. Expect rough edges; report issues on this repo.

## Repo internals

Public preview/release docs + install script for the Burree platform. Source of truth for `release.burree.org` (which mirrors `install.sh`, `install.md`, `setup.md`, and skill SKILL.md files). Built binaries published as GitHub Release assets on this repo.

- `clawee-vanguard/burree` (PUBLIC). Trunk: `main`. Daily work on `dev` (worktree at `../.worktrees/dev`).
- gh.account: `clawee-vanguard`. Call gh via `~/.claude/bin/ghp`.

### Roots

| Name    | Path                                                          | Where        |
|---|---|---|
| `LOCAL` | `.` (this directory)                                          | dev machine  |
| `PROD`  | mirrored at `release.burree.org` (CDN-fronted)                | prod         |

See `~/.claude/guidelines/PROJECT-SETUP.md` §10.

### Stack

Markdown + shell. No compiled code in this repo.

### Layout

```
install.sh           ← end-user install entry point (SoT)
install.md           ← human-readable install guide
setup.md             ← post-install setup
skills/              ← burree-* skill packages (SKILL.md each)
```

### Deferred

- Per-platform install binaries for non-mac targets.
