# Machines

Machines store SSH targets and host interfaces.

```sh
dp machine add lab 127.0.0.1:22:local --username "$USER"
dp machine ssh-config lab
dp machine connect lab --dry-run
dp machine check lab --timeout 1000
```
