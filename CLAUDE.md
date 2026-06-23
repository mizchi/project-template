# CLAUDE.md

Guidance for AI agents (and humans) working in this repo. This is a
**language-agnostic project template**: nix + direnv + apm, reproducible on
Claude Code web. No language runtime is baked in — add one per project.

## Bootstrap

On a fresh clone or a new Claude Code web session:

```bash
./.claude/scripts/ccweb-init.sh
```

It is idempotent. It:

1. Probes for unprivileged user namespaces (with a short retry, since the
   probe can spuriously fail very early in container boot) and writes
   `/etc/nix/nix.conf` with `sandbox = true` when available (else `false`). It
   also pins `ssl-cert-file` to the system CA so fetches don't depend on
   `NIX_SSL_CERT_FILE`. The file is rewritten every run, so a stale clone
   self-heals.
2. Installs single-user Nix when absent (or just sources an already-installed
   profile).
3. Makes `nix` reachable from every shell — `/etc/profile.d/nix.sh` (login),
   a guarded `~/.bashrc` block (interactive), and symlinks in `/usr/local/bin`
   (non-interactive CI / Claude Code tool shells, which source no rc file).
4. Builds the devShell and runs `apm install`.

With direnv hooked into your shell, `cd` into the repo is otherwise enough
(`.envrc` runs `use flake`).

On **Claude Code web** you don't run this by hand: the `SessionStart` hook in
`.claude/settings.json` (`.claude/hooks/session-start.sh`) runs
`.claude/scripts/ccweb-init.sh` automatically before the session starts, so
`nix` and the toolchain are on
PATH from the first command. The hook is gated on `CLAUDE_CODE_REMOTE=true`, so
local sessions are left to manage their own nix/direnv. It is synchronous —
the session waits for the bootstrap to finish — which trades a slower start for
a guarantee that tools are ready (no race). Switch the hook to async mode if
you prefer a faster startup.

## Dev environment

Everything lives in the nix devShell — never assume host tools.

```bash
nix develop                    # enter the shell
nix develop --command <cmd>    # run one command in it
```

The devShell provides: `pkf` (task runner), `apm` (skill/prompt distribution),
`pkl` (Taskfile engine), `gitleaks` (secret scan), `ast-grep` (structural
search). There is intentionally **no** language runtime.

## Tasks

Tasks are defined in `Taskfile.pkl` and run with `pkf`:

```bash
pkf list           # list tasks
pkf run ci         # CI gate: verify-tools + full-history gitleaks scan
pkf run setup      # apm install
```

`pkf run ci` is the gate CI runs (`.github/workflows/test.yml`). Add
per-project build / test / lint tasks as `deps` of the `ci` task — the
workflow then needs no edits.

## Gotchas (read before debugging the toolchain)

- **Sandbox must be on.** With `sandbox = false`, nix builds run with
  `HOME=/homeless-shelter` on the real filesystem; pkfire's Go build writes
  telemetry there and the *next* build aborts with
  `home directory '/homeless-shelter' exists`. `ccweb-init.sh` enables the sandbox
  where the kernel allows it; if you see that error, check `nix.conf` and
  remove `/homeless-shelter`.
- **pkl needs the system CA once.** `pkf` evaluates `Taskfile.pkl`, whose
  `amends` fetches the pkfire schema from `pkg.pkl-lang.org`. pkl's bundled JVM
  truststore does not chain to that host, so the first fetch fails with an SSL
  handshake error. The devShell `shellHook` warms the pkl package cache with
  the system CA bundle; later `pkf` runs hit the cache offline. If a fetch
  fails, ensure `NIX_SSL_CERT_FILE` points at a real bundle and re-enter the
  shell.

## Conventions

- Secrets: a `pre-push` git hook runs a gitleaks scan (`pkf hooks install`,
  wired automatically by `.envrc`). Never commit secrets; put local overrides
  in `.env.local` (gitignored).
- APM: `apm.yml` + `apm.lock.yaml` are tracked; deployed skills under
  `.claude/skills/` and `.github/skills/` are gitignored — regenerate with
  `apm install`. Pin dependencies by commit/tag to keep resolution
  reproducible.

## Per-project next steps

1. Add a language to `flake.nix` (`pkgs.nodejs_24`, `rust-overlay`, …).
2. Run `skill-selector` to pick the skills this repo needs, then append them to
   `apm.yml`.
3. Add build / test / lint tasks to `Taskfile.pkl` as `deps` of `ci`.
