{
  description = "Language-agnostic project template (nix + direnv + apm), reproducible on Claude Code web";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # pkf task runner — the MoonBit build (pkfire >= 0.12). A single
    # self-contained native binary that embeds its own Pkl evaluator, so
    # it needs neither a JVM nor an external `pkl` to evaluate Taskfile.pkl.
    # Pinned to a published tag so `nix develop` gives the same binary on
    # every machine and on Claude Code web (the flake fetches the prebuilt
    # release tarball — no source build). `follows` dedupes pkfire's
    # transitive nixpkgs/flake-utils onto ours to shrink the store closure.
    pkfire = {
      # NOTE: pinned to a COMMIT, not the `v0.12.1` tag. pkfire's binary-fetch
      # flake reads the version+sha256 from `nix/pkf-release.json`, which is
      # synced AFTER the release tag is cut — so the `v0.12.1` tag still serves
      # the previous binary. This commit is the post-sync state that actually
      # fetches the 0.12.1 binary.
      url = "github:mizchi/pkfire/63ccd98c925e4ba5d2c535a14a5009d8894a7e80";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    # pkspec — the MoonBit spec/test runner (pkspec + 5 native adapter
    # shims). Also a self-contained binary-fetch flake; same tag-lag caveat
    # as pkfire, so pinned to the post-sha256-sync commit for 0.4.1.
    pkspec = {
      url = "github:mizchi/pkspec/bc27230f98034aaf6263da65a6f35aa5286a5f53";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pkfire, pkspec }:
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
            pkfire.packages.${system}.default # pkf task runner (MoonBit, embeds its Pkl evaluator)
            pkspec.packages.${system}.default # pkspec spec/test runner + adapter shims (MoonBit)
            apm                               # skill / prompt distribution
            pkgs.pkl                          # Pkl CLI — optional, for authoring/evaluating Taskfile.pkl directly
            pkgs.gitleaks                     # secret scan (pre-push hook)
            pkgs.ast-grep                     # structural search / lint
          ];

          # The MoonBit `pkf` embeds its own Pkl evaluator and manages its own
          # package cache, so there is no JVM truststore to warm. Its first
          # fetch of the pkfire schema from pkg.pkl-lang.org still goes over
          # HTTPS, so export a real CA bundle (Claude Code web / CI lack a
          # default one); after the first run pkf serves the schema from its
          # on-disk cache offline.
          shellHook = ''
            export NIX_SSL_CERT_FILE="''${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
            export SSL_CERT_FILE="''${SSL_CERT_FILE:-$NIX_SSL_CERT_FILE}"
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
