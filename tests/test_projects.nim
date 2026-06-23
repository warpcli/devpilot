import std/strutils

import test_support

compileBinary()

let envPrefix = freshEnv("projects")
let dp = dp(envPrefix)

discard checked(dp & "project add demo --path /tmp/demo --language go --framework cobra --tags cli")

let raw = checked(dp & "project list --raw")
doAssert "demo\tdefault\t/tmp/demo\tgo" in raw

let info = checked(dp & "project info demo")
doAssert info.contains("Project: demo")
doAssert info.contains("Framework: cobra")
doAssert info.contains("Tags: cli")

discard checked(dp & "project set demo --path /tmp/demo2 --language nim " &
    "--framework bobabrew --description updated")
let updated = checked(dp & "project info demo")
doAssert updated.contains("Path: /tmp/demo2")
doAssert updated.contains("Language: nim")
doAssert updated.contains("Framework: bobabrew")
doAssert updated.contains("Description: updated")

discard checked(dp & "project tag add demo tui")
discard checked(dp & "project tag add demo tui")
let tagged = checked(dp & "project info demo")
doAssert tagged.contains("Tags: cli, tui")
discard checked(dp & "project tag remove demo cli")
let untagged = checked(dp & "project info demo")
doAssert untagged.contains("Tags: tui")

discard checked(dp & "project rename demo renamed")
let renamed = checked(dp & "project info renamed")
doAssert renamed.contains("Project: renamed")

let duplicate = run(dp & "project add demo --path /tmp/other")
doAssert duplicate.code == 0
let duplicateRename = run(dp & "project rename renamed demo")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")

discard checked(dp & "project --namespace other add renamed --path /tmp/other")
discard checked(dp & "project --namespace other set renamed --language zig")
let defaultInfo = checked(dp & "project info renamed")
doAssert defaultInfo.contains("Language: nim")
let otherInfo = checked(dp & "project --namespace other info renamed")
doAssert otherInfo.contains("Language: zig")

discard checked(dp & "project remove renamed")

let missing = run(dp & "project info renamed")
doAssert missing.code != 0
