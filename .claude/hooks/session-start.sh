#!/usr/bin/env bash
# SessionStart hook for Claude Code on the web.
#
# Problem it solves: a fresh web container clones the repo with NO nix on PATH.
# It is easy to forget to run `./init.sh` by hand, so the very first tool call
# hits "nix: command not found" and the whole toolchain (pkf / apm / pkl /
# gitleaks / ast-grep) is missing. This hook runs the idempotent bootstrap
# automatically — before the session starts — so the toolchain is ready from
# the first command, no human reminder required.
#
# Verbose bootstrap output goes to stderr on purpose: SessionStart stdout is
# folded into the session context, and we don't want a nix build log in there.
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR"

# Cheap + idempotent: let direnv auto-load the flake in shells that have it.
command -v direnv >/dev/null 2>&1 && direnv allow . 2>/dev/null || true

# The heavy bootstrap only makes sense in the remote web container: it runs as
# root, the repo is cloned fresh, and nix is absent. Local sessions manage
# their own nix/direnv, so we leave /etc/nix and the host profile untouched.
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  # init.sh is idempotent and self-healing: installs single-user nix when
  # absent (else reuses the store), wires it onto PATH for every shell —
  # including this non-interactive tool shell, via /usr/local/bin symlinks —
  # builds the devShell, and runs `apm install`.
  ./init.sh >&2
fi
