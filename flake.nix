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

        # apm ships as a PyInstaller native binary, not an nixpkgs package, so
        # we build the derivation inline here rather than vendoring an apm.nix.
        # Bump `apmVersion` + the matching sha256 to upgrade.
        apmVersion = "0.8.11";
        apmSources = {
          "x86_64-linux" = { suffix = "linux-x86_64"; sha256 = "b3f4ee5a933c89b97ce30fb7318d227e2c92060b64abd699a35a7e9c1998fe45"; };
          "aarch64-linux" = { suffix = "linux-arm64"; sha256 = "c49c5b3cdbbf7abe2a4ac630c2cd5706cd45e1576065449d847e4129efaa17c0"; };
          "x86_64-darwin" = { suffix = "darwin-x86_64"; sha256 = "1c48afad648781d02dbea5050b78a037a4f243b711b92d08d3f05257edb0aec9"; };
          "aarch64-darwin" = { suffix = "darwin-arm64"; sha256 = "d4d78cfa110d369601d53b1238e0b17a2772ae1ef0281e67eb4917f3525bc6b4"; };
        };
        apmSrc = apmSources.${system} or (throw "apm: unsupported system ${system}");
        apm = pkgs.stdenv.mkDerivation {
          pname = "apm";
          version = apmVersion;
          src = pkgs.fetchurl {
            url = "https://github.com/microsoft/apm/releases/download/v${apmVersion}/apm-${apmSrc.suffix}.tar.gz";
            sha256 = apmSrc.sha256;
          };
          sourceRoot = "apm-${apmSrc.suffix}";
          nativeBuildInputs = [ pkgs.makeWrapper ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
            # PyInstaller's bundled _ssl / _hashlib modules link libssl.so.3 /
            # libcrypto.so.3. Without openssl, autoPatchelf fails on Linux
            # (macOS skips autoPatchelf so the gap is invisible there).
            pkgs.openssl
          ];
          dontConfigure = true;
          dontBuild = true;
          # PyInstaller appends its PKG archive after the Mach-O / ELF binary.
          # strip / patchelf would truncate or corrupt that archive.
          dontStrip = true;
          dontPatchELF = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/apm $out/bin
            cp -r . $out/libexec/apm/
            chmod +x $out/libexec/apm/apm
            makeWrapper $out/libexec/apm/apm $out/bin/apm
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "Agent Package Manager (microsoft/apm)";
            homepage = "https://github.com/microsoft/apm";
            license = licenses.mit;
            mainProgram = "apm";
            platforms = builtins.attrNames apmSources;
            sourceProvenance = [ sourceTypes.binaryNativeCode ];
          };
        };
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
