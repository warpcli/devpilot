# Projects

Projects are named paths with optional namespace, language, framework, tags,
and timestamps.

```sh
dp project add api --path ~/code/api --language Go --tags service
dp project list --json
dp project info api
dp project set api --framework cobra
dp project discover ~/code --depth 2
dp project import ~/code --dry-run
```
