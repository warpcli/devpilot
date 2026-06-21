# Package

version       = "0.1.10"
author        = "Trim Bresilla"
description   = "Development workflow and project management CLI"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["dp"]

requires "nim >= 2.2.0"
requires "illwill >= 0.4.1"

task test, "Run CLI regression tests":
  exec "nim c -r tests/test_cli.nim"
