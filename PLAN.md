# dococ — Plan

Run opencode inside a Docker container with the relevant folders already mounted, giving
agent isolation while keeping sessions and configuration shared with the host.

## Goals

- Drop into an opencode execution inside a container with one command from a project folder.
- Sessions survive the death of the container and can be resumed by a new container.
- Default to sharing the host's opencode configuration, auth, and database.
- Support opt-in per-project isolation and cross-project folder mounts.
- Minimal ceremony: reuse an existing container for the project when possible.

## Context gathered

- `opencode` binary: standalone ELF v1.18.25, glibc-linked (`/usr/lib/libc.so.6`), so the
  base image must be glibc (Ubuntu/Debian), not Alpine/musl.
- Plugins (`@tarquinen/opencode-dcp`, `@sliker/opencode-quota`) and the playwright MCP run
  under node/`npx`, so the image needs node + npx (and a browser for the playwright MCP).
- Host data layout:
  - `~/.config/opencode/` — opencode.json / opencode.jsonc (config, plugins, MCP)
  - `~/.local/share/opencode/` — main data: `opencode.db` (SQLite, WAL mode), `auth.json`,
    `snapshot/`, `worktree/`, etc.
  - `~/.local/state/opencode/` — locks, `model.json`, `prompt-history.jsonl`, `session.json`
  - `~/.cache/opencode/` — plugin node_modules, `models.json`, quota state
- Active providers are internet APIs (opencode / opencode-go / openrouter / github-copilot /
  google). The `localhost:3000` openai block in `opencode.jsonc` is stale/unused — nothing
  listens there and it is not in active use, so no local-provider networking rewrite is needed
  for this setup.
- SQLite is in WAL mode; opencode already handles multiple sessions (plus subagent fork
  sessions via `session.parent_id`) writing to one DB. Per-session isolation is opencode's
  concern, not dococ's.

## Design decisions

- **Image**: custom, built from a `Dockerfile` in this repo. Ubuntu base + node + npx +
  opencode binary copied from `~/.opencode/bin/opencode`. Rebuilt on host binary change via
  `dococ update`.
- **DB handling**: shared by default (mount the real `~/.local/share/opencode`), opt-in
  isolation via `--isolated` (per-project fresh data dir).
- **Reuse semantics**: `dococ` with no args reuses an existing container for the project if
  present, else creates one.
- **Cleanup**: keep exited containers by default; `--rm` destroys on exit.
- **Config**: global `~/.config/dococ/config.sh` + optional per-project `.dococ` file.
  Precedence: CLI > project > global.
- **Language**: Bash (shell orchestration only; see "Language" below).

## Container identity

- Container name computed from the project: `dococ-<dirname>-<hash>` where hash is a short
  digest of the absolute project path (avoids collisions between same-named dirs).
- `--new` forces a new container (removes the old one for the project first).

## Default mounts

| Host                         | Container                       | Mode |
|------------------------------|---------------------------------|------|
| `$PWD` (project)             | `/workspace`                    | rw   |
| `~/.config/opencode/`        | `~/.config/opencode/`           | ro   |
| `~/.local/share/opencode/`   | `~/.local/share/opencode/`      | rw   |
| `~/.local/state/opencode/`   | `~/.local/state/opencode/`      | rw   |
| `~/.cache/opencode/`         | `~/.cache/opencode/`            | rw   |

## CLI surface

Subcommands: `dococ [flags]` (default: run/attach), `dococ status`, `dococ clean`,
`dococ update`.

Flags:
- `--mount PATH` (repeatable) — mount an extra folder for cross-project access.
- `--mount-file PATH` (repeatable) — mount an individual file (e.g. env files).
- `--isolated` — per-project fresh opencode data dir instead of the shared DB.
- `--new` / `-n` — force a new container (remove existing one for the project first).
- `--rm` — destroy the container on exit (default is keep).
- `--keep` — keep the container on exit (explicit; the default).
- `--env KEY=VAL` (repeatable) — pass env vars into the container.
- `--offline` — run with `--network none` for pure local work.
- `--command CMD` — run a one-off command in the container instead of the opencode TUI.

Subcommand details:
- `status` — list dococ containers (name, project, running/stopped).
- `clean` — remove all dococ containers.
- `update` — rebuild the image from the current host binary.

## Config files

Global `~/.config/dococ/config.sh` (Bash-sourced) supports, e.g.:
- `DOCOC_IMAGE` — image name/tag.
- `DOCOC_MOUNTS` — array of extra host dirs to mount.
- `DOCOC_ENV` — array of `KEY=VAL`.
- `DOCOC_OFFLINE`, `DOCOC_REMOVE`, etc. — default flags.

Project `.dococ` (same format, loaded after global) overrides/extends per project. Precedence:
CLI flags > project config > global config > built-in defaults.

## Implementation notes

- Run docker with `--user $(id -u):$(id -g)` (or a mapped user) so mounted files are not
  root-owned.
- Set `set -euo pipefail`; carefully quote all paths (spaces in dir names); use Bash arrays
  for mounts/env to avoid quoting bugs.
- The DB is shared by default, so do not copy it; mount it live.
- For `--isolated`, back up nothing on the host; each project gets a dedicated data dir under
  `~/.local/share/dococ/<hash>/` mounted at the container's opencode data path, seeded with
  config/auth.

## Deliverables

- `dococ` — the main Bash script.
- `Dockerfile` — builds the opencode container image.
- `README.md` — project overview; how to install/run; configuration and CLI arguments;
  authorship and license.
- `LICENSE` — license file.
- `PLAN.md` — this planning document.

## README.md contents

- What dococ is and the workflow it automates.
- How to install (build image, place script on PATH) and how to run.
- Configuration: global `~/.config/dococ/config.sh` and per-project `.dococ`.
- Full CLI arguments/subcommands table.
- Authorship and license.
- Note on the security model: shared opencode state by default, `--isolated` opt-in.

## Authoring

- License: MIT.
- Author: André Santos (for README, LICENSE, and any header comments).

## Language note

Bash is sufficient and idiomatic here because the tool is thin shell/docker orchestration with
simple scalar opts. If the config schema, flag surface, or multi-container coordination grows
significantly, consider migrating to Python or Go (better data structures, validation, test
surface). Decide this when the v1 spec stabilizes.
