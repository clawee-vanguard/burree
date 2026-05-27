---
name: burree-setup
description: Sign in the burree agent against cloud.burree.org, pull the node assignment, run the doctor, and choose between a managed launchd/systemd service or a foreground `burree run`. Use after the burree binary is installed (see burree-install skill). Trigger when the operator says "set up burree", "log in to burree", "connect burree to my account", or pastes release.burree.org/skills/burree-setup/SKILL.md.
---

# burree-setup

You are an LLM coding agent setting up an already-installed burree
agent against `cloud.burree.org`. The binary must already be on PATH
— if it isn't, stop and route the operator to the `burree-install`
skill first.

This skill **requires interactive operator steps** (browser sign-in,
explicit choice of service vs. foreground). Pause and ask; resume on
confirmation.

---

## 0. Pre-flight

Confirm the binary is present and the workspace is clean:

```bash
burree version
ls -ld "$HOME/.burree" 2>/dev/null || echo "no .burree dir"
```

`burree version` must print a real version line. If it can't, route
the operator to `burree-install` and stop.

The `$HOME/.burree` directory may or may not exist yet — both are
fine. If it exists with files from a previous pairing, ask the
operator whether they want to keep that identity (just refresh the
token) or wipe and start over.

---

## 1. Sign in to the cloud

`burree login` opens the system browser to `cloud.burree.org/login`,
captures the returned token on a one-shot localhost callback, and
writes it to `$HOME/.burree/auth.token`. Then it auto-runs the
register flow, which pulls the assigned node + pinned cloud pubkey.

This step **requires the browser** — do not try to automate it. Tell
the operator:

> I'm about to run `burree login`. A browser window will open to
> `https://cloud.burree.org/login`. Sign in (or sign up if invited),
> approve the CLI grant, and the terminal will continue automatically.
> Default timeout is 5 minutes.

Then run:

```bash
burree login
```

Watch the exit code. On success, the CLI prints `Logged in. Agent
agt_… registered (node: <hostname>)`. On failure (token timeout, user
closed the browser, cloud unreachable), surface the error to the
operator and stop — they need to retry.

For a non-default cloud (`burree login --cloud https://my-cloud.example.com`),
ask the operator before assuming the default. Don't guess.

---

## 2. Verify identity + connectivity

```bash
burree info
burree doctor
```

`burree info` should print either a cached entitlement summary or
"no cached entitlement — not yet paired or never connected". Both are
fine here — entitlement caches on the first WSS-control connect, which
happens once the daemon runs.

`burree doctor` is the source of truth. Walk every `✗` (fail) and `!`
(warn) line and act on the inline action. Common cases:

| Failing check | What it means | Action |
|---|---|---|
| `cloud /healthz` ✗ | Cloud unreachable or `cloud.url` wrong | Recheck `curl https://cloud.burree.org/healthz`; if good, re-run `burree login --cloud https://cloud.burree.org`. |
| `node /healthz` ✗ | Assigned node down or decommissioned | Run `curl -fsS -X POST http://127.0.0.1:16508/api/cloud/resync` after step 4 lands a daemon, or run `burree dash` and click "Refresh from cloud" on the Settings tab. |
| `daemon` ! | No `burree run` process detected | Step 3 below. |
| `keys/hmac.key` ! | Missing — viewer tokens won't mint | Re-run `burree login` (registration regenerates it if absent). |

After each fix, re-run `burree doctor`. Don't move on until the
checklist is green except possibly the `daemon` warn (resolved in
step 3) and `node /healthz` (which may stay red until the daemon
runs once + the cloud rebinds it — re-check after step 3).

---

## 3. Choose: managed service vs. foreground

Ask the operator how they want the daemon to run, and proceed
accordingly. Don't pick for them.

**Option A — managed service (recommended for laptops/servers that
should always have burree available):**

On macOS:
```bash
burree service install
burree service status        # confirm "loaded" or "started"
```

On Linux (systemd available — `systemctl --user status` works):
```bash
burree service install
systemctl --user status dev.burree.agent.service
```

`burree service install` writes the right unit file for the host's
init system (launchd plist on macOS, systemd user service on Linux)
and bootstraps it immediately. The agent survives logout/reboot.

**Option B — foreground `burree run` (recommended for terminals, dev
work, anything where you want logs in front of you):**

Tell the operator:
> Open a separate terminal and run `burree run`. Leave it running.
> Switch back to this session when you see the line
> `burree: dialing wss://<node>/ws/agent/control`.

Do **not** try to spawn `burree run` in the background from this
shell. The daemon's stdout/stderr are the operator's primary debugging
surface — backgrounding it from a remote agent hides them.

Either way, wait for the operator to confirm the daemon is up before
moving to step 4.

---

## 4. Final verification

With the daemon running, the doctor should be all-green and the
local dashboard should be reachable:

```bash
burree doctor                # every line should be ✓
curl -sf http://127.0.0.1:16508/healthz
```

The `127.0.0.1:16508/healthz` probe confirms the loopback dash is up
(both `burree run` and `burree dash` bind it). If the doctor still
shows `node /healthz` ✗, give the daemon ~30 seconds to first-connect,
then re-run.

---

## 5. Hand back

When everything's green, tell the operator:

> burree is signed in and running. Useful commands:
> - `burree info` — cached entitlement
> - `burree doctor` — re-verify any time something looks off
> - `burree dash` — loopback UI at http://127.0.0.1:16508
> - Service logs (macOS):  `tail -f $HOME/.burree/logs/launchd.out.log`
> - Service logs (linux):  `journalctl --user -u dev.burree.agent.service -f`

Operations like adding ports, attaching custom domains, or sharing an
agent with a team will be covered by additional skills once they're
ready. For now, that work happens via:
- `cloud.burree.org/agents` (the web SPA)
- the local dash at `127.0.0.1:16508`
- the `burree` CLI subcommands

---

## Troubleshooting hooks

- **`burree login` says "browser callback timeout".** The operator
  probably closed the tab before approving. Re-run; default timeout
  is 5 minutes, can override with `--timeout 10m`.

- **"Re-pair?" loop on the dash settings tab.** The agent rotated
  identity (HMAC + ed25519 key) at some point. Easiest reset:
  ```bash
  rm -rf $HOME/.burree
  burree login
  ```
  This wipes both auth + keys; the cloud-side row is re-created on
  the next register. Mention to the operator that any existing
  viewer tokens / shared ports break.

- **`burree service install` fails on Linux with "systemd not
  available".** The host is using a non-systemd init (OpenRC,
  runit). Fall back to Option B (foreground) or have the operator
  wire a custom supervisor.

- **Operator says they're behind a corporate proxy.** burree obeys
  `HTTPS_PROXY` for outbound cloud calls. Make sure the proxy is in
  the operator's env before running `burree login`. The WSS dialer
  also honors `HTTPS_PROXY` (HTTP CONNECT tunneling).

- **Re-running this skill on an already-configured machine.** Step 1
  (`burree login`) is idempotent if the operator wants to refresh
  the token; it reuses the existing keypair. If the operator wants
  to switch accounts entirely, they should `burree logout` first
  (preserves keys for re-login on the same identity).
