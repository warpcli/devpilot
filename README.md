<img align="right" width="32%" src="./misc/pilot.png">

devpilot
===

`devpilot` is a local development workflow CLI. The binary is `dp`.

## Features

- Manage named projects with namespace, path, language, framework, template, and tag metadata.
- Manage workspaces and attach components to them.
- Manage reusable file/directory templates and apply them to new target directories.
- Manage SSH machine entries and connect through stored host/interface metadata.
- Browse all stored development data through an `illwill`-backed terminal dashboard.
- Store user data as small TOML files under the platform data directory (`$XDG_DATA_HOME/devpilot` on Linux when set).

## Development

This repo uses `flake.nix` for the development environment. The implementation is written in Nim, but `devpilot` itself is language-neutral.

```sh
direnv allow
```

or directly:

```sh
nix develop --impure
```

Build:

```sh
nimble build -y
```

Test:

```sh
nimble test -y
```

Run:

```sh
nimble run -y -- --help
```

After `nimble build`, the binary is available at:

```sh
./bin/dp --help
```

## Usage

```sh
dp --help
dp project add my-app --path ~/code/my-app --language go --tags cli
dp project list --raw
dp workspace add lab --path ~/code --projects my-app
dp template add basic --description "Basic app" --path ./template --language go
dp machine add lab 127.0.0.1:22:local --username "$USER"
dp tui
```

## TUI

The full-screen TUI uses [`illwill`](https://github.com/johnnovak/illwill) as a small terminal backend.

```sh
dp tui
```

Keys: `Left`/`Right` or `h`/`l` switch sections, `Up`/`Down` or `j`/`k` move the selection, `r` reloads data, and `q`/`Esc` quits.

Management keys:

- `Enter` shows details for the selected project, workspace, machine, or template.
- `/` filters the current section.
- `:` opens a command palette that runs any non-interactive `dp` command and reloads the dashboard.
- `a` opens a prefilled add command for the current section.
- `d` deletes the selected row after typing `yes`.
- `?` shows the in-app key reference.

For CI or scripting, the TUI also has non-fullscreen modes:

```sh
dp tui --snapshot
dp tui --command "project add sample --path /tmp/sample --language go"
```

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md).
