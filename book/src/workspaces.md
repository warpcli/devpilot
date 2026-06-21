# Workspaces

Workspaces group projects and components so actions can run across many paths.

```sh
dp workspace add lab --path ~/code --projects api
dp workspace status lab
dp workspace run lab -- git status --short
dp workspace open lab --dry-run
dp workspace env lab --format direnv
dp workspace discover lab ~/code
```
