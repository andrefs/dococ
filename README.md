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
| `~/.local/state/opencode/` | `/home/ubuntu/.local/state/opencode/` | rw |
| `~/.cache/opencode/` | `/home/ubuntu/.cache/opencode/` | rw |
| `~/.agents/` (skills) | `/home/ubuntu/.agents/` | ro |

## Security model

By default, dococ shares the host's opencode state with every project: the session database,
configuration, auth, and cache. This is convenient but means the agent running in one project
can read another project's history.

For per-project isolation, pass `--isolated` (or set `DOCOC_ISOLATED=1` in config). Each
project then gets a dedicated opencode data directory under `~/.local/share/dococ/<project>-<hash>/`,
seeded with your `auth.json` so providers still work, but with a clean session database.
Switching isolation mode for a project recreates its container automatically.

## Layout

```
dococ        the wrapper script
Dockerfile   builds the opencode container image
PLAN.md      the design document
```

## License

MIT. Author: André Santos.

See [LICENSE](LICENSE).
