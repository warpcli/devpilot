import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("templates")
let dp = dp(envPrefix)

let templateRoot = "/tmp/devpilot-templates-template"
let targetRoot = "/tmp/devpilot-templates-target"
resetDir(templateRoot)
removeDir(targetRoot)

writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}} {{project-name}}")
writeFile(templateRoot / "snake.txt", "{{snake_name}} {{NAME}}")

discard checked(dp & "template add base --description sample --path " &
    quoteShell(templateRoot) & " --language go")

let dryRunTarget = "/tmp/devpilot-templates-dry-run"
removeDir(dryRunTarget)
let dryRun = checked(dp & "template apply base " & quoteShell(dryRunTarget) &
    " --name sample_app --dry-run")
doAssert dryRun.contains("Copy files:")
doAssert dryRun.contains("README.md")
doAssert not dirExists(dryRunTarget)

discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"
doAssert readFile(targetRoot / "snake.txt") == "sample_app SAMPLE_APP"

let conflict = run(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert conflict.code != 0
doAssert conflict.output.contains("Conflicts:")

writeFile(targetRoot / "README.md", "old")
discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --skip-existing")
doAssert readFile(targetRoot / "README.md") == "old"

discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --force")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"

writeFile(templateRoot / "binary.bin", "abc\0{{PROJECT_NAME}}")
let binaryOutput = checked(dp & "template apply base " & quoteShell(
    targetRoot) & " --name sample_app --force")
doAssert binaryOutput.contains("Skipped placeholder replacements:")
doAssert readFile(targetRoot / "binary.bin") == "abc\0{{PROJECT_NAME}}"

discard checked(dp & "template set base --description updated --language nim " &
    "--framework cli --path " & quoteShell(templateRoot))
let updatedTemplate = checked(dp & "template info base")
doAssert updatedTemplate.contains("Description: updated")
doAssert updatedTemplate.contains("Language: nim")
doAssert updatedTemplate.contains("Framework: cli")

discard checked(dp & "template tag add base tui")
discard checked(dp & "template tag add base tui")
let taggedTemplate = checked(dp & "template info base")
doAssert taggedTemplate.contains("Tags: tui")
discard checked(dp & "template tag remove base tui")
let untaggedTemplate = checked(dp & "template info base")
doAssert untaggedTemplate.contains("Tags: None")

discard checked(dp & "template rename base renamed")
let renamedTemplate = checked(dp & "template info renamed")
doAssert renamedTemplate.contains("Template: renamed")
discard checked(dp & "template add other --description other --path " &
    quoteShell(templateRoot))
let duplicateRename = run(dp & "template rename renamed other")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")
let badTemplatePath = run(dp & "template set renamed --path /tmp/devpilot-missing-template")
doAssert badTemplatePath.code != 0
doAssert badTemplatePath.output.contains("does not exist")

let linkTemplate = "/tmp/devpilot-templates-link-template"
let linkTarget = "/tmp/devpilot-templates-link-target"
let outside = "/tmp/devpilot-templates-outside.txt"
resetDir(linkTemplate)
removeDir(linkTarget)
writeFile(outside, "outside")
createSymlink(outside, linkTemplate / "outside-link")
discard checked(dp & "template add links --description links --path " &
    quoteShell(linkTemplate))

let blockedLink = run(dp & "template apply links " & quoteShell(linkTarget))
doAssert blockedLink.code != 0
doAssert blockedLink.output.contains("Template contains symlinks")

discard checked(dp & "template apply links " & quoteShell(linkTarget) &
    " --allow-symlinks")
doAssert expandSymlink(linkTarget / "outside-link") == outside

discard checked(dp & "template remove renamed")
discard checked(dp & "template remove other")
discard checked(dp & "template remove links")

let missing = run(dp & "template info renamed")
doAssert missing.code != 0
