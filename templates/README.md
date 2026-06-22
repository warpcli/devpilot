# devpilot bundled templates

Install these into your devpilot template registry:

```sh
dp init
```

Then create projects:

```sh
dp template apply go /tmp/my-go-tool --name my_go_tool
dp template apply zig /tmp/my-zig-tool --name my_zig_tool
dp template apply nim /tmp/my-nim-tool --name my_nim_tool
dp template apply rust /tmp/my-rust-lib --name my_rust_lib
dp template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
```

The apply command replaces placeholders in file contents and file names.

Layout:

- `common/` contains shared files.
- `go/`, `zig/`, `nim/`, `rust/`, and `cpp/` overlay only language-specific files.
