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

Clone this repository and build the base image:

```sh
git clone https://github.com/your-name/dococ
cd dococ
./dococ update        # builds the dococ/opencode:base image
```

Place the `dococ` script somewhere on your `PATH` (or run it via its absolute path):

```sh
install -m 0755 dococ ~/.local/bin/dococ
```

To pick up a newer opencode release, rebuild the image with `dococ update`.

## Quick Start

```sh
cd ~/src/my-project
dococ init          # runs opencode to analyze project, generates .dococ, builds image with LSPs
dococ               # launch opencode
```

The `dococ init` command runs `opencode` to automatically analyze your project and generate a tailored `.dococ` configuration file, then builds the container image with the appropriate apt packages and language server setup commands. If a `.dococ` already exists, you'll be prompted before overwriting.

## Usage

Run dococ from a project folder:

```sh
cd ~/src/my-project
dococ                # open (or reuse) the container for this project, launch opencode
dococ --command 'make test'   # run a one-off command in the project container
dococ init           # generate config, build image (first time only)
dococ gen-config     # generate .dococ by analyzing project with opencode
dococ images         # list all dococ container images
dococ list           # list this project's containers
dococ status         # list all dococ containers
dococ clean          # remove all dococ containers
dococ update         # (re)build the project's opencode image (uses .dococ apt packages + LSPs)
```

With no subcommand, `dococ` creates a container for the current project if needed and launches
the opencode TUI inside it. The container is kept running after the session ends (default), so
the next `dococ` in the same folder reuses it. Use `--rm` to destroy it on exit.

### Container identity

Each project gets one **canonical** container named `dococ-<dirname>-<hash>` where `<hash>` is a
digest of the project's absolute path (so same-named folders in different locations don't
collide). A plain `dococ` always reuses the canonical container for the current project.

You can manage containers per project:

- `--new` — create a fresh canonical container, keeping the old one by renaming it to
  `dococ-<dirname>-<hash>.retired-<timestamp>-<pid>`.
- `--replace` — destroy every container for the project, then create a fresh one.
- `--pick [NAME]` — use a specific container for this run. With a container `NAME`, use it
  directly (any dococ container on the system, not just this project's — an explicit escape
  hatch; the canonical name is left unchanged); without one, list this project's containers
  and choose interactively (including a "new container" option).
- `dococ list` — list this project's containers, marking the canonical one.

Each project also gets its own **container image** (`dococ/opencode:<project-hash>`) built
with the project's declared apt packages and LSP setup commands (see [System packages](#system-packages-apt)
and [Language servers](#language-servers)). If a project declares no extra packages and has no `.dococ` file, a shared base image
(`dococ/opencode:base`) is used.

### Session portability

The project directory is mounted at its host-absolute path inside the container, and that path
is used as the container's `WORKDIR`. This means sessions created on the host can be resumed
in the container, and vice versa — opencode records the same absolute path in both environments.

## Configuration

### Command-line arguments

| Flag | Description |
|------|-------------|
| `-m, --mount PATH` | Mount an extra host folder into the container (repeatable). |
| `--mount-file PATH` | Mount an individual file, read-only (repeatable). |
| `-e, --env KEY=VAL` | Set an environment variable in the container (repeatable). |
| `--isolated` | Use a per-project opencode data dir instead of the shared database. |
| `-n, --new` | Create a fresh canonical container, keeping the old one (renamed `.retired-<ts>-<pid>`). |
| `--replace` | Destroy the project's container(s), then create a fresh one. |
| `--pick [NAME]` | Use a specific container this run; with `NAME`, target any dococ container directly; without it, pick interactively. |
| `--rm` | Remove the container when the session ends (default is keep). |
| `--keep` | Keep the container on exit (explicit; the default). |
| `--offline` | Run with `--network none` for purely local work. |
| `--command CMD` | Run `CMD` in the project container instead of the opencode TUI. |
| `--config-file PATH` | Per-project config file (default: `./.dococ`). |
| `--global-config PATH` | Global config file (default: `~/.config/dococ/config.sh`). |
| `--output PATH` | Output file for gen-config (default: `./.dococ`). |
| `-h, --help` | Show help. |
| `-v, --version` | Show version. |

### Config files

Two Bash-sourced config files allow setting defaults:

- **Global** — `~/.config/dococ/config.sh`
- **Per-project** — `.dococ` in the project root (loaded after the global file)

Both may set `DOCOC_*` variables and append to the `DOCOC_MOUNTS`, `DOCOC_MOUNT_FILES`,
`DOCOC_ENV`, `DOCOC_APT_PACKAGES`, and `DOCOC_SETUP_COMMANDS` arrays. Precedence is: CLI flags > project config >
global config > built-in defaults.

### System packages (apt)

Declare additional apt packages to be installed in the project's container image via
`DOCOC_APT_PACKAGES`. Each project gets its own image (`dococ/opencode:<project-hash>`)
built with the merged package list from global + project config.

```sh
# In ~/.config/dococ/config.sh or .dococ
DOCOC_APT_PACKAGES=(cargo golang python3)
```

Run `dococ update` from the project directory to (re)build the image with those packages.
If no apt packages are declared and no `.dococ` file exists, a shared base image
(`dococ/opencode:base`) is used.

### Language servers

Declare language server installation commands in `DOCOC_SETUP_COMMANDS`. These run at
**build time** as the `ubuntu` user, so LSPs are pre-installed in the image and ready
immediately.

```sh
# In .dococ (generated by `dococ gen-config` or manually)
DOCOC_SETUP_COMMANDS=(
    "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    "source /home/ubuntu/.cargo/env && rustup component add rust-analyzer"
    "source /home/ubuntu/.cargo/env && rustup component add clippy rustfmt"
)
```

Common examples:
- **Rust**: `rustup component add rust-analyzer clippy rustfmt`
- **Go**: `go install golang.org/x/tools/gopls@latest`
- **Python**: `pip install pyright`
- **TypeScript**: `npm i -g typescript-language-server`
- **Lua**: `cargo install --locked lua-language-server`

The image build adds common tool paths to `PATH` (`~/.cargo/bin`, `~/.npm-global/bin`, `~/go/bin`, `~/.local/bin`)
so these commands work at build time.

`dococ gen-config` detects the project type and suggests appropriate LSP install commands by running **opencode** to analyze your project.

Example `~/.config/dococ/config.sh`:

```sh
DOCOC_IMAGE="dococ/opencode:latest"
DOCOC_APT_PACKAGES=(cargo)
DOCOC_SETUP_COMMANDS=("rustup component add rust-analyzer")
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
| `$PWD` (project) | `/workspace` (and host path) | rw |
| `~/.config/opencode/` | `/home/ubuntu/.config/opencode/` | ro |
| `~/.local/share/opencode/` | `/home/ubuntu/.local/share/opencode/` | rw |
| `~/.local/share/opencode/auth.json` | `/home/ubuntu/.local/share/opencode/auth.json` | ro |
| `~/.local/state/opencode/` | `/home/ubuntu/.local/state/opencode/` | rw |
| `~/.cache/opencode/` | `/home/ubuntu/.cache/opencode/` | rw* |
| `~/.agents/` (skills) | `/home/ubuntu/.agents/` | ro |

| * | `rw*` — `node_modules`, `packages`, and `bin` subdirectories are overlaid read-only to keep plugin/LSP code immutable. |

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `init` | Initialize project: runs **opencode** to analyze project and generate `.dococ` config, then builds image |
| `gen-config` | Runs **opencode** to analyze the project and generate `.dococ` config (interactive, shows thinking) |
| `update` | Build the project's container image (uses `.dococ` apt packages + LSP setup commands) |
| `images` | List all dococ container images |
| `list` | List this project's containers (marks canonical) |
| `status` | List all dococ containers across projects |
| `clean` | Remove all dococ containers |
| `run` | Default: launch opencode in project container |

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
- **Skills are read-only.** `~/.agents/` is mounted read-only.
- **Configuration is read-only.** `~/.config/opencode/` is mounted read-only, so the agent can
  read but not rewrite your provider/model configuration or endpoints.
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
- **The opencode cache is writable with immutable plugins.** `~/.cache/opencode/` is mounted
  read-write so opencode can refresh its models catalog (`models.json`) and write cache data,
  but its `node_modules`, `packages`, and `bin` subdirectories are overlaid read-only to keep
  installed plugin/LSP code immutable. A compromised agent can tamper with cache data
  but not with executable plugin code. (Config and skills stay read-only.)
- **Installing skills/MCPs/plugins happens on the host.** Because the config dir is mounted
  read-only, plugin/MCP/skill *configuration* cannot be written from inside the container; add or
  update them from the host, and the container picks them up on its next run.
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
Dockerfile   builds the opencode container image (also embedded in script)
PLAN.md      the design document
```

## License

MIT. Author: André Santos.

See [LICENSE](LICENSE).