# project-template

Language-agnostic project scaffold: **nix + direnv + apm**, reproducible on
Claude Code web. No language runtime is baked in — add one per project.

## Quick start

```bash
nix flake init -t github:mizchi/project-template   # scaffold a fresh repo
./.claude/scripts/ccweb-init.sh                    # bootstrap a clone
```

The bootstrap installs single-user Nix when absent, materializes the devShell
(`pkf`, `apm`, `pkl`, `gitleaks`, `ast-grep`), and runs `apm install`. With
direnv hooked, `cd` into the repo is enough; on Claude Code web a `SessionStart`
hook runs it for you.

See [`CLAUDE.md`](./CLAUDE.md) for the full guide (bootstrap internals, tasks,
toolchain gotchas).

## Per-project next steps

1. Add a language to `flake.nix` (`pkgs.nodejs_24`, `rust-overlay`, …).
2. Run `skill-selector` to pick skills, then append them to `apm.yml`.
3. Add build / test / lint tasks to `Taskfile.pkl` as `deps` of `ci`.

## License

[MIT](./LICENSE)
