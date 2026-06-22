# project-template

Language-agnostic project scaffold: **nix + direnv + apm**, reproducible on Claude Code web.
No language runtime is baked in — add one per project.

## Use it

Fork / clone, or scaffold a fresh repo from the flake template:

```bash
nix flake init -t github:mizchi/project-template
```

## Bootstrap (fresh clone / Claude Code web)

```bash
./init.sh
```

Installs single-user Nix when absent (sandbox on where the kernel allows
unprivileged user namespaces, off otherwise), materializes the devShell, and
runs `apm install`. With direnv hooked into your shell, `cd` into the repo is
otherwise enough.

## What's inside

| File | Role |
|------|------|
| `flake.nix` | devShell (`pkf`, `apm`, `pkl`, `gitleaks`, `ast-grep`) + a `shellHook` that warms the pkl package cache; also the `nix flake init -t` template output |
| `apm.nix` | Vendored derivation for `apm` (PyInstaller native binary, not in nixpkgs) |
| `.envrc` | `use flake` + idempotent `pkf hooks install` |
| `Taskfile.pkl` | pkfire tasks; `pre-push` runs a gitleaks secret scan |
| `apm.yml` | Declares `mizchi/skills/meta/skill-selector` |
| `init.sh` | One-shot bootstrap (Nix → `apm install` → `direnv allow`) |
| `.claude/settings.json` | `SessionStart` hook runs `direnv allow` for the agent session |
| `.github/workflows/test.yml` | CI: builds the devShell, runs `pkf run ci` (toolchain guard + gitleaks) and verifies APM resolution |

## CI

`.github/workflows/test.yml` builds the devShell via the Determinate Nix
installer (GHA-cached) and runs the language-agnostic gate:

```bash
nix develop --command pkf run ci   # verify-tools + full-history gitleaks scan
```

Add per-project build / test tasks as `deps` of the `ci` task in `Taskfile.pkl`
once a language is chosen — the workflow then needs no edits.

## Per-project next steps

1. Add a language to `flake.nix` (`pkgs.nodejs_24`, `rust-overlay`, …).
2. Run `skill-selector` to pick the skills this repo needs, then append them to `apm.yml`.
3. Add build / test / lint tasks to `Taskfile.pkl`.
