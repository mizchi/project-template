{
  description = "Language-agnostic project template (nix + direnv + apm), reproducible on Claude Code web";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # pkf task runner. Pinned to the latest published tag so `nix develop`
    # gives the same binary on every machine and on Claude Code web.
    pkfire.url = "github:mizchi/pkfire/v0.9.0";
  };

  outputs = { self, nixpkgs, flake-utils, pkfire }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Vendored derivation: apm ships as a PyInstaller native binary,
        # not an nixpkgs package. See apm.nix for the why.
        apm = import ./apm.nix { inherit pkgs; };
      in
      {
        devShells.default = pkgs.mkShell {
          # Intentionally NO language runtime here — this template is
          # language-agnostic. Add nodejs / rust / etc. per project.
          packages = [
            pkfire.packages.${system}.default # pkf task runner
            apm                               # skill / prompt distribution
            pkgs.pkl                          # Taskfile.pkl evaluator (pkf's engine)
            pkgs.gitleaks                     # secret scan (pre-push hook)
            pkgs.ast-grep                     # structural search / lint
          ];

          # pkf evaluates Taskfile.pkl, whose `amends` pulls the pkfire schema
          # from pkg.pkl-lang.org. pkl runs on the bundled JVM, whose truststore
          # does NOT chain to that host's CA — so the very first fetch fails with
          # an SSL handshake error on Claude Code web and in CI alike. Warm the
          # pkl package cache once using the system CA bundle; every later `pkf`
          # invocation (here, via direnv, or `nix develop --command` in CI) then
          # hits the on-disk cache and needs neither network nor the JVM trust.
          shellHook = ''
            export NIX_SSL_CERT_FILE="''${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
            if [ -f Taskfile.pkl ] && \
               [ ! -d "''${HOME:-/root}/.pkl/cache/package-2/pkg.pkl-lang.org" ]; then
              echo "warming pkl package cache (system CA)…" >&2
              pkl eval --ca-certificates="$NIX_SSL_CERT_FILE" Taskfile.pkl >/dev/null 2>&1 \
                || echo "pkl cache warm failed — pkf may need network + a CA bundle" >&2
            fi
          '';
        };
      })
    // {
      # `nix flake init -t github:mizchi/project-template` scaffolds a new
      # repo from this directory. The repo itself is also a usable scaffold
      # (just fork / clone it) — one source, both distribution forms.
      templates.default = {
        path = ./.;
        description = "Language-agnostic project template (nix + direnv + apm)";
      };
    };
}
