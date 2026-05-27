#!/usr/bin/env bash
# Burree agent installer — single-binary, macOS + Linux.
#
#   curl -fsSL --proto '=https' --tlsv1.2 https://release.burree.org/install.sh | bash
#
# (https://cloud.burree.org/install.sh is mirrored from release.burree.org;
#  both URLs serve the same script.)
#
# What this script does:
#   1. detect OS/arch
#   2. resolve the latest release tag on github.com/${BURREE_RELEASE_REPO}
#      (default clawee-vanguard/burree) — or use ${BURREE_VERSION} if pinned
#   3. download the matching burree-${OS}-${ARCH}.zip + SHA256SUMS.txt
#   4. verify the checksum before extracting
#   5. extract `burree` into $PREFIX/bin (default $HOME/.local/bin)
#   6. ensure $HOME/.burree exists for runtime keystore + auth.token
#
# Env vars:
#   BURREE_VERSION         release tag (default: latest — resolved via GH API)
#   PREFIX                 install root (default $HOME/.local; binary at PREFIX/bin)
#   BURREE_AGENT_DIR       runtime dir (default $HOME/.burree)
#   BURREE_RELEASE_REPO    GitHub repo serving releases
#                          (default clawee-vanguard/burree)
#   BURREE_UNINSTALL=1     remove the binary; keys + auth.token preserved

set -euo pipefail

# ---- styling ------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\033[1m'; ACCENT=$'\033[38;2;255;77;77m'
    OK=$'\033[38;2;0;229;204m'; MUTED=$'\033[38;2;136;146;176m'
    WARN=$'\033[38;2;255;176;32m'; ERR=$'\033[38;2;230;57;70m'; NC=$'\033[0m'
else
    BOLD=""; ACCENT=""; OK=""; MUTED=""; WARN=""; ERR=""; NC=""
fi
info() { printf "  %s→%s %s\n" "${ACCENT}" "${NC}" "$*"; }
ok()   { printf "  %s✓%s %s\n" "${OK}"     "${NC}" "$*"; }
warn() { printf "  %s!%s %s\n" "${WARN}"   "${NC}" "$*" >&2; }
fail() { printf "\n  %s✗%s %s\n\n" "${ERR}" "${NC}" "$*" >&2; exit 1; }

# ---- defaults -----------------------------------------------------------
BURREE_VERSION="${BURREE_VERSION:-latest}"
PREFIX="${PREFIX:-$HOME/.local}"
BURREE_AGENT_DIR="${BURREE_AGENT_DIR:-$HOME/.burree}"
BURREE_RELEASE_REPO="${BURREE_RELEASE_REPO:-clawee-vanguard/burree}"
BIN_DIR="${PREFIX}/bin"
BIN_PATH="${BIN_DIR}/burree"

# Back-compat: BURREE_RELEASE_BASE was the old release.burree.org/agents/
# host. Warn loudly if anyone still sets it — the new install.sh ignores it.
if [[ -n "${BURREE_RELEASE_BASE:-}" ]]; then
    warn "BURREE_RELEASE_BASE is deprecated and ignored. Set BURREE_RELEASE_REPO=<org/repo> instead (default: clawee-vanguard/burree)."
fi

# ---- platform detection -------------------------------------------------
case "$(uname -s)" in
    Darwin) OS=darwin ;;
    Linux)  OS=linux ;;
    *)      fail "unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
    arm64|aarch64) ARCH=arm64 ;;
    x86_64|amd64)  ARCH=amd64 ;;
    *)             fail "unsupported arch: $(uname -m)" ;;
esac

printf "\n%s%s  burree installer%s  %s(${OS}/${ARCH})%s\n\n" \
    "${BOLD}" "${ACCENT}" "${NC}" "${MUTED}" "${NC}"

# ---- uninstall ----------------------------------------------------------
if [[ "${BURREE_UNINSTALL:-0}" == "1" ]]; then
    info "uninstalling burree"
    [[ -f "${BIN_PATH}" ]] && rm -f "${BIN_PATH}" && ok "removed ${BIN_PATH}" \
        || warn "no binary at ${BIN_PATH}"
    ok "agent dir preserved: ${BURREE_AGENT_DIR} ${MUTED}(keys + auth.token kept)${NC}"
    info "to wipe agent state too: rm -rf ${BURREE_AGENT_DIR}"
    exit 0
fi

mkdir -p "${BIN_DIR}" "${BURREE_AGENT_DIR}"
chmod 0700 "${BURREE_AGENT_DIR}"

# ---- resolve release tag + download from GitHub Releases -----------------
# tools/release.sh on the private agent repo publishes assets to
#     github.com/${BURREE_RELEASE_REPO}/releases/<tag>/burree-${OS}-${ARCH}.zip
# alongside SHA256SUMS.txt. We resolve `latest` via the GitHub API, then
# fetch + checksum-verify before extracting.
PLATFORM="${OS}-${ARCH}"
GH_API="https://api.github.com/repos/${BURREE_RELEASE_REPO}/releases"

if [[ "${BURREE_VERSION}" == "latest" ]]; then
    info "resolving latest tag from ${GH_API}/latest"
    TAG="$(curl -fsSL --connect-timeout 15 --max-time 30 "${GH_API}/latest" \
        | grep -E '"tag_name"\s*:' | head -1 \
        | sed -E 's/.*"tag_name"[^"]*"([^"]+)".*/\1/')" || true
    [[ -n "${TAG}" ]] \
        || fail "could not resolve latest tag — check network or pin BURREE_VERSION=<tag>"
else
    TAG="${BURREE_VERSION}"
fi
RELEASE_BASE="https://github.com/${BURREE_RELEASE_REPO}/releases/download/${TAG}"
URL="${RELEASE_BASE}/burree-${PLATFORM}.zip"
SUMS_URL="${RELEASE_BASE}/SHA256SUMS.txt"

command -v unzip >/dev/null \
    || fail "unzip not found — install it (\`brew install unzip\` on macOS, \`apt install unzip\` on Debian/Ubuntu) and retry"

# SHA verify tool — prefer shasum (macOS default) then sha256sum (coreutils,
# default on Ubuntu/Debian where shasum's `perl` package is not pre-installed).
if command -v shasum >/dev/null; then
    SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null; then
    SHA_CMD="sha256sum"
else
    fail "neither \`shasum\` nor \`sha256sum\` found — install one (built-in on macOS, \`sudo apt install coreutils\` on Debian/Ubuntu) and retry"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/burree-install-XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT
ZIP_PATH="${TMP_DIR}/burree-${PLATFORM}.zip"
SUMS_PATH="${TMP_DIR}/SHA256SUMS.txt"

info "downloading ${URL}"
if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 -o "${ZIP_PATH}" "${URL}"; then
    fail "download failed — confirm the release exists at ${URL} (or check your network)"
fi

info "downloading SHA256SUMS.txt"
if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 30 -o "${SUMS_PATH}" "${SUMS_URL}"; then
    fail "SHA256SUMS.txt missing on release ${TAG} — refusing to install unverified bytes"
fi

info "verifying checksum"
grep -qF "burree-${PLATFORM}.zip" "${SUMS_PATH}" \
    || fail "SHA256SUMS.txt has no entry for burree-${PLATFORM}.zip — release may be incomplete or tampered; refusing to install"
( cd "${TMP_DIR}" && ${SHA_CMD} -c --ignore-missing SHA256SUMS.txt >/dev/null ) \
    || fail "checksum mismatch — refusing to install (zip tampered or download corrupted)"

info "extracting"
if ! unzip -qo "${ZIP_PATH}" -d "${TMP_DIR}"; then
    fail "zip extraction failed — corrupt download?"
fi
[[ -f "${TMP_DIR}/burree" ]] \
    || fail "no \`burree\` binary inside the zip — release packaging changed; re-run release.sh"

mv -f "${TMP_DIR}/burree" "${BIN_PATH}"
chmod +x "${BIN_PATH}"
ok "installed: ${BIN_PATH}"

# ---- PATH hint ----------------------------------------------------------
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ok "${BIN_DIR} is on PATH" ;;
    *)                warn "${BIN_DIR} not on PATH — add: ${BOLD}export PATH=\"${BIN_DIR}:\$PATH\"${NC}" ;;
esac

cat <<EOF

  ${BOLD}Next:${NC}
    1. ${ACCENT}burree login${NC}             ${MUTED}# browser-callback auth; saves auth.token${NC}
    2. ${ACCENT}burree service install${NC}   ${MUTED}# launchd persistence (optional)${NC}
    3. ${ACCENT}burree dash${NC}              ${MUTED}# loopback UI on 127.0.0.1:16508${NC}

  ${MUTED}Uninstall:${NC}
    BURREE_UNINSTALL=1 bash <(curl -fsSL https://release.burree.org/install.sh)

EOF
