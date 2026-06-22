# Templates

Templates are copied safely with conflict detection, optional dry-runs, and
explicit symlink handling.

```sh
dp template add base --description "Base app" --path ./template
dp template apply base /tmp/new-app --name new_app --dry-run
dp template apply base /tmp/new-app --name new_app --skip-existing
```

Bundled starter templates are available for Go, Zig, and Nim CLIs:

```sh
dp template builtins list
dp template builtins install
dp template apply go-cli /tmp/my-go-tool --name my_go_tool
dp template apply zig-cli /tmp/my-zig-tool --name my_zig_tool
dp template apply nim-cli /tmp/my-nim-tool --name my_nim_tool
```

Template placeholders are replaced in both file contents and file names, so
`{{snake_name}}.nimble` becomes `my_nim_tool.nimble`.
