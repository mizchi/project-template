#!/usr/bin/env bash
# One-shot bootstrap for a fresh clone, including the Claude Code web sandbox.
# On Claude Code web the SessionStart hook runs this automatically; run it by
# hand for a fresh local clone:
#
#   git clone <repo> && cd <repo> && ./.claude/scripts/ccweb-init.sh
#
# It is idempotent and safe to re-run. Steps:
#   1. Pick the right nix sandbox setting for this kernel and write nix.conf.
#   2. Install single-user Nix when absent (else reuse the existing store).
#   3. Make `nix` reachable from EVERY kind of shell — login, interactive, and
#      non-interactive (CI and the Claude Code tool shell read none of the
#      usual rc files, so the bare profile is not enough on its own).
#   4. Materialize the devShell and run `apm install`.
#   5. `direnv allow` so subsequent shells auto-load the env.
set -euo pipefail

# Run from the repo root regardless of where we were invoked from: the script
# now lives under .claude/scripts/, but `nix develop` and `direnv allow .`
# below need the flake at the repo root as the working directory.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

NIX_VERSION="2.24.9"
CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
PROFILE_BIN="/nix/var/nix/profiles/default/bin"

# --- sandbox detection ------------------------------------------------------
# Nix builds want the kernel's unprivileged-user-namespace sandbox for purity.
# Without it a build runs with HOME=/homeless-shelter on the real filesystem;
# Go-based deps (pkfire) write telemetry there and the *next* build aborts with
# "home directory '/homeless-shelter' exists". Detection can spuriously fail
# very early in container boot, so retry a few times before degrading to
# `sandbox = false`.
sandbox_supported() {
  local i
  for i in 1 2 3; do
    if unshare --user --map-root-user true >/dev/null 2>&1; then
      return 0
    fi
    [ "$i" -lt 3 ] && sleep 1
  done
  return 1
}

write_nix_conf() {
  local sandbox="$1"
  mkdir -p /etc/nix "$HOME/.config/nix"
  cat > /etc/nix/nix.conf <<EOF
build-users-group =
sandbox = ${sandbox}
experimental-features = nix-command flakes
# Point nix at the system CA bundle so substituter and flake-input fetches
# succeed without depending on NIX_SSL_CERT_FILE being exported into the shell
# (the non-interactive tool/CI shell never sources a profile to set it).
ssl-cert-file = ${CA_BUNDLE}
EOF
  cp /etc/nix/nix.conf "$HOME/.config/nix/nix.conf"
}

# --- make nix reachable from every shell ------------------------------------
# The single-user profile's nix.sh only loads in *login* shells (via
# /etc/profile.d). Interactive non-login shells read ~/.bashrc; the Claude Code
# tool shell and CI `bash -c` are non-interactive and read neither. So we cover
# all three:
#   1. /etc/profile.d/nix.sh        -> login shells
#   2. ~/.bashrc (guarded snippet)  -> interactive non-login shells
#   3. symlinks in /usr/local/bin   -> every shell, incl. the non-interactive
#                                       tool/CI shell (only PATH is honoured)
# Called unconditionally — earlier this lived only in the install path, so a
# clone where nix was pre-installed but off PATH never got persisted.
persist_nix() {
  # 1. login shells
  cat > /etc/profile.d/nix.sh <<EOF
export USER="\${USER:-\$(id -un)}"
export HOME="\${HOME:-/root}"
if [ -e "\$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "\$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
export NIX_SSL_CERT_FILE="\${NIX_SSL_CERT_FILE:-${CA_BUNDLE}}"
EOF

  # 2. interactive non-login shells (idempotent, keyed on a marker block)
  local rc="$HOME/.bashrc" marker="# >>> nix (project-template) >>>"
  if [ -f "$rc" ] && ! grep -qF "$marker" "$rc" 2>/dev/null; then
    cat >> "$rc" <<EOF

$marker
if [ -e "\$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "\$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
export NIX_SSL_CERT_FILE="\${NIX_SSL_CERT_FILE:-${CA_BUNDLE}}"
# <<< nix (project-template) <<<
EOF
  fi

  # 3. non-interactive shells (CI, Claude Code tool shell): /usr/local/bin is
  #    on PATH for every shell, so symlink the nix entrypoints there. Skip
  #    silently if the dir is not writable — the other two layers still apply.
  if [ -d "$PROFILE_BIN" ] && [ -w /usr/local/bin ]; then
    local b
    for b in "$PROFILE_BIN"/*; do
      ln -sfn "$b" "/usr/local/bin/$(basename "$b")"
    done
  fi
}

install_nix_single_user() {
  case "$(uname -m)" in
    x86_64)  sys="x86_64-linux" ;;
    aarch64) sys="aarch64-linux" ;;
    arm64)   sys="aarch64-darwin" ;;
    *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac

  local url tmp unpacked nix_pkg
  url="https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${sys}.tar.xz"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo "Downloading ${url}..."
  curl -fsSL "$url" -o "$tmp/nix.tar.xz"
  mkdir -p "$tmp/unpack"
  tar -xJf "$tmp/nix.tar.xz" -C "$tmp/unpack"
  unpacked="$tmp/unpack/nix-${NIX_VERSION}-${sys}"

  mkdir -p /nix/store /nix/var/nix
  cp -RPp "$unpacked/store/"* /nix/store/
  nix_pkg="/nix/store/$(basename "$(ls -d "$unpacked/store"/*-nix-"${NIX_VERSION}")")"
  "$nix_pkg/bin/nix-store" --load-db < "$unpacked/.reginfo"

  mkdir -p /nix/var/nix/profiles/per-user/root
  ln -sfn "$nix_pkg" /nix/var/nix/profiles/default
  ln -sfn /nix/var/nix/profiles/default "$HOME/.nix-profile"

  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
}

export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"
export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-$CA_BUNDLE}"

if sandbox_supported; then
  SANDBOX=true
  echo "==> user namespaces available — nix sandbox = true"
else
  SANDBOX=false
  echo "==> user namespaces unavailable — nix sandbox = false (degraded purity)"
fi
# Written every run so an existing clone with a stale (e.g. sandbox=false)
# nix.conf is corrected, not just fresh installs.
write_nix_conf "$SANDBOX"

# Ensure nix is installed and on PATH for the rest of THIS script.
if ! command -v nix >/dev/null 2>&1; then
  if [ -x "$HOME/.nix-profile/bin/nix" ]; then
    echo "==> nix present but not on PATH; sourcing profile"
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  else
    echo "==> nix not found; installing single-user Nix"
    install_nix_single_user
  fi
else
  echo "==> nix present: $(nix --version)"
fi
# Last-resort PATH fix for this process if no profile script was sourced.
command -v nix >/dev/null 2>&1 || export PATH="$PROFILE_BIN:$PATH"

# Persist nix across login, interactive, and non-interactive shells. Runs on
# every invocation, independent of whether we installed or reused nix above.
persist_nix
echo "==> nix wired into login + interactive + non-interactive shells"

# A prior sandboxless build may have left /homeless-shelter, which makes every
# later build abort. Harmless to remove; the sandbox keeps it from recurring.
rm -rf /homeless-shelter 2>/dev/null || true

echo "==> Building devShell and installing APM dependencies"
# The devShell's shellHook warms the pkl package cache (system CA) before this
# runs, so `apm install` and later `pkf` invocations work offline.
nix develop --command sh -c 'apm install'

if command -v direnv >/dev/null 2>&1; then
  echo "==> direnv allow"
  direnv allow . || true
fi

echo "==> Done. Enter the dev shell with: nix develop   (or just cd in, if direnv is hooked)"
