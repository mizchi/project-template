#!/usr/bin/env bash
# One-shot bootstrap for a fresh clone, including the Claude Code web sandbox.
#
#   git clone <repo> && cd <repo> && ./init.sh
#
# Steps:
#   1. Install single-user Nix when `nix` is absent.
#   2. Materialize the devShell and run `apm install`.
#   3. `direnv allow` so subsequent shells auto-load the env.
set -euo pipefail

NIX_VERSION="2.24.9"

# Nix builds want the kernel's unprivileged-user-namespace sandbox for purity.
# Probe for it: when available we keep `sandbox = true` (the right default),
# otherwise we fall back to `sandbox = false`. Falling back matters because a
# sandboxless build runs with HOME=/homeless-shelter on the real filesystem —
# Go-based deps (pkfire) then write telemetry there, and the *next* build aborts
# with "home directory '/homeless-shelter' exists". The sandbox isolates that.
sandbox_supported() {
  unshare --user --map-root-user true >/dev/null 2>&1
}

write_nix_conf() {
  local sandbox="$1"
  mkdir -p /etc/nix "$HOME/.config/nix"
  cat > /etc/nix/nix.conf <<EOF
build-users-group =
sandbox = ${sandbox}
experimental-features = nix-command flakes
EOF
  cp /etc/nix/nix.conf "$HOME/.config/nix/nix.conf"
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
  export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"

  # Persist for subsequent shells.
  cat > /etc/profile.d/nix.sh <<'EOF'
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
EOF
}

export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"

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

if ! command -v nix >/dev/null 2>&1; then
  if [ -x "$HOME/.nix-profile/bin/nix" ]; then
    echo "==> nix present but not on PATH; sourcing profile"
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
  else
    echo "==> nix not found; installing single-user Nix"
    install_nix_single_user
  fi
else
  echo "==> nix present: $(nix --version)"
fi

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
