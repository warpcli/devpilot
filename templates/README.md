# devpilot bundled templates

Install these into your devpilot template registry:

```sh
dp template builtins install
```

Then create projects:

```sh
dp template apply go-cli /tmp/my-go-tool --name my_go_tool
dp template apply zig-cli /tmp/my-zig-tool --name my_zig_tool
dp template apply nim-cli /tmp/my-nim-tool --name my_nim_tool
```

The apply command replaces placeholders in file contents and file names.

