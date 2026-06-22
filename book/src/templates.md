# Templates

Templates are copied safely with conflict detection, optional dry-runs, and
explicit symlink handling.

```sh
dp template add base --description "Base app" --path ./template
dp template apply base /tmp/new-app --name new_app --dry-run
dp template apply base /tmp/new-app --name new_app --skip-existing
```

Bundled starter templates are available for Go, Zig, Nim, Rust, and C++:

```sh
dp init
dp template builtins list
dp template apply go /tmp/my-go-tool --name my_go_tool
dp template apply zig /tmp/my-zig-tool --name my_zig_tool
dp template apply nim /tmp/my-nim-tool --name my_nim_tool
dp template apply rust /tmp/my-rust-lib --name my_rust_lib
dp template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
```

Template placeholders are replaced in both file contents and file names, so
`{{snake_name}}.nimble` becomes `my_nim_tool.nimble`.

The bundled templates are embedded in the `dp` binary. `dp init` writes them to
`$XDG_DATA_HOME/devpilot/templates` and registers `go`, `zig`, `nim`, `rust`,
and `cpp`.

The embedded templates share one common base for files like `.envrc`,
`flake.nix`, `README.md`, `.gitignore`, and `PROJECT`; each language directory
only overlays its unique source, build, test, and workflow files.
