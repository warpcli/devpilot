import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("workspaces")
let dp = dp(envPrefix)

let projectPath = "/tmp/devpilot-workspaces-api"
let componentPath = "/tmp/devpilot-workspaces-tool"
let missingPath = "/tmp/devpilot-workspaces-missing"
resetDir(projectPath)
resetDir(componentPath)
removeDir(missingPath)

discard checked(dp & "project add api --path " & quoteShell(projectPath))
discard checked(dp & "workspace add lab --path /tmp/lab --description test --projects api")
discard checked(dp & "workspace component lab add tool --type tool --path " &
    quoteShell(componentPath))

let raw = checked(dp & "workspace list --raw")
doAssert "lab\t/tmp/lab\tapi" in raw

let info = checked(dp & "workspace info lab")
doAssert info.contains("Workspace: lab")
doAssert info.contains("Description: test")
doAssert info.contains("tool: tool")

let initialStatus = checked(dp & "workspace status lab")
doAssert initialStatus.contains("Workspace: lab")
doAssert initialStatus.contains("api")
doAssert initialStatus.contains("non-git")

discard checked(dp & "workspace run lab -- sh -c " & quoteShell(
    "pwd > .devpilot-pwd"))
doAssert fileExists(projectPath / ".devpilot-pwd")
doAssert fileExists(componentPath / ".devpilot-pwd")

let parallelRun = checked(dp & "workspace run lab --parallel -- sh -c " &
    quoteShell("echo ok"))
doAssert parallelRun.contains("[api] ok")
doAssert parallelRun.contains("[tool] ok")

let failedRun = run(dp & "workspace run lab -- sh -c " & quoteShell("exit 7"))
doAssert failedRun.code != 0

let openDryRun = checked(dp & "workspace open lab --editor code --dry-run")
doAssert openDryRun.contains("Would run: code")

let missingEditor = run(dp & "workspace open lab --editor /tmp/devpilot-no-editor")
doAssert missingEditor.code != 0
doAssert missingEditor.output.contains("Unable to open workspace editor")

let envOutput = checked(dp & "workspace env lab")
doAssert envOutput.contains("export DEVPILOT_WORKSPACE=lab")
doAssert envOutput.contains("export DEVPILOT_WORKSPACE_ROOT=/tmp/lab")
let direnvOutput = checked(dp & "workspace env lab --format direnv")
doAssert direnvOutput.contains("direnv configuration")

if run("command -v git").code == 0:
  discard checked("git -C " & quoteShell(projectPath) & " init")
  let gitStatus = checked(dp & "workspace status lab")
  doAssert gitStatus.contains("dirty") or gitStatus.contains("clean")

discard checked(dp & "workspace component lab add missing --type tool --path " &
    quoteShell(missingPath))
let missingStatus = checked(dp & "workspace status lab")
doAssert missingStatus.contains("missing")

discard checked(dp & "workspace set lab --path /tmp/lab2 --description updated")
let updated = checked(dp & "workspace info lab")
doAssert updated.contains("Path: /tmp/lab2")
doAssert updated.contains("Description: updated")

discard checked(dp & "workspace project add lab api2")
discard checked(dp & "workspace project add lab api2")
let withProject = checked(dp & "workspace info lab")
doAssert withProject.contains("Projects: api, api2")
discard checked(dp & "workspace project remove lab api")
let withoutProject = checked(dp & "workspace info lab")
doAssert withoutProject.contains("Projects: api2")

discard checked(dp & "workspace rename lab lab2")
let renamed = checked(dp & "workspace info lab2")
doAssert renamed.contains("Workspace: lab2")

discard checked(dp & "workspace add other --path /tmp/other")
let duplicateRename = run(dp & "workspace rename lab2 other")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")

discard checked(dp & "workspace component lab2 remove tool")

let componentList = checked(dp & "workspace component lab2 list")
doAssert not componentList.contains("tool: tool")

let missingWorkspace = run(dp & "workspace project add missing api")
doAssert missingWorkspace.code != 0
doAssert missingWorkspace.output.contains("not found")

discard checked(dp & "workspace remove lab2")

let missing = run(dp & "workspace info lab2")
doAssert missing.code != 0
