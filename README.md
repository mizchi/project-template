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

Installs single-user Nix (sandbox off) when absent, materializes the devShell,
and runs `apm install`. With direnv hooked into your shell, `cd` into the repo
is otherwise enough.

## What's inside

| File | Role |
|------|------|
| `flake.nix` | devShell (`pkf`, `apm`, `gitleaks`, `ast-grep`) + `nix flake init -t` template output |
| `apm.nix` | Vendored derivation for `apm` (PyInstaller native binary, not in nixpkgs) |
| `.envrc` | `use flake` + idempotent `pkf hooks install` |
| `Taskfile.pkl` | pkfire tasks; `pre-push` runs a gitleaks secret scan |
| `apm.yml` | Declares `mizchi/skills/meta/skill-selector` |
| `init.sh` | One-shot bootstrap (Nix → `apm install` → `direnv allow`) |
| `.claude/settings.json` | `SessionStart` hook runs `direnv allow` for the agent session |

## Per-project next steps

1. Add a language to `flake.nix` (`pkgs.nodejs_24`, `rust-overlay`, …).
2. Run `skill-selector` to pick the skills this repo needs, then append them to `apm.yml`.
3. Add build / test / lint tasks to `Taskfile.pkl`.
