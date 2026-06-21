# Templates

Templates are copied safely with conflict detection, optional dry-runs, and
explicit symlink handling.

```sh
dp template add base --description "Base app" --path ./template
dp template apply base /tmp/new-app --name new_app --dry-run
dp template apply base /tmp/new-app --name new_app --skip-existing
```
