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
            pkgs.gitleaks                     # secret scan (pre-push hook)
            pkgs.ast-grep                     # structural search / lint
          ];
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
