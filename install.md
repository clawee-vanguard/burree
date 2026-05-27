---
name: burree-install
description: Install the burree agent binary on the local machine (macOS + Linux). Use when the user asks to "install burree", "get the burree CLI", or pastes the URL release.burree.org/skills/burree-install/SKILL.md. Stop after the binary is on PATH and reports its version — sign-in + service setup live in the burree-setup skill, which the operator triggers next.
---

# burree-install

You are an LLM coding agent (Claude Code, Cursor, Aider, …) tasked
with putting the **burree agent binary** on this machine. The job is
narrow: download + install + verify. Do **not** start sign-in flows,
do **not** install services. Those belong to the `burree-setup`
skill the operator will invoke next.

The operator may need to perform out-of-terminal actions (granting
shell permissions, opening a new shell to pick up `PATH`). Pause and
ask them; resume when they confirm.

---

## 0. Pre-flight

Run these checks; stop and surface the failure if any one fails.

```bash
uname -s            # expected: Darwin (macOS) or Linux
uname -m            # expected: arm64 / aarch64 / x86_64 / amd64
command -v curl
command -v bash
command -v unzip
curl -fsSL https://release.burree.org/install.sh | head -3
```

Acceptable platforms today: `darwin × {arm64, amd64}`, `linux × {arm64, amd64}`.
For anything else (Windows, BSD, esoteric arch), stop and tell the operator the
official build doesn't ship for their platform yet.

If `unzip` is missing, install it (`brew install unzip` on macOS;
`sudo apt install unzip` on Debian/Ubuntu; `sudo dnf install unzip` on
RHEL/Fedora). Retry the pre-flight afterwards.

---

## 1. Install the binary

```bash
curl -fsSL --proto '=https' --tlsv1.2 https://release.burree.org/install.sh | bash
```

The installer downloads the platform-matched release zip from
`release.burree.org/agents/`, extracts the `burree` binary into
`$HOME/.local/bin/`, and creates the runtime keystore directory at
`$HOME/.burree/` (0700). It prints a hint if `$HOME/.local/bin` isn't on
`PATH`.

If the installer fails with a download error, recheck the pre-flight
network access. Do **not** retry with `BURREE_FROM_SOURCE=1` — that
flag was removed.

---

## 2. Verify

Pick the right invocation depending on whether the bin dir is on PATH:

```bash
# Preferred:
burree version

# Fallback if PATH isn't refreshed yet:
"$HOME/.local/bin/burree" version
```

Expected output: a single line beginning with `burree` followed by a
version string and a build-info trailer. Anything else (missing
binary, "command not found", wrong arch error) means the install
didn't land — surface the raw output to the operator and stop.

If `PATH` is missing the bin dir, tell the operator to add this line
to their shell rc (`~/.zshrc`, `~/.bashrc`, etc.) and open a new
shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## 3. Hand back

Once `burree version` succeeds, **stop**. Tell the operator:

> burree is installed at `$HOME/.local/bin/burree`. To sign in to the
> cloud and bring up the daemon, run the `burree-setup` skill next
> (or paste `https://release.burree.org/skills/burree-setup/SKILL.md`
> into your coding agent).

Do not start `burree login`, `burree run`, or `burree service install`
from this skill. The setup flow needs operator decisions
(browser-based login, service-vs-foreground choice) that this skill is
not equipped to walk through.

---

## Troubleshooting

- **"unsupported arch" on a known-good Mac (Apple Silicon).** The
  installer reads `uname -m`. Rosetta-emulated shells report
  `x86_64`; close any Rosetta'd terminal and run from a native one.
- **`Failed to connect to release.burree.org`.** The artifact host
  is on Cloudflare; corporate proxies sometimes block. Check
  `curl -v https://release.burree.org/install.sh` and surface the
  TLS/HTTP error to the operator.
- **Wanted to pin a specific version.** Re-run with `BURREE_VERSION`:
  ```bash
  BURREE_VERSION=v0.2.0.2026.05.20.<hash> bash <(curl -fsSL https://release.burree.org/install.sh)
  ```
- **Operator wants to uninstall.** Use the `BURREE_UNINSTALL` path:
  ```bash
  BURREE_UNINSTALL=1 bash <(curl -fsSL https://release.burree.org/install.sh)
  ```
  Keys + `auth.token` under `$HOME/.burree/` are preserved by design —
  mention this so the operator can `rm -rf $HOME/.burree` if they want
  a true clean slate.
