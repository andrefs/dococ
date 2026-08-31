# dococ

Run `opencode` inside a Docker container with the relevant folders already mounted, giving
agent isolation while keeping sessions and configuration shared with the host.

`dococ` is a thin Bash wrapper around Docker. From a project folder it drops you into an
opencode session running in a container whose workspace is your project, and whose opencode
state is your host's — so sessions, config, auth, and cache all carry over. Containers are
reused across invocations, so you can leave the agent working and come back to the same
session later.

## Why

- One command to run the agent in an isolated runtime (dependencies, tools, and a fresh
  filesystem) without contaminating your host.
- Sessions survive container restarts — opencode's database lives on the host by default.
- Expected to be opencode-aware: the image installs the standalone opencode binary plus the
  runtime (node/npx) its plugins and MCPs need.

## Requirements

- Docker (tested against Docker 29.x).
- A POSIX shell with Bash (the script uses Bash arrays and `mapfile`).
- The opencode container image built once (see [Install](#install)).

## Install

Clone this repository and build the image:

```sh
git clone https://github.com/your-name/dococ
cd dococ
./dococ update        # builds the dococ/opencode:latest image
```

Place the `dococ` script somewhere on your `PATH` (or run it via its absolute path):

```sh
install -m 0755 dococ ~/.local/bin/dococ
```

To pick up a newer opencode release, rebuild the image with `dococ update`.

## Usage

Run dococ from a project folder:

```sh
cd ~/src/my-project
dococ                # open (or reuse) the container for this project, launch opencode
dococ --command 'make test'   # run a one-off command in the project container
dococ status         # list dococ containers
dococ clean          # remove all dococ containers
dococ update         # rebuild the opencode image
```

With no subcommand, `dococ` creates a container for the current project if needed and launches
the opencode TUI inside it. The container is kept running after the session ends (default), so
the next `dococ` in the same folder reuses it. Use `--rm` to destroy it on exit.

### Container identity

Each project gets its own container, named `dococ-<dirname>-<hash>` where `<hash>` is a digest
of the project's absolute path (so same-named folders in different locations don't collide).
`--new` forces a new container for the project, removing the previous one first.

## Configuration

### Command-line arguments

| Flag | Description |
|------|-------------|
| `-m, --mount PATH` | Mount an extra host folder into the container (repeatable). |
| `--mount-file PATH` | Mount an individual file, read-only (repeatable). |
| `-e, --env KEY=VAL` | Set an environment variable in the container (repeatable). |
| `--isolated` | Use a per-project opencode data dir instead of the shared database. |
| `-n, --new` | Force a new container (removes the existing one for the project). |
| `--rm` | Remove the container when the session ends (default is keep). |
| `--keep` | Keep the container on exit (explicit; the default). |
| `--offline` | Run with `--network none` for purely local work. |
| `--command CMD` | Run `CMD` in the project container instead of the opencode TUI. |
| `-h, --help` | Show help. |
| `-v, --version` | Show version. |

### Config files

Two Bash-sourced config files allow setting defaults:

- **Global** — `~/.config/dococ/config.sh`
- **Per-project** — `.dococ` in the project root (loaded after the global file)

Both may set `DOCOC_*` variables and append to the `DOCOC_MOUNTS`, `DOCOC_MOUNT_FILES`, and
`DOCOC_ENV` arrays. Precedence is: CLI flags > project config > global config > built-in
defaults.

Example `~/.config/dococ/config.sh`:

```sh
DOCOC_IMAGE="dococ/opencode:latest"
DOCOC_MOUNTS=(~/notes ~/secrets)
DOCOC_ENV=(EDITOR=vim)
DOCOC_OFFLINE=0
```

### Default mounts

Host state is mounted under the container's home directory (`/home/ubuntu`), so the
containerized opencode reads it via `$HOME` and the host username never appears in the
container.

| Host | Container | Mode |
|------|-----------|------|
| `$PWD` (project) | `/workspace` | rw |
| `~/.config/opencode/` | `/home/ubuntu/.config/opencode/` | ro |
| `~/.local/share/opencode/` | `/home/ubuntu/.local/share/opencode/` | rw |
| `~/.local/share/opencode/auth.json` | `/home/ubuntu/.local/share/opencode/auth.json` | ro |
| `~/.local/state/opencode/` | `/home/ubuntu/.local/state/opencode/` | rw |
| `~/.cache/opencode/` | `/home/ubuntu/.cache/opencode/` | ro |
| `~/.agents/` (skills) | `/home/ubuntu/.agents/` | ro |

## Security model

dococ runs the opencode agent in a container that shares your host's opencode state, so your
config, session history, and credentials carry over. Because the whole point is that the agent
works as you on your files, dococ deliberately keeps some host state reachable. What follows is
an explicit mapping of what is exposed and what is deliberately left open in exchange for
usability.

### What is protected

- **Credentials are read-only.** `auth.json` is bind-mounted read-only (overlaid on the
  read-write data mount), so the agent can use the API keys it authenticates with but cannot
  rewrite them or swap the provider endpoints they point at.
- **Plugin & tool code is read-only.** `~/.cache/opencode/` (plugin `node_modules`, LSP servers,
  quota state) is mounted read-only, so a compromised agent cannot tamper with the executable
  code that later runs on the host.
- **Skills are read-only.** `~/.agents/` is mounted read-only.
- **Leased privilege.** The container drops all Linux capabilities (`--cap-drop ALL`) and runs
  with `no-new-privileges`, which raises the barrier against setuid/kernel-privilege escalation
  while leaving normal usage unaffected.

### Accepted tradeoffs (for usability)

- **Network access is on by default.** opencode must reach model APIs (OpenAI, Anthropic, ...),
  so `--network none` is opt-in via `--offline`. This means the agent can exfiltrate anything it
  can read, but no more than any process you run with your credentials could.
- **The agent is your user.** dococ runs with `--user $(id -u):$(id -g)`, so anything your user
  can write on a *mounted* path, the agent can write. This is required for the project workspace
  and session DB to be shared.
- **The shared data mount is writable.** The opencode session database (`~/.local/share/opencode/`)
  is mounted read-write so sessions persist across container runs. The agent could therefore
  modify its own session history. Use `--isolated` for a per-project clean session store.
- **Extra mounts are the user's call.** `--mount PATH` and `--mount-file PATH` mount host paths
  exactly as given (read-write for `--mount`). dococ does not filter these: mounting `~/.ssh`,
  `/`, or `~/.gnupg` hands the container the host filesystem. They are a deliberate
  power-user escape hatch, not something the agent can add on its own.
- **Installing skills/MCPs/plugins happens on the host.** Because the config and cache dirs (and
  thus plugin/LSP state) are mounted read-only, the container is a *consumer*, not an installer.
  Add or update skills, MCPs, or plugins from the host; the container picks them up on its next
  run.
- **The container filesystem is writable** and containers persist by default (`--rm` opts out),
  so a compromised session can lay down a foothold inside the container. It has no privilege and
  the read-only mounts limit what it can reach, but it survives across sessions until you `dococ
  clean`.

### Per-project isolation

Pass `--isolated` (or set `DOCOC_ISOLATED=1` in config). Each project then gets a dedicated
opencode data directory under `~/.local/share/dococ/<project>-<hash>/`, seeded with your
`auth.json` (read-only) so providers still work, but with a clean session database. Switching
isolation mode for a project recreates its container automatically.

## Layout

```
dococ        the wrapper script
Dockerfile   builds the opencode container image
PLAN.md      the design document
```

## License

MIT. Author: André Santos.

See [LICENSE](LICENSE).
