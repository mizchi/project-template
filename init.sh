#!/usr/bin/env bash
# One-shot bootstrap for a fresh clone, including the Claude Code web sandbox.
#
#   git clone <repo> && cd <repo> && ./init.sh
#
# Steps:
#   1. Install single-user Nix (sandbox off) when `nix` is absent.
#   2. Materialize the devShell and run `apm install`.
#   3. `direnv allow` so subsequent shells auto-load the env.
set -euo pipefail

NIX_VERSION="2.24.9"

install_nix_single_user() {
  export USER="${USER:-$(id -un)}"
  export HOME="${HOME:-/root}"

  # nix.conf first: single-user, sandbox disabled, flakes enabled.
  mkdir -p /etc/nix "$HOME/.config/nix"
  cat > /etc/nix/nix.conf <<'EOF'
build-users-group =
sandbox = false
experimental-features = nix-command flakes
EOF
  cp /etc/nix/nix.conf "$HOME/.config/nix/nix.conf"

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

if ! command -v nix >/dev/null 2>&1; then
  echo "==> nix not found; installing single-user Nix"
  install_nix_single_user
else
  echo "==> nix present: $(nix --version)"
fi

echo "==> Building devShell and installing APM dependencies"
nix develop --command sh -c 'apm install'

if command -v direnv >/dev/null 2>&1; then
  echo "==> direnv allow"
  direnv allow . || true
fi

echo "==> Done. Enter the dev shell with: nix develop   (or just cd in, if direnv is hooked)"
