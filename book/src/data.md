# Data and backup

Data is stored under `$XDG_DATA_HOME/devpilot` or
`~/.local/share/devpilot`.

Files:

- `projects.toml`
- `workspaces.toml`
- `machines.toml`
- `templates.toml`

Backup and restore:

```sh
dp backup create --path ./devpilot-backup
dp backup restore ./devpilot-backup --force
dp export --format json
dp import ./devpilot-backup --merge
```
