import std/[os, osproc, strutils]

const Binary = "/tmp/devpilot-nim-test-dp"

proc run(command: string): tuple[output: string, code: int] =
  let output = execCmdEx(command)
  (output.output, output.exitCode)

proc checked(command: string): string =
  let res = run(command)
  doAssert res.code == 0, command & "\n" & res.output
  res.output

discard checked("nim c --out:" & quoteShell(Binary) & " src/dp.nim")

let dataHome = "/tmp/devpilot-nim-test-data"
let home = "/tmp/devpilot-nim-test-home"
removeDir(dataHome)
removeDir(home)
createDir(dataHome)
createDir(home)

let envPrefix = "XDG_DATA_HOME=" & quoteShell(dataHome) & " HOME=" & quoteShell(home) & " "
let dp = envPrefix & quoteShell(Binary) & " "

doAssert checked(dp & "--version").strip() == "0.1.10"
let tuiSnapshot = checked(dp & "tui --snapshot")
doAssert tuiSnapshot.contains("devpilot tui")
doAssert tuiSnapshot.contains("Projects:")
discard checked(dp & "tui --command " & quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))
doAssert checked(dp & "project info tui_demo").contains("Project: tui_demo")
discard checked(dp & "project remove tui_demo")

discard checked(dp & "project add demo --path /tmp/demo --language go --tags cli")
let projects = checked(dp & "project list --raw")
doAssert "demo\tdefault\t/tmp/demo\tgo" in projects
doAssert checked(dp & "project info demo").contains("Project: demo")

discard checked(dp & "workspace add lab --path /tmp/lab --projects demo")
discard checked(dp & "workspace component lab add tool --type tool --path /tmp/tool")
let workspace = checked(dp & "workspace info lab")
doAssert workspace.contains("Workspace: lab")
doAssert workspace.contains("tool: tool")

discard checked(dp & "machine add lab 127.0.0.1:22:local --username tester --key /tmp/key")
let machines = checked(dp & "machine list --raw")
doAssert "lab\ttester\t127.0.0.1\t22\tlocal" in machines
doAssert checked(dp & "machine info lab").contains("Machine: lab")

let templateRoot = "/tmp/devpilot-nim-template"
let targetRoot = "/tmp/devpilot-nim-target"
removeDir(templateRoot)
removeDir(targetRoot)
createDir(templateRoot)
writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}}")
discard checked(dp & "template add base --description sample --path " & quoteShell(templateRoot) & " --language go")
discard checked(dp & "template apply base " & quoteShell(targetRoot) & " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app"

let populatedSnapshot = checked(dp & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")
doAssert populatedSnapshot.contains("Workspaces: 1")
doAssert populatedSnapshot.contains("Templates: 1")

discard checked(dp & "project remove demo")
discard checked(dp & "workspace remove lab")
discard checked(dp & "template remove base")
discard checked(dp & "machine remove lab")

let missing = run(dp & "project info missing")
doAssert missing.code != 0
