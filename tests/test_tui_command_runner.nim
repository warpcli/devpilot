import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("tui-command")
let dp = dp(envPrefix)

let emptySnapshot = checked(dp & "tui --snapshot")
doAssert emptySnapshot.contains("devpilot tui")
doAssert emptySnapshot.contains("Projects:")

discard checked(dp & "tui --command " &
    quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))

let populatedSnapshot = checked(dp & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")

let blockedNested = run(dp & "tui --command " & quoteShell("tui --snapshot"))
doAssert blockedNested.code != 0
doAssert blockedNested.output.contains("Nested TUI commands")

let blockedSsh = run(dp & "tui --command " & quoteShell("machine connect lab"))
doAssert blockedSsh.code != 0
doAssert blockedSsh.output.contains("Interactive ssh is disabled")
