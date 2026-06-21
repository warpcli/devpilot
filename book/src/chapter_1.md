# Introduction

`devpilot` is a language-neutral development workflow CLI. It tracks projects,
workspaces, machines, reusable templates, and the local metadata needed to move
between them quickly.

The tool is implemented in Nim, but the product is not Nim-specific: projects
can be Go, Rust, Nim, Python, Node, Zig, or anything else with a filesystem
path.

Core commands:

- `dp project ...`
- `dp workspace ...`
- `dp machine ...`
- `dp template ...`
- `dp backup ...`
- `dp tui`
