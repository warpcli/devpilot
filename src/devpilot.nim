import std/[net, os, osproc, sequtils, streams, strutils, terminal, times]

import devpilot_embedded_templates
import devpilot_storage

const
  Version = "0.2.1"
  About = "ultimate tool for managing development workflows"

type
  Host = object
    ip: string
    port: string
    iface: string

  Machine = object
    name: string
    username: string
    key: string
    hosts: seq[Host]

  Project = object
    name: string
    path: string
    namespace: string
    templateName: string
    description: string
    language: string
    framework: string
    tags: seq[string]
    createdAt: string
    updatedAt: string

  Component = object
    name: string
    componentType: string
    path: string

  Workspace = object
    name: string
    path: string
    description: string
    components: seq[Component]
    projects: seq[string]
    createdAt: string
    updatedAt: string

  Template = object
    name: string
    description: string
    path: string
    language: string
    framework: string
    tags: seq[string]
    createdAt: string
    updatedAt: string

  BuiltinTemplate = object
    name: string
    description: string
    dir: string
    language: string
    framework: string
    tags: string
    nixPackages: string

  DashboardSection* = object
    title*: string
    empty*: string
    headers*: seq[string]
    rows*: seq[seq[string]]

  DashboardData* = object
    dataDir*: string
    sections*: seq[DashboardSection]

const
  GoNixPackages = "            pkgs.go\n" &
      "            pkgs.gopls\n" &
      "            pkgs.gotools\n" &
      "            pkgs.go-tools\n" &
      "            pkgs.delve\n" &
      "            pkgs.golangci-lint\n" &
      "            pkgs.goreleaser"

  ZigNixPackages = "            pkgs.zig\n" &
      "            pkgs.zls"

  NimNixPackages = "            pkgs.nim\n" &
      "            pkgs.nimble\n" &
      "            pkgs.nimlsp\n" &
      "            pkgs.nimlangserver"

  RustNixPackages = "            pkgs.rustc\n" &
      "            pkgs.cargo\n" &
      "            pkgs.rustfmt\n" &
      "            pkgs.clippy\n" &
      "            pkgs.rust-analyzer"

  CppNixPackages = "            pkgs.cmake\n" &
      "            pkgs.gcc\n" &
      "            pkgs.gdb\n" &
      "            pkgs.clang-tools"

  BuiltinTemplates: array[5, BuiltinTemplate] = [
    BuiltinTemplate(
      name: "go",
      description: "Go CLI app with Makefile, flake.nix, tests, and release hooks",
      dir: "go",
      language: "go",
      framework: "cli",
      tags: "builtin,go,cli",
      nixPackages: GoNixPackages
    ),
    BuiltinTemplate(
      name: "zig",
      description: "Zig CLI app with build.zig, Makefile, flake.nix, and release hooks",
      dir: "zig",
      language: "zig",
      framework: "cli",
      tags: "builtin,zig,cli",
      nixPackages: ZigNixPackages
    ),
    BuiltinTemplate(
      name: "nim",
      description: "Nim CLI app with nimble, Makefile, flake.nix, tests, and release hooks",
      dir: "nim",
      language: "nim",
      framework: "cli",
      tags: "builtin,nim,cli",
      nixPackages: NimNixPackages
    ),
    BuiltinTemplate(
      name: "rust",
      description: "Rust library starter with Cargo, Makefile, flake.nix, tests, and release hooks",
      dir: "rust",
      language: "rust",
      framework: "library",
      tags: "builtin,rust,library",
      nixPackages: RustNixPackages
    ),
    BuiltinTemplate(
      name: "cpp",
      description: "C++ library starter with CMake, Makefile, flake.nix, tests, and release hooks",
      dir: "cpp",
      language: "cpp",
      framework: "library",
      tags: "builtin,cpp,library",
      nixPackages: CppNixPackages
    )
  ]

proc die(message: string; code = 1) =
  stderr.writeLine(message)
  quit(code)

proc nowStamp(): string =
  getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc displayStamp(value: string): string =
  if value.len == 0:
    "unknown"
  else:
    value.replace("T", " ").replace("Z", " UTC")

proc dateOnly(value: string): string =
  if value.len >= 10: value[0 .. 9] else: value

proc noneIfEmpty(value: string): string =
  if value.len == 0: "None" else: value

proc unknownIfEmpty(value: string): string =
  if value.len == 0: "unknown" else: value

proc colorHelp(): bool =
  if getEnv("FORCE_COLOR").len > 0:
    return true
  if getEnv("NO_COLOR").len > 0 or getEnv("TERM") == "dumb":
    return false
  isatty(stdout)

proc paint(value, code: string): string =
  if colorHelp(): "\e[" & code & "m" & value & "\e[0m" else: value

proc helpLine(name, alias, description, code: string): string =
  let label =
    if alias.len > 0: name & " [" & alias & "]"
    else: name
  "  " & paint(label & repeat(" ", max(1, 18 - label.len)), code) &
      paint(description, "37")

proc tomlEscape(value: string): string =
  value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n")

proc tomlString(value: string): string =
  "\"" & tomlEscape(value) & "\""

proc unquoteToml(value: string): string =
  var v = value.strip()
  if v.len >= 2 and v[0] == '"' and v[^1] == '"':
    if v.len == 2:
      return ""
    v = v.substr(1, v.len - 2)
    return v
      .replace("\\n", "\n")
      .replace("\\\"", "\"")
      .replace("\\\\", "\\")
  v

proc splitTomlArrayItems(value: string): seq[string] =
  var current = ""
  var quoted = false
  var escaped = false
  for ch in value:
    if escaped:
      current.add(ch)
      escaped = false
    elif ch == '\\':
      current.add(ch)
      escaped = true
    elif ch == '"':
      current.add(ch)
      quoted = not quoted
    elif ch == ',' and not quoted:
      result.add(current.strip())
      current = ""
    else:
      current.add(ch)
  if current.strip().len > 0:
    result.add(current.strip())

proc parseStringArray(value: string): seq[string] =
  let v = value.strip()
  if not (v.startsWith("[") and v.endsWith("]")):
    return @[]
  let inner =
    if v.len <= 2: ""
    else: v.substr(1, v.len - 2).strip()
  if inner.len == 0:
    return @[]
  for item in splitTomlArrayItems(inner):
    result.add(unquoteToml(item))

proc tomlArray(values: seq[string]): string =
  "[" & values.mapIt(tomlString(it)).join(", ") & "]"

proc splitKeyValue(line: string): tuple[key, value: string] =
  let idx = line.find('=')
  if idx < 0:
    return ("", "")
  (line[0 ..< idx].strip(), line[idx + 1 .. ^1].strip())

proc table(headers: seq[string]; rows: seq[seq[string]]): string =
  var widths = newSeq[int](headers.len)
  for i, header in headers:
    widths[i] = header.len
  for row in rows:
    for i, cell in row:
      if i < widths.len:
        widths[i] = max(widths[i], cell.len)

  proc renderRow(row: seq[string]): string =
    var cells: seq[string] = @[]
    for i in 0 ..< widths.len:
      let cell = if i < row.len: row[i] else: ""
      cells.add(cell & repeat(" ", widths[i] - cell.len))
    " " & cells.join("  ") & " "

  proc renderRule(): string =
    var cells: seq[string] = @[]
    for width in widths:
      cells.add(repeat("-", width))
    " " & cells.join("  ") & " "

  result.add(renderRow(headers))
  result.add("\n")
  result.add(renderRule())
  for row in rows:
    result.add("\n")
    result.add(renderRow(row))

proc popFlag(args: var seq[string]; names: openArray[string]): bool =
  var i = 0
  while i < args.len:
    for name in names:
      if args[i] == name:
        args.delete(i)
        return true
    inc i

proc popValue(args: var seq[string]; names: openArray[string];
    defaultValue = ""): string =
  var i = 0
  while i < args.len:
    for name in names:
      if args[i] == name:
        if i + 1 >= args.len:
          die("Missing value for " & name, 2)
        result = args[i + 1]
        args.delete(i + 1)
        args.delete(i)
        return
      let prefix = name & "="
      if args[i].startsWith(prefix):
        result = args[i][prefix.len .. ^1]
        args.delete(i)
        return
    inc i
  defaultValue

proc popValues(args: var seq[string]; names: openArray[string]): seq[string] =
  while true:
    let before = args.len
    let value = popValue(args, names, "")
    if args.len == before:
      break
    result.add(value)

proc requireArgs(args: seq[string]; count: int; usage: string) =
  if args.len < count:
    die("Usage: " & usage, 2)

proc rejectUnknownOptions(args: seq[string]) =
  for arg in args:
    if arg.startsWith("-"):
      die("Unknown option: " & arg, 2)

proc parseMachines(path: string): seq[Machine] =
  let content = readConfig(path)
  var currentMachine = -1
  var currentHost = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[machines]]":
      result.add(Machine(name: "", username: "", key: "", hosts: @[]))
      currentMachine = result.high
      currentHost = -1
    elif line == "[[machines.hosts]]":
      if currentMachine >= 0:
        result[currentMachine].hosts.add(Host(ip: "", port: "22",
            iface: "local"))
        currentHost = result[currentMachine].hosts.high
    elif line.contains("=") and currentMachine >= 0:
      let (key, value) = splitKeyValue(line)
      if currentHost >= 0 and key in ["ip", "port", "iface"]:
        case key
        of "ip": result[currentMachine].hosts[currentHost].ip = unquoteToml(value)
        of "port": result[currentMachine].hosts[currentHost].port = unquoteToml(value)
        of "iface": result[currentMachine].hosts[
            currentHost].iface = unquoteToml(value)
        else: discard
      else:
        case key
        of "name": result[currentMachine].name = unquoteToml(value)
        of "username": result[currentMachine].username = unquoteToml(value)
        of "key": result[currentMachine].key = unquoteToml(value)
        else: discard

proc writeMachines(path: string; machines: seq[Machine]) =
  var text = schemaHeader()
  if machines.len == 0:
    text.add("machines = []\n")
  else:
    for machine in machines:
      text.add("[[machines]]\n")
      text.add("name = " & tomlString(machine.name) & "\n")
      text.add("username = " & tomlString(machine.username) & "\n")
      if machine.key.len > 0:
        text.add("key = " & tomlString(machine.key) & "\n")
      for host in machine.hosts:
        text.add("\n[[machines.hosts]]\n")
        text.add("ip = " & tomlString(host.ip) & "\n")
        text.add("port = " & tomlString(host.port) & "\n")
        text.add("iface = " & tomlString(host.iface) & "\n")
      text.add("\n")
  atomicWriteFile(path, text)

proc defaultMachine(): Machine =
  let hostName = getEnv("HOSTNAME", "localhost")
  let userName = getEnv("USER", "root")
  Machine(
    name: hostName,
    username: userName,
    key: "",
    hosts: @[Host(ip: "127.0.0.1", port: "22", iface: "local")]
  )

proc ensureMachinesFile(): string =
  result = configPath("machines.toml")
  if (not fileExists(result)) or getFileSize(result) == 0:
    writeMachines(result, @[defaultMachine()])

proc parseProjects(path: string): seq[Project] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[projects]]":
      let stamp = nowStamp()
      result.add(Project(namespace: "default", tags: @[], createdAt: stamp,
          updatedAt: stamp))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "path": result[current].path = unquoteToml(value)
      of "namespace": result[current].namespace = unquoteToml(value)
      of "template", "templateName": result[current].templateName = unquoteToml(value)
      of "description": result[current].description = unquoteToml(value)
      of "language": result[current].language = unquoteToml(value)
      of "framework": result[current].framework = unquoteToml(value)
      of "tags": result[current].tags = parseStringArray(value)
      of "created_at", "createdAt": result[current].createdAt = unquoteToml(value)
      of "updated_at", "updatedAt": result[current].updatedAt = unquoteToml(value)
      else: discard

proc writeProjects(path: string; projects: seq[Project]) =
  var text = schemaHeader()
  if projects.len == 0:
    text.add("projects = []\n")
  else:
    for project in projects:
      text.add("[[projects]]\n")
      text.add("name = " & tomlString(project.name) & "\n")
      text.add("path = " & tomlString(project.path) & "\n")
      text.add("namespace = " & tomlString(project.namespace) & "\n")
      if project.templateName.len > 0: text.add("template = " & tomlString(
          project.templateName) & "\n")
      if project.description.len > 0: text.add("description = " & tomlString(
          project.description) & "\n")
      if project.language.len > 0: text.add("language = " & tomlString(
          project.language) & "\n")
      if project.framework.len > 0: text.add("framework = " & tomlString(
          project.framework) & "\n")
      text.add("tags = " & tomlArray(project.tags) & "\n")
      text.add("created_at = " & tomlString(project.createdAt) & "\n")
      text.add("updated_at = " & tomlString(project.updatedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureProjectsFile(): string =
  result = configPath("projects.toml")
  ensureFile(result, schemaHeader() & "projects = []\n")

proc parseWorkspaces(path: string): seq[Workspace] =
  let content = readConfig(path)
  var currentWorkspace = -1
  var currentComponent = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[workspaces]]":
      let stamp = nowStamp()
      result.add(Workspace(components: @[], projects: @[], createdAt: stamp,
          updatedAt: stamp))
      currentWorkspace = result.high
      currentComponent = -1
    elif line == "[[workspaces.components]]":
      if currentWorkspace >= 0:
        result[currentWorkspace].components.add(Component(
            componentType: "project"))
        currentComponent = result[currentWorkspace].components.high
    elif line.contains("=") and currentWorkspace >= 0:
      let (key, value) = splitKeyValue(line)
      if currentComponent >= 0 and key in ["name", "component_type",
          "componentType", "path"]:
        case key
        of "name": result[currentWorkspace].components[
            currentComponent].name = unquoteToml(value)
        of "component_type", "componentType": result[
            currentWorkspace].components[
            currentComponent].componentType = unquoteToml(value)
        of "path": result[currentWorkspace].components[
            currentComponent].path = unquoteToml(value)
        else: discard
      else:
        case key
        of "name": result[currentWorkspace].name = unquoteToml(value)
        of "path": result[currentWorkspace].path = unquoteToml(value)
        of "description": result[currentWorkspace].description = unquoteToml(value)
        of "projects": result[currentWorkspace].projects = parseStringArray(value)
        of "created_at", "createdAt": result[
            currentWorkspace].createdAt = unquoteToml(value)
        of "updated_at", "updatedAt": result[
            currentWorkspace].updatedAt = unquoteToml(value)
        else: discard

proc writeWorkspaces(path: string; workspaces: seq[Workspace]) =
  var text = schemaHeader()
  if workspaces.len == 0:
    text.add("workspaces = []\n")
  else:
    for workspace in workspaces:
      text.add("[[workspaces]]\n")
      text.add("name = " & tomlString(workspace.name) & "\n")
      text.add("path = " & tomlString(workspace.path) & "\n")
      if workspace.description.len > 0: text.add("description = " & tomlString(
          workspace.description) & "\n")
      text.add("projects = " & tomlArray(workspace.projects) & "\n")
      text.add("created_at = " & tomlString(workspace.createdAt) & "\n")
      text.add("updated_at = " & tomlString(workspace.updatedAt) & "\n")
      for component in workspace.components:
        text.add("\n[[workspaces.components]]\n")
        text.add("name = " & tomlString(component.name) & "\n")
        text.add("component_type = " & tomlString(component.componentType) & "\n")
        if component.path.len > 0: text.add("path = " & tomlString(
            component.path) & "\n")
      text.add("\n")
  atomicWriteFile(path, text)

proc ensureWorkspacesFile(): string =
  result = configPath("workspaces.toml")
  ensureFile(result, schemaHeader() & "workspaces = []\n")

type
  WorkspaceEntry = object
    kind: string
    name: string
    path: string

  DetectedProject = object
    name: string
    path: string
    language: string
    framework: string

proc workspaceEntries(workspace: Workspace; projects: seq[Project]): seq[
    WorkspaceEntry] =
  for projectName in workspace.projects:
    var projectPath = ""
    for project in projects:
      if project.name == projectName:
        projectPath = project.path
        break
    result.add(WorkspaceEntry(kind: "project", name: projectName,
        path: projectPath))
  for component in workspace.components:
    result.add(WorkspaceEntry(kind: component.componentType,
        name: component.name, path: component.path))

proc findWorkspace(workspaces: seq[Workspace]; name: string): int =
  result = -1
  for i, workspace in workspaces:
    if workspace.name == name:
      return i

proc findFirstExe(candidates: openArray[string]): string =
  for candidate in candidates:
    let found = findExe(candidate)
    if found.len > 0:
      return found

proc prefixedOutput(prefix, output: string) =
  for line in output.splitLines():
    if line.len > 0:
      echo "[" & prefix & "] " & line

proc runProcessInDir(commandParts: seq[string]; cwd: string): tuple[
    output: string; code: int] =
  if commandParts.len == 0:
    return ("", 2)
  try:
    let processArgs =
      if commandParts.len > 1: commandParts[1 .. ^1]
      else: @[]
    let process = startProcess(commandParts[0], workingDir = cwd,
        args = processArgs, options = {poUsePath, poStdErrToStdOut})
    result.output = process.outputStream.readAll()
    result.code = process.waitForExit()
    process.close()
  except CatchableError as e:
    result.output = e.msg
    result.code = 1

proc gitStatusForPath(path: string): tuple[exists, git, branch,
    status: string] =
  if path.len == 0 or not dirExists(path):
    return ("missing", "no", "-", "missing")
  let inside = execCmdEx("git -C " & quoteShell(path) &
      " rev-parse --is-inside-work-tree")
  if inside.exitCode != 0 or inside.output.strip() != "true":
    return ("yes", "no", "-", "non-git")
  var branch = execCmdEx("git -C " & quoteShell(path) &
      " branch --show-current").output.strip()
  if branch.len == 0:
    branch = execCmdEx("git -C " & quoteShell(path) &
        " rev-parse --short HEAD").output.strip()
  if branch.len == 0:
    branch = "-"
  let dirty = execCmdEx("git -C " & quoteShell(path) &
      " status --porcelain").output.strip()
  ("yes", "yes", branch, if dirty.len == 0: "clean" else: "dirty")

proc jsonString(value: string): string =
  "\"" & value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n") & "\""

proc hasNimbleFile(path: string): bool =
  for kind, item in walkDir(path):
    if kind == pcFile and item.endsWith(".nimble"):
      return true

proc detectProject(path: string): tuple[found: bool; project: DetectedProject] =
  var language = ""
  var hints: seq[string] = @[]

  if dirExists(path / ".git") or fileExists(path / ".git"):
    hints.add("git")
  if fileExists(path / "go.mod"):
    language = "Go"
    hints.add("go modules")
  if fileExists(path / "Cargo.toml"):
    if language.len == 0:
      language = "Rust"
    hints.add("cargo")
  if hasNimbleFile(path):
    if language.len == 0:
      language = "Nim"
    hints.add("nimble")
  if fileExists(path / "pyproject.toml") or fileExists(path / "setup.py"):
    if language.len == 0:
      language = "Python"
    hints.add("python")
  if fileExists(path / "package.json"):
    if language.len == 0:
      language = "Node"
    hints.add("npm")
  if fileExists(path / "build.zig"):
    if language.len == 0:
      language = "Zig"
    hints.add("zig")

  if hints.len == 0:
    return (false, DetectedProject())

  let normalized = normalizedPath(path)
  (true, DetectedProject(
    name: splitPath(normalized).tail,
    path: normalized,
    language: language,
    framework: hints.join(", ")
  ))

proc ignoredDiscoveryDir(path: string): bool =
  splitPath(path).tail in [".git", "node_modules", "target", "nimcache",
      ".direnv", "vendor", "result"]

proc discoverProjects(root: string; maxDepth: int): seq[DetectedProject] =
  var foundProjects: seq[DetectedProject] = @[]

  proc scan(path: string; depth: int) =
    if depth > maxDepth or (depth > 0 and ignoredDiscoveryDir(path)):
      return
    let detected = detectProject(path)
    if detected.found:
      foundProjects.add(detected.project)
    if depth == maxDepth:
      return
    for kind, child in walkDir(path):
      if kind == pcDir:
        scan(child, depth + 1)

  if not dirExists(root):
    die("Discovery path '" & root & "' does not exist")
  scan(root, 0)
  result = foundProjects

proc printDiscovered(projects: seq[DetectedProject]; asJson: bool) =
  if asJson:
    echo "["
    for i, project in projects:
      let suffix = if i == projects.high: "" else: ","
      echo "  {\"name\": " & jsonString(project.name) & ", \"path\": " &
          jsonString(project.path) & ", \"language\": " &
          jsonString(project.language) & ", \"framework\": " &
          jsonString(project.framework) & "}" & suffix
    echo "]"
  elif projects.len == 0:
    echo "No projects discovered"
  else:
    echo table(
      @["Name", "Path", "Language", "Framework"],
      projects.mapIt(@[
        it.name,
        it.path,
        noneIfEmpty(it.language),
        noneIfEmpty(it.framework)
      ])
    )

proc jsonStringArray(values: seq[string]): string =
  result = "["
  for i, value in values:
    if i > 0:
      result.add(", ")
    result.add(jsonString(value))
  result.add("]")

proc projectJson(project: Project): string =
  "{\"name\": " & jsonString(project.name) & ", \"path\": " &
      jsonString(project.path) & ", \"namespace\": " &
      jsonString(project.namespace) & ", \"template\": " &
      jsonString(project.templateName) & ", \"description\": " &
      jsonString(project.description) & ", \"language\": " &
      jsonString(project.language) & ", \"framework\": " &
      jsonString(project.framework) & ", \"tags\": " & jsonStringArray(
          project.tags) &
      ", \"created_at\": " & jsonString(project.createdAt) &
          ", \"updated_at\": " &
      jsonString(project.updatedAt) & "}"

proc componentJson(component: Component): string =
  "{\"name\": " & jsonString(component.name) & ", \"type\": " &
      jsonString(component.componentType) & ", \"path\": " &
      jsonString(component.path) & "}"

proc workspaceJson(workspace: Workspace): string =
  var components = "["
  for i, component in workspace.components:
    if i > 0:
      components.add(", ")
    components.add(componentJson(component))
  components.add("]")
  "{\"name\": " & jsonString(workspace.name) & ", \"path\": " &
      jsonString(workspace.path) & ", \"description\": " &
      jsonString(workspace.description) & ", \"projects\": " &
      jsonStringArray(workspace.projects) & ", \"components\": " & components &
      ", \"created_at\": " & jsonString(workspace.createdAt) &
      ", \"updated_at\": " & jsonString(workspace.updatedAt) & "}"

proc hostJson(host: Host): string =
  "{\"ip\": " & jsonString(host.ip) & ", \"port\": " & jsonString(host.port) &
      ", \"iface\": " & jsonString(host.iface) & "}"

proc machineJson(machine: Machine): string =
  var hosts = "["
  for i, host in machine.hosts:
    if i > 0:
      hosts.add(", ")
    hosts.add(hostJson(host))
  hosts.add("]")
  "{\"name\": " & jsonString(machine.name) & ", \"username\": " &
      jsonString(machine.username) & ", \"key\": " & jsonString(machine.key) &
      ", \"hosts\": " & hosts & "}"

proc templateJson(tmpl: Template): string =
  "{\"name\": " & jsonString(tmpl.name) & ", \"description\": " &
      jsonString(tmpl.description) & ", \"path\": " & jsonString(tmpl.path) &
      ", \"language\": " & jsonString(tmpl.language) & ", \"framework\": " &
      jsonString(tmpl.framework) & ", \"tags\": " & jsonStringArray(tmpl.tags) &
      ", \"created_at\": " & jsonString(tmpl.createdAt) & ", \"updated_at\": " &
      jsonString(tmpl.updatedAt) & "}"

proc printJsonArray[T](items: seq[T]; render: proc(item: T): string) =
  echo "["
  for i, item in items:
    let suffix = if i == items.high: "" else: ","
    echo "  " & render(item) & suffix
  echo "]"

proc parseTemplates(path: string): seq[Template] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[templates]]":
      let stamp = nowStamp()
      result.add(Template(tags: @[], createdAt: stamp, updatedAt: stamp))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "description": result[current].description = unquoteToml(value)
      of "path": result[current].path = unquoteToml(value)
      of "language": result[current].language = unquoteToml(value)
      of "framework": result[current].framework = unquoteToml(value)
      of "tags": result[current].tags = parseStringArray(value)
      of "created_at", "createdAt": result[current].createdAt = unquoteToml(value)
      of "updated_at", "updatedAt": result[current].updatedAt = unquoteToml(value)
      else: discard

proc writeTemplates(path: string; templates: seq[Template]) =
  var text = schemaHeader()
  if templates.len == 0:
    text.add("templates = []\n")
  else:
    for tmpl in templates:
      text.add("[[templates]]\n")
      text.add("name = " & tomlString(tmpl.name) & "\n")
      text.add("description = " & tomlString(tmpl.description) & "\n")
      text.add("path = " & tomlString(tmpl.path) & "\n")
      if tmpl.language.len > 0: text.add("language = " & tomlString(
          tmpl.language) & "\n")
      if tmpl.framework.len > 0: text.add("framework = " & tomlString(
          tmpl.framework) & "\n")
      text.add("tags = " & tomlArray(tmpl.tags) & "\n")
      text.add("created_at = " & tomlString(tmpl.createdAt) & "\n")
      text.add("updated_at = " & tomlString(tmpl.updatedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureTemplatesFile(): string =
  result = configPath("templates.toml")
  ensureFile(result, schemaHeader() & "templates = []\n")

proc embeddedTemplatesRoot(): string =
  dataRoot() / "templates"

proc writeEmbeddedTemplateSources(root: string; force: bool): tuple[
    written: int; skipped: int] =
  for item in EmbeddedTemplateFiles:
    let destination = root / item.group / item.path
    if fileExists(destination) and not force:
      inc result.skipped
    else:
      atomicWriteFile(destination, item.content)
      inc result.written

proc ensureEmbeddedTemplateSources(force = false): tuple[root: string;
    written: int; skipped: int] =
  result.root = embeddedTemplatesRoot()
  let counts = writeEmbeddedTemplateSources(result.root, force)
  result.written = counts.written
  result.skipped = counts.skipped

proc builtinLanguageTitle(tmpl: BuiltinTemplate): string =
  if tmpl.language.len == 0:
    return ""
  tmpl.language[0].toUpperAscii() & tmpl.language.substr(1)

proc renderBuiltinTemplate(content: string; tmpl: BuiltinTemplate): string =
  content
    .replace("{{builtin_language}}", tmpl.language)
    .replace("{{builtin_language_title}}", builtinLanguageTitle(tmpl))
    .replace("{{builtin_nix_packages}}", tmpl.nixPackages)

proc builtinTemplateTags(tmpl: BuiltinTemplate): seq[string] =
  result = @[]
  for tag in tmpl.tags.split(","):
    let cleaned = tag.strip()
    if cleaned.len > 0:
      result.add(cleaned)

proc builtinTemplatesRoot(): string =
  let fromEnv = getEnv("DEVPILOT_TEMPLATE_DIR")
  if fromEnv.len > 0 and dirExists(fromEnv):
    return fromEnv

  let appDir = parentDir(getAppFilename())
  let embeddedRoot = embeddedTemplatesRoot()
  let candidates = @[
    embeddedRoot,
    getCurrentDir() / "templates",
    appDir / "templates",
    appDir / ".." / "share" / "devpilot" / "templates"
  ]
  for candidate in candidates:
    if dirExists(candidate):
      return candidate
  ""

proc builtinTemplatePath(root: string; tmpl: BuiltinTemplate): string =
  root / tmpl.dir

proc builtinCommonPath(root: string): string =
  root / "common"

proc builtinTemplateAvailable(root: string; tmpl: BuiltinTemplate): bool =
  root.len > 0 and dirExists(builtinCommonPath(root)) and dirExists(
      builtinTemplatePath(root, tmpl))

proc copyBuiltinTemplateDir(srcRoot, dstRoot, relRoot: string;
    tmpl: BuiltinTemplate) =
  for kind, path in walkDir(srcRoot):
    let rel = if relRoot.len == 0: splitPath(path).tail else: relRoot /
        splitPath(path).tail
    let dstPath = dstRoot / rel
    case kind
    of pcDir:
      createDir(dstPath)
      copyBuiltinTemplateDir(path, dstRoot, rel, tmpl)
    of pcFile:
      createDir(parentDir(dstPath))
      writeFile(dstPath, renderBuiltinTemplate(readFile(path), tmpl))
    of pcLinkToFile, pcLinkToDir:
      discard

proc materializeBuiltinTemplate(root: string; tmpl: BuiltinTemplate): string =
  let commonPath = builtinCommonPath(root)
  let overlayPath = builtinTemplatePath(root, tmpl)
  if not dirExists(commonPath):
    die("Bundled template common path '" & commonPath & "' does not exist", 2)
  if not dirExists(overlayPath):
    die("Bundled template path '" & overlayPath & "' does not exist", 2)

  result = dataRoot() / "builtin-templates" / tmpl.name
  if dirExists(result):
    removeDir(result)
  createDir(result)
  copyBuiltinTemplateDir(commonPath, result, "", tmpl)
  copyBuiltinTemplateDir(overlayPath, result, "", tmpl)

proc printBuiltinTemplates(root: string; raw, asJson: bool) =
  if asJson:
    echo "["
    for i, tmpl in BuiltinTemplates:
      let path = if root.len > 0: builtinTemplatePath(root, tmpl) else: ""
      let suffix = if i == BuiltinTemplates.high: "" else: ","
      echo "  {\"name\": " & jsonString(tmpl.name) &
          ", \"description\": " & jsonString(tmpl.description) &
          ", \"path\": " & jsonString(path) &
          ", \"language\": " & jsonString(tmpl.language) &
          ", \"framework\": " & jsonString(tmpl.framework) &
          ", \"available\": " & (if builtinTemplateAvailable(root,
              tmpl): "true" else: "false") &
          "}" & suffix
    echo "]"
  elif raw:
    for tmpl in BuiltinTemplates:
      let path = if root.len > 0: builtinTemplatePath(root, tmpl) else: ""
      echo tmpl.name & "\t" & tmpl.language & "\t" & path
  else:
    echo table(
      @["Name", "Description", "Language", "Path", "Status"],
      BuiltinTemplates.mapIt(@[
        it.name,
        it.description,
        it.language,
        if root.len > 0: builtinTemplatePath(root, it) else: "None",
        if builtinTemplateAvailable(root, it): "ready" else: "missing"
      ])
    )

proc installBuiltinTemplates(path: string; templates: var seq[Template];
    force: bool; sourceRoot = "") =
  if sourceRoot.len == 0 and getEnv("DEVPILOT_TEMPLATE_DIR").len == 0:
    discard ensureEmbeddedTemplateSources(false)
  let root = if sourceRoot.len > 0: sourceRoot else: builtinTemplatesRoot()
  if root.len == 0:
    die("Bundled templates not found. Set DEVPILOT_TEMPLATE_DIR or run dp init", 2)

  var added = 0
  var updated = 0
  var skipped = 0
  templates = templates.filterIt(not @["go-cli", "zig-cli", "nim-cli"].contains(
      it.name))
  for builtin in BuiltinTemplates:
    let templatePath = materializeBuiltinTemplate(root, builtin)

    var found = -1
    for i, tmpl in templates:
      if tmpl.name == builtin.name:
        found = i
        break

    let stamp = nowStamp()
    let record = Template(
      name: builtin.name,
      description: builtin.description,
      path: templatePath,
      language: builtin.language,
      framework: builtin.framework,
      tags: builtinTemplateTags(builtin),
      createdAt: stamp,
      updatedAt: stamp
    )
    if found >= 0:
      if force:
        templates[found].description = record.description
        templates[found].path = record.path
        templates[found].language = record.language
        templates[found].framework = record.framework
        templates[found].tags = record.tags
        templates[found].updatedAt = stamp
        inc updated
      else:
        inc skipped
    else:
      templates.add(record)
      inc added

  writeTemplates(path, templates)
  echo "Bundled templates installed: " & $added & " added, " & $updated &
      " updated, " & $skipped & " skipped"

proc loadDashboardData*(): DashboardData =
  let projectPath = ensureProjectsFile()
  let workspacePath = ensureWorkspacesFile()
  let machinePath = ensureMachinesFile()
  let templatePath = ensureTemplatesFile()

  let projects = parseProjects(projectPath)
  let workspaces = parseWorkspaces(workspacePath)
  let machines = parseMachines(machinePath)
  let templates = parseTemplates(templatePath)

  var machineRows: seq[seq[string]] = @[]
  for machine in machines:
    machineRows.add(@[
      machine.name,
      machine.username,
      machine.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(", "),
      noneIfEmpty(machine.key)
    ])

  result = DashboardData(
    dataDir: dataRoot(),
    sections: @[
      DashboardSection(
        title: "Projects",
        empty: "No projects yet. Add one with: dp project add NAME --path PATH",
        headers: @["Name", "Namespace", "Path", "Language"],
        rows: projects.mapIt(@[
          it.name,
          it.namespace,
          it.path,
          noneIfEmpty(it.language)
    ])
  ),
      DashboardSection(
        title: "Workspaces",
        empty: "No workspaces yet. Add one with: dp workspace add NAME --path PATH",
        headers: @["Name", "Path", "Projects", "Components"],
        rows: workspaces.mapIt(@[
          it.name,
          it.path,
          if it.projects.len == 0: "None" else: it.projects.join(", "),
          $it.components.len
    ])
  ),
      DashboardSection(
        title: "Machines",
        empty: "No machines yet. Add one with: dp machine add NAME IP[:PORT][:IFACE]",
        headers: @["Name", "User", "Hosts", "Key"],
        rows: machineRows
    ),
    DashboardSection(
      title: "Templates",
      empty: "No templates yet. Add one with: dp template add NAME --description DESC --path PATH",
      headers: @["Name", "Description", "Path", "Language"],
      rows: templates.mapIt(@[
        it.name,
        it.description,
        it.path,
        noneIfEmpty(it.language)
      ])
    )
  ]
  )

proc showHelp() =
  echo paint("devpilot", "1;35") & paint(" — development workflow dashboard", "2")
  echo ""
  echo paint("Usage:", "1;36") & "  " & paint("dp", "1;32") & " " &
      paint("<COMMAND>", "33")
  echo ""
  echo paint("Main commands:", "1;36")
  echo helpLine("workspace", "w", "Workspace related commands", "1;32")
  echo helpLine("project", "p", "Project and code creation", "1;32")
  echo helpLine("machine", "m", "Add or edit hostnames and ssh", "1;32")
  echo helpLine("template", "t", "Project template management", "1;32")
  echo ""
  echo paint("Other commands:", "1;36")
  echo helpLine("init", "", "Initialize devpilot data and embedded templates",
      "1;34")
  echo helpLine("data", "", "Backup, restore, export, and import devpilot data",
      "1;34")
  echo helpLine("completions", "", "Generate shell completions", "1;34")
  echo helpLine("tui", "ui", "Full-screen terminal dashboard", "1;34")
  echo ""
  echo paint("Options:", "1;36")
  echo "  " & paint("--about", "33") & repeat(" ", 13) & "About the tool"
  echo "  " & paint("-h, --help", "33") & repeat(" ", 9) &
      "Print help information"
  echo "  " & paint("-V, --version", "33") & repeat(" ", 6) &
      "Print version information"
  echo ""
  echo paint("Tip:", "1;35") & " run " & paint("dp", "1;32") &
      " with no arguments to open the TUI."

proc showProjectHelp() =
  echo """
Usage: dp project [--namespace NAMESPACE] <COMMAND>

Commands:
  add NAME [options]
  discover PATH [--depth N] [--json]
  import PATH [--namespace NAMESPACE] [--dry-run]
  list [--raw]
  info NAME
  set NAME [options]
  rename OLD NEW
  tag add NAME TAG
  tag remove NAME TAG
  remove NAME
"""

proc showWorkspaceHelp() =
  echo """
Usage: dp workspace <COMMAND>

Commands:
  add NAME [options]
  list [--raw]
  info NAME
  set NAME [options]
  rename OLD NEW
  project add WORKSPACE PROJECT
  project remove WORKSPACE PROJECT
  discover NAME PATH
  remove NAME
  component WORKSPACE [add|remove|list] [COMPONENT] [options]
"""

proc showTemplateHelp() =
  echo """
Usage: dp template <COMMAND>

Commands:
  add NAME --description DESC --path PATH [options]
  list [--raw]
  info NAME
  set NAME [options]
  rename OLD NEW
  tag add NAME TAG
  tag remove NAME TAG
  apply TEMPLATE TARGET_PATH [--name PROJECT_NAME] [--dry-run] [--force|--skip-existing] [--allow-symlinks]
  builtins [list|install] [--force]
  remove NAME
"""

proc showMachineHelp() =
  echo """
Usage: dp machine <COMMAND>

Commands:
  add NAME IP[:PORT][:IFACE]... [--username USER] [--key KEY]
  list [--raw]
  info NAME
  set NAME [--username USER] [--key KEY]
  rename OLD NEW
  host add NAME IP[:PORT][:IFACE]...
  host remove NAME IFACE
  ssh-config [NAME]
  check NAME [--timeout MS]
  check --all [--timeout MS]
  pick
  connect NAME [--interface IFACE] [--command COMMAND] [--dry-run]
  remove NAME
"""

proc showBackupHelp() =
  echo """
Usage: dp data backup <COMMAND>

Commands:
  create [--path PATH]
  restore PATH [--force]
"""

proc showDataHelp() =
  echo """
Usage: dp data <COMMAND>

Commands:
  backup create [--path PATH]
  backup restore PATH [--force]
  export [--format toml|json] [--path PATH]
  import PATH [--merge|--force]
"""

proc handleProject(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showProjectHelp()
    return
  let namespace = popValue(args, ["-n", "--namespace"], "default")
  requireArgs(args, 1, "dp project [--namespace NAMESPACE] <add|list|info>")
  let command = args[0]
  args.delete(0)
  let path = ensureProjectsFile()
  var projects = parseProjects(path)

  case command
  of "add", "a", "new", "create":
    let projectPath = popValue(args, ["-p", "--path"], getCurrentDir())
    let templateName = popValue(args, ["-t", "--template"])
    let description = popValue(args, ["-d", "--description"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let tags = popValues(args, ["--tags"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project add NAME [options]")
    let name = args[0]
    if projects.anyIt(it.name == name and it.namespace == namespace):
      die("Project '" & name & "' already exists in namespace '" & namespace & "'")
    let stamp = nowStamp()
    projects.add(Project(
      name: name,
      path: projectPath,
      namespace: namespace,
      templateName: templateName,
      description: description,
      language: language,
      framework: framework,
      tags: tags,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeProjects(path, projects)
    echo "Project '" & name & "' added successfully to namespace '" &
        namespace & "'"
  of "discover", "scan":
    let depthValue = popValue(args, ["--depth"], "3")
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project discover PATH [--depth N] [--json]")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
    printDiscovered(discoverProjects(args[0], depth), asJson)
  of "import":
    let dryRun = popFlag(args, ["--dry-run"])
    let depthValue = popValue(args, ["--depth"], "3")
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project import PATH [--namespace NAMESPACE] [--dry-run]")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
    let discovered = discoverProjects(args[0], depth)
    if discovered.len == 0:
      echo "No projects discovered"
      return
    var imported = 0
    var skipped = 0
    let stamp = nowStamp()
    for item in discovered:
      if projects.anyIt(it.name == item.name and it.namespace == namespace):
        echo "Skipped duplicate: " & item.name
        inc skipped
      elif dryRun:
        echo "Would import: " & item.name & " -> " & item.path
        inc imported
      else:
        projects.add(Project(
          name: item.name,
          path: item.path,
          namespace: namespace,
          language: item.language,
          framework: item.framework,
          tags: @[],
          createdAt: stamp,
          updatedAt: stamp
        ))
        echo "Imported: " & item.name
        inc imported
    if not dryRun and imported > 0:
      writeProjects(path, projects)
    echo "Import summary: " & $imported & " imported, " & $skipped & " skipped"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    let filtered = projects.filterIt(it.namespace == namespace)
    if asJson:
      printJsonArray(filtered, projectJson)
    elif raw:
      for project in filtered:
        echo project.name & "\t" & project.namespace & "\t" & project.path &
            "\t" & unknownIfEmpty(project.language)
    else:
      echo table(
        @["Name", "Path", "Namespace", "Template", "Language", "Framework",
            "Tags", "Created"],
        filtered.mapIt(@[
          it.name,
          it.path,
          it.namespace,
          noneIfEmpty(it.templateName),
          noneIfEmpty(it.language),
          noneIfEmpty(it.framework),
          if it.tags.len == 0: "None" else: it.tags.join(", "),
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project info NAME")
    let name = args[0]
    for project in projects:
      if project.name == name and project.namespace == namespace:
        echo "Project: " & project.name
        echo "Path: " & project.path
        echo "Namespace: " & project.namespace
        echo "Template: " & noneIfEmpty(project.templateName)
        echo "Description: " & noneIfEmpty(project.description)
        echo "Language: " & noneIfEmpty(project.language)
        echo "Framework: " & noneIfEmpty(project.framework)
        echo "Tags: " & (if project.tags.len ==
            0: "None" else: project.tags.join(", "))
        echo "Created: " & displayStamp(project.createdAt)
        echo "Updated: " & displayStamp(project.updatedAt)
        return
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project remove NAME")
    let name = args[0]
    let before = projects.len
    projects = projects.filterIt(not (it.name == name and it.namespace == namespace))
    if projects.len == before:
      die("Project '" & name & "' not found in namespace '" & namespace & "'")
    writeProjects(path, projects)
    echo "Project '" & name & "' removed from namespace '" & namespace & "'"
  of "set", "update", "edit":
    let projectPath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let description = popValue(args, ["-d", "--description"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp project set NAME [options]")
    if projectPath.len == 0 and language.len == 0 and framework.len == 0 and
        description.len == 0:
      die("No project fields were provided", 2)
    let name = args[0]
    for i in 0 .. projects.high:
      if projects[i].name == name and projects[i].namespace == namespace:
        if projectPath.len > 0:
          projects[i].path = projectPath
        if language.len > 0:
          projects[i].language = language
        if framework.len > 0:
          projects[i].framework = framework
        if description.len > 0:
          projects[i].description = description
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & name & "' updated in namespace '" & namespace & "'"
        return
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp project rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if projects.anyIt(it.name == newName and it.namespace == namespace):
      die("Project '" & newName & "' already exists in namespace '" &
          namespace & "'")
    for i in 0 .. projects.high:
      if projects[i].name == oldName and projects[i].namespace == namespace:
        projects[i].name = newName
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & oldName & "' renamed to '" & newName &
            "' in namespace '" & namespace & "'"
        return
    die("Project '" & oldName & "' not found in namespace '" & namespace & "'")
  of "tag", "tags":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "dp project tag add|remove NAME TAG")
    let action = args[0]
    let name = args[1]
    let tag = args[2]
    for i in 0 .. projects.high:
      if projects[i].name == name and projects[i].namespace == namespace:
        case action
        of "add":
          if not projects[i].tags.contains(tag):
            projects[i].tags.add(tag)
        of "remove", "rm":
          projects[i].tags = projects[i].tags.filterIt(it != tag)
        else:
          die("Unknown project tag action: " & action, 2)
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & name & "' tags updated in namespace '" & namespace & "'"
        return
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  else:
    die("Unknown project command: " & command, 2)

proc handleWorkspace(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showWorkspaceHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureWorkspacesFile()
  var workspaces = parseWorkspaces(path)

  case command
  of "add", "a", "new", "create":
    let workspacePath = popValue(args, ["-p", "--path"], getCurrentDir())
    let description = popValue(args, ["-d", "--description"])
    let projects = popValues(args, ["--projects"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace add NAME [options]")
    let name = args[0]
    if workspaces.anyIt(it.name == name):
      die("Workspace '" & name & "' already exists")
    let stamp = nowStamp()
    workspaces.add(Workspace(
      name: name,
      path: workspacePath,
      description: description,
      components: @[],
      projects: projects,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeWorkspaces(path, workspaces)
    echo "Workspace '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    rejectUnknownOptions(args)
    if raw:
      for workspace in workspaces:
        echo workspace.name & "\t" & workspace.path & "\t" &
            workspace.projects.join(",")
    else:
      echo table(
        @["Name", "Path", "Description", "Projects", "Components", "Created"],
        workspaces.mapIt(@[
          it.name,
          it.path,
          noneIfEmpty(it.description),
          if it.projects.len == 0: "None" else: it.projects.join(", "),
          $it.components.len,
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace info NAME")
    let name = args[0]
    for workspace in workspaces:
      if workspace.name == name:
        if asJson:
          echo workspaceJson(workspace)
        else:
          echo "Workspace: " & workspace.name
          echo "Path: " & workspace.path
          echo "Description: " & noneIfEmpty(workspace.description)
          echo "Projects: " & (if workspace.projects.len ==
              0: "None" else: workspace.projects.join(", "))
          echo "Components:"
          if workspace.components.len == 0:
            echo "  None"
          else:
            for component in workspace.components:
              echo "  " & component.name & ": " & component.componentType &
                  " (" & noneIfEmpty(component.path).replace("None",
                      "no path") & ")"
          echo "Created: " & displayStamp(workspace.createdAt)
          echo "Updated: " & displayStamp(workspace.updatedAt)
        return
    die("Workspace '" & name & "' not found")
  of "status", "stat":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace status NAME")
    let name = args[0]
    let idx = findWorkspace(workspaces, name)
    if idx < 0:
      die("Workspace '" & name & "' not found")
    let projects = parseProjects(ensureProjectsFile())
    let entries = workspaceEntries(workspaces[idx], projects)
    echo "Workspace: " & name
    echo ""
    if entries.len == 0:
      echo "No workspace paths configured"
    else:
      echo table(
        @["Type", "Name", "Path", "Exists", "Git", "Branch", "Status"],
        entries.mapIt(block:
          let state = gitStatusForPath(it.path)
          @[
            it.kind,
            it.name,
            if it.path.len == 0: "missing" else: it.path,
            state.exists,
            state.git,
            state.branch,
            state.status
          ]
        )
      )
  of "run":
    let parallel = popFlag(args, ["--parallel"])
    requireArgs(args, 3, "dp workspace run NAME [--parallel] -- COMMAND...")
    let name = args[0]
    if args[1] != "--":
      die("Usage: dp workspace run NAME [--parallel] -- COMMAND...", 2)
    let commandParts = args[2 .. ^1]
    let idx = findWorkspace(workspaces, name)
    if idx < 0:
      die("Workspace '" & name & "' not found")
    let projects = parseProjects(ensureProjectsFile())
    let entries = workspaceEntries(workspaces[idx], projects)
    var failed = false
    if parallel:
      var jobs: seq[tuple[name: string; process: Process]] = @[]
      for entry in entries:
        if entry.path.len == 0 or not dirExists(entry.path):
          echo "[" & entry.name & "] missing path: " & noneIfEmpty(entry.path)
          failed = true
        else:
          try:
            let processArgs =
              if commandParts.len > 1: commandParts[1 .. ^1]
              else: @[]
            let process = startProcess(commandParts[0], workingDir = entry.path,
                args = processArgs, options = {poUsePath, poStdErrToStdOut})
            jobs.add((entry.name, process))
          except CatchableError as e:
            echo "[" & entry.name & "] " & e.msg
            failed = true
      for job in jobs:
        let output = job.process.outputStream.readAll()
        let code = job.process.waitForExit()
        job.process.close()
        prefixedOutput(job.name, output)
        if code != 0:
          failed = true
    else:
      for entry in entries:
        if entry.path.len == 0 or not dirExists(entry.path):
          echo "[" & entry.name & "] missing path: " & noneIfEmpty(entry.path)
          failed = true
          continue
        let runResult = runProcessInDir(commandParts, entry.path)
        prefixedOutput(entry.name, runResult.output)
        if runResult.code != 0:
          failed = true
    if failed:
      quit(1)
  of "open":
    let editorOption = popValue(args, ["--editor"])
    let terminal = popFlag(args, ["--terminal"])
    let dryRun = popFlag(args, ["--dry-run"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace open NAME [--editor EDITOR] [--terminal] [--dry-run]")
    let name = args[0]
    let idx = findWorkspace(workspaces, name)
    if idx < 0:
      die("Workspace '" & name & "' not found")
    let projects = parseProjects(ensureProjectsFile())
    let paths = workspaceEntries(workspaces[idx], projects).mapIt(
        it.path).filterIt(it.len > 0 and dirExists(it))
    if paths.len == 0:
      die("Workspace '" & name & "' has no existing paths")
    if terminal:
      let terminalExe =
        if editorOption.len > 0: editorOption
        elif getEnv("TERMINAL").len > 0: getEnv("TERMINAL")
        else: findFirstExe(["x-terminal-emulator", "alacritty", "kitty",
            "gnome-terminal", "konsole", "xterm"])
      if terminalExe.len == 0:
        die("No terminal found; set TERMINAL or use --editor", 2)
      for itemPath in paths:
        if dryRun:
          echo "Would open terminal in: " & itemPath
        else:
          try:
            discard startProcess(terminalExe, workingDir = itemPath,
                options = {poUsePath})
          except CatchableError as e:
            die("Unable to open workspace terminal: " & e.msg)
    else:
      let editor =
        if editorOption.len > 0: editorOption
        elif getEnv("EDITOR").len > 0: getEnv("EDITOR")
        else: findFirstExe(["code", "nvim", "vim", "vi"])
      if editor.len == 0:
        die("No editor found; set EDITOR or pass --editor", 2)
      if dryRun:
        echo "Would run: " & editor & " " & paths.mapIt(quoteShell(it)).join(" ")
      else:
        try:
          discard startProcess(editor, args = paths, options = {poUsePath})
        except CatchableError as e:
          die("Unable to open workspace editor: " & e.msg)
  of "env":
    let format = popValue(args, ["--format"], "shell")
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace env NAME [--format direnv]")
    let name = args[0]
    let idx = findWorkspace(workspaces, name)
    if idx < 0:
      die("Workspace '" & name & "' not found")
    if format == "direnv":
      echo "# direnv configuration generated by devpilot"
    elif format != "shell":
      die("Unknown workspace env format: " & format, 2)
    echo "export DEVPILOT_WORKSPACE=" & quoteShell(workspaces[idx].name)
    echo "export DEVPILOT_WORKSPACE_ROOT=" & quoteShell(workspaces[idx].path)
  of "discover", "bootstrap":
    let depthValue = popValue(args, ["--depth"], "3")
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp workspace discover NAME PATH [--depth N]")
    let name = args[0]
    let workspaceRoot = args[1]
    if workspaces.anyIt(it.name == name):
      die("Workspace '" & name & "' already exists")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
    let discovered = discoverProjects(workspaceRoot, depth)
    let projectPath = ensureProjectsFile()
    var projects = parseProjects(projectPath)
    let stamp = nowStamp()
    var projectNames: seq[string] = @[]
    for item in discovered:
      projectNames.add(item.name)
      if not projects.anyIt(it.name == item.name and it.namespace == "default"):
        projects.add(Project(
          name: item.name,
          path: item.path,
          namespace: "default",
          language: item.language,
          framework: item.framework,
          tags: @[],
          createdAt: stamp,
          updatedAt: stamp
        ))
    if discovered.len > 0:
      writeProjects(projectPath, projects)
    workspaces.add(Workspace(
      name: name,
      path: workspaceRoot,
      description: "Discovered workspace",
      components: @[],
      projects: projectNames,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeWorkspaces(path, workspaces)
    echo "Workspace '" & name & "' discovered with " & $projectNames.len &
        " projects"
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace remove NAME")
    let name = args[0]
    let before = workspaces.len
    workspaces = workspaces.filterIt(it.name != name)
    if workspaces.len == before:
      die("Workspace '" & name & "' not found")
    writeWorkspaces(path, workspaces)
    echo "Workspace '" & name & "' removed successfully"
  of "set", "update", "edit":
    let workspacePath = popValue(args, ["-p", "--path"])
    let description = popValue(args, ["-d", "--description"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace set NAME [options]")
    if workspacePath.len == 0 and description.len == 0:
      die("No workspace fields were provided", 2)
    let name = args[0]
    for i in 0 .. workspaces.high:
      if workspaces[i].name == name:
        if workspacePath.len > 0:
          workspaces[i].path = workspacePath
        if description.len > 0:
          workspaces[i].description = description
        workspaces[i].updatedAt = nowStamp()
        writeWorkspaces(path, workspaces)
        echo "Workspace '" & name & "' updated successfully"
        return
    die("Workspace '" & name & "' not found")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp workspace rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if workspaces.anyIt(it.name == newName):
      die("Workspace '" & newName & "' already exists")
    for i in 0 .. workspaces.high:
      if workspaces[i].name == oldName:
        workspaces[i].name = newName
        workspaces[i].updatedAt = nowStamp()
        writeWorkspaces(path, workspaces)
        echo "Workspace '" & oldName & "' renamed to '" & newName & "'"
        return
    die("Workspace '" & oldName & "' not found")
  of "project", "projects":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "dp workspace project add|remove WORKSPACE PROJECT")
    let action = args[0]
    let workspaceName = args[1]
    let projectName = args[2]
    for i in 0 .. workspaces.high:
      if workspaces[i].name == workspaceName:
        case action
        of "add":
          if not workspaces[i].projects.contains(projectName):
            workspaces[i].projects.add(projectName)
        of "remove", "rm":
          workspaces[i].projects = workspaces[i].projects.filterIt(it != projectName)
        else:
          die("Unknown workspace project action: " & action, 2)
        workspaces[i].updatedAt = nowStamp()
        writeWorkspaces(path, workspaces)
        echo "Workspace '" & workspaceName & "' projects updated"
        return
    die("Workspace '" & workspaceName & "' not found")
  of "component", "c", "components", "comp":
    let componentType = popValue(args, ["-t", "--type"], "project")
    let componentPath = popValue(args, ["-p", "--path"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace component WORKSPACE [add|remove|list] [COMPONENT]")
    let workspaceName = args[0]
    args.delete(0)
    var idx = -1
    for i, workspace in workspaces:
      if workspace.name == workspaceName:
        idx = i
        break
    if idx < 0:
      die("Workspace '" & workspaceName & "' not found")
    let action =
      if args.len == 0: "list"
      else:
        let value = args[0]
        args.delete(0)
        value
    case action
    of "add":
      requireArgs(args, 1, "dp workspace component WORKSPACE add COMPONENT [options]")
      let componentName = args[0]
      workspaces[idx].components.add(Component(name: componentName,
          componentType: componentType, path: componentPath))
      workspaces[idx].updatedAt = nowStamp()
      writeWorkspaces(path, workspaces)
      echo "Component '" & componentName & "' added to workspace '" &
          workspaceName & "'"
    of "remove":
      requireArgs(args, 1, "dp workspace component WORKSPACE remove COMPONENT")
      let componentName = args[0]
      let before = workspaces[idx].components.len
      workspaces[idx].components = workspaces[idx].components.filterIt(
          it.name != componentName)
      if workspaces[idx].components.len == before:
        die("Component '" & componentName & "' not found in workspace '" &
            workspaceName & "'")
      workspaces[idx].updatedAt = nowStamp()
      writeWorkspaces(path, workspaces)
      echo "Component '" & componentName & "' removed from workspace '" &
          workspaceName & "'"
    of "list":
      echo "Components in workspace '" & workspaceName & "':"
      for component in workspaces[idx].components:
        echo "  - " & component.name & ": " & component.componentType & " (" &
            noneIfEmpty(component.path).replace("None", "no path") & ")"
    else:
      die("Unknown workspace component action: " & action, 2)
  else:
    die("Unknown workspace command: " & command, 2)

type
  TemplateApplyPlan = object
    createDirs: seq[string]
    copyFiles: seq[string]
    symlinks: seq[string]
    replacements: seq[string]
    conflicts: seq[string]
    rejectedSymlinks: seq[string]
    skippedReplacements: seq[string]

proc childRel(parent, child: string): string =
  if parent.len == 0: child else: parent / child

proc hasNul(content: string): bool =
  for ch in content:
    if ch == '\0':
      return true

proc placeholderPairs(projectName: string): seq[(string, string)] =
  let kebab = projectName.replace("_", "-")
  let kebabLower = kebab.toLowerAscii()
  let snake = projectName.replace("-", "_")
  let snakeLower = snake.toLowerAscii()
  @[
    ("{{PROJECT_NAME}}", projectName),
    ("{{project_name}}", projectName),
    ("{{PROJECT-NAME}}", kebab),
    ("{{project-name}}", kebabLower),
    ("{{name}}", projectName),
    ("{{NAME}}", projectName.toUpperAscii()),
    ("{{kebab_name}}", kebabLower),
    ("{{snake_name}}", snakeLower)
  ]

proc inferProjectName(targetPath: string): string =
  var cleaned = targetPath
  while cleaned.len > 1 and (cleaned[^1] == '/' or cleaned[^1] == '\\'):
    cleaned.setLen(cleaned.len - 1)
  let tail = splitPath(cleaned).tail
  if tail.len > 0:
    tail
  else:
    "project"

proc effectiveProjectName(projectName, targetPath: string): string =
  if projectName.len > 0:
    projectName
  else:
    inferProjectName(targetPath)

proc renderTemplateRel(rel, projectName: string): string =
  result = rel
  if projectName.len == 0:
    return
  for pair in placeholderPairs(projectName):
    result = result.replace(pair[0], pair[1])

proc replacementStatus(path, rel, projectName: string): tuple[needed: bool;
    skipped: string] =
  if projectName.len == 0:
    return (false, "")
  try:
    let content = readFile(path)
    if hasNul(content):
      return (false, rel & " (binary)")
    for pair in placeholderPairs(projectName):
      if content.contains(pair[0]):
        return (true, "")
  except CatchableError as e:
    return (false, rel & " (" & e.msg & ")")
  (false, "")

proc addConflictIfNeeded(plan: var TemplateApplyPlan; target, rel: string) =
  if fileExists(target) or dirExists(target):
    plan.conflicts.add(rel)

proc addFileToPlan(plan: var TemplateApplyPlan; srcPath, targetRoot, rel,
    projectName: string) =
  plan.copyFiles.add(rel)
  addConflictIfNeeded(plan, targetRoot / rel, rel)
  let status = replacementStatus(srcPath, rel, projectName)
  if status.needed:
    plan.replacements.add(rel)
  elif status.skipped.len > 0:
    plan.skippedReplacements.add(status.skipped)

proc addSymlinkToPlan(plan: var TemplateApplyPlan; targetRoot, rel: string;
    allowSymlinks: bool) =
  if allowSymlinks:
    plan.symlinks.add(rel)
    addConflictIfNeeded(plan, targetRoot / rel, rel)
  else:
    plan.rejectedSymlinks.add(rel)

proc collectTemplateDir(plan: var TemplateApplyPlan; srcRoot, targetRoot,
    relRoot, projectName: string; allowSymlinks: bool) =
  for kind, path in walkDir(srcRoot):
    let rawRel = childRel(relRoot, splitPath(path).tail)
    let rel = renderTemplateRel(rawRel, projectName)
    case kind
    of pcDir:
      plan.createDirs.add(rel)
      collectTemplateDir(plan, path, targetRoot, rawRel, projectName, allowSymlinks)
    of pcFile:
      addFileToPlan(plan, path, targetRoot, rel, projectName)
    of pcLinkToFile, pcLinkToDir:
      addSymlinkToPlan(plan, targetRoot, rel, allowSymlinks)

proc buildTemplatePlan(srcPath, targetRoot, projectName: string;
    allowSymlinks: bool): TemplateApplyPlan =
  if dirExists(srcPath):
    collectTemplateDir(result, srcPath, targetRoot, "", projectName, allowSymlinks)
  elif fileExists(srcPath):
    addFileToPlan(result, srcPath, targetRoot,
        renderTemplateRel(splitPath(srcPath).tail, projectName), projectName)
  else:
    die("Template path '" & srcPath & "' does not exist")

proc printList(title: string; items: seq[string]) =
  if items.len == 0:
    return
  echo title & ":"
  for item in items:
    echo "  " & item
  echo ""

proc printTemplatePlan(templateName, targetPath: string;
    plan: TemplateApplyPlan) =
  echo "Template: " & templateName
  echo "Target: " & targetPath
  echo ""
  printList("Create directories", plan.createDirs)
  printList("Copy files", plan.copyFiles)
  printList("Create symlinks", plan.symlinks)
  printList("Replace placeholders", plan.replacements)
  printList("Conflicts", plan.conflicts)
  printList("Rejected symlinks", plan.rejectedSymlinks)
  printList("Skipped placeholder replacements", plan.skippedReplacements)

proc replacePlaceholdersInFile(path, rel, projectName: string;
    skipped: var seq[string]) =
  if projectName.len == 0:
    return
  try:
    var content = readFile(path)
    if hasNul(content):
      skipped.add(rel & " (binary)")
      return
    let original = content
    for pair in placeholderPairs(projectName):
      content = content.replace(pair[0], pair[1])
    if content != original:
      writeFile(path, content)
  except CatchableError as e:
    skipped.add(rel & " (" & e.msg & ")")

proc copyTemplateFile(srcPath, targetPath, rel, projectName: string; force,
    skipExisting: bool; skippedReplacements: var seq[string]) =
  if fileExists(targetPath) or dirExists(targetPath):
    if skipExisting:
      return
    if not force:
      die("Template target conflict: " & rel)
  createDir(parentDir(targetPath))
  copyFile(srcPath, targetPath)
  replacePlaceholdersInFile(targetPath, rel, projectName, skippedReplacements)

proc copyTemplateSymlink(srcPath, targetPath, rel: string; force,
    skipExisting: bool) =
  if fileExists(targetPath) or dirExists(targetPath):
    if skipExisting:
      return
    if not force:
      die("Template target conflict: " & rel)
    removeFile(targetPath)
  createDir(parentDir(targetPath))
  createSymlink(expandSymlink(srcPath), targetPath)

proc applyTemplateDir(srcRoot, targetRoot, relRoot, projectName: string; force,
    skipExisting, allowSymlinks: bool; skippedReplacements: var seq[string]) =
  createDir(targetRoot / renderTemplateRel(relRoot, projectName))
  for kind, path in walkDir(srcRoot):
    let rawRel = childRel(relRoot, splitPath(path).tail)
    let rel = renderTemplateRel(rawRel, projectName)
    let target = targetRoot / rel
    case kind
    of pcDir:
      applyTemplateDir(path, targetRoot, rawRel, projectName, force,
          skipExisting, allowSymlinks, skippedReplacements)
    of pcFile:
      copyTemplateFile(path, target, rel, projectName, force, skipExisting,
          skippedReplacements)
    of pcLinkToFile, pcLinkToDir:
      if not allowSymlinks:
        die("Template contains symlink '" & rel & "'; use --allow-symlinks")
      copyTemplateSymlink(path, target, rel, force, skipExisting)

proc applyTemplate(srcPath, targetRoot, projectName: string; force,
    skipExisting, allowSymlinks: bool): seq[string] =
  if dirExists(srcPath):
    applyTemplateDir(srcPath, targetRoot, "", projectName, force, skipExisting,
        allowSymlinks, result)
  elif fileExists(srcPath):
    let rel = renderTemplateRel(splitPath(srcPath).tail, projectName)
    copyTemplateFile(srcPath, targetRoot / rel, rel, projectName, force,
        skipExisting, result)
  else:
    die("Template path '" & srcPath & "' does not exist")

proc handleTemplate(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showTemplateHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureTemplatesFile()
  var templates = parseTemplates(path)

  case command
  of "builtins", "builtin", "defaults":
    let force = popFlag(args, ["--force"])
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    let action =
      if args.len == 0: "list"
      else:
        let value = args[0]
        args.delete(0)
        value
    rejectUnknownOptions(args)
    case action
    of "list", "ls":
      printBuiltinTemplates(builtinTemplatesRoot(), raw, asJson)
    of "install", "add", "seed":
      if raw or asJson:
        die("--raw and --json are only valid with dp template builtins list", 2)
      installBuiltinTemplates(path, templates, force)
    else:
      die("Unknown builtin template action: " & action, 2)
  of "add", "a", "new":
    let description = popValue(args, ["-d", "--description", "--desc"])
    let templatePath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let tags = popValues(args, ["--tags"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp template add NAME --description DESC --path PATH")
    if description.len == 0: die("Template description is required", 2)
    if templatePath.len == 0: die("Template path is required", 2)
    if not (fileExists(templatePath) or dirExists(templatePath)):
      die("Template path '" & templatePath & "' does not exist")
    let name = args[0]
    if templates.anyIt(it.name == name):
      die("Template '" & name & "' already exists")
    let stamp = nowStamp()
    templates.add(Template(
      name: name,
      description: description,
      path: templatePath,
      language: language,
      framework: framework,
      tags: tags,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeTemplates(path, templates)
    echo "Template '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    if asJson:
      printJsonArray(templates, templateJson)
    elif raw:
      for tmpl in templates:
        echo tmpl.name & "\t" & unknownIfEmpty(tmpl.language) & "\t" & tmpl.path
    else:
      echo table(
        @["Name", "Description", "Language", "Framework", "Tags", "Created"],
        templates.mapIt(@[
          it.name,
          it.description,
          noneIfEmpty(it.language),
          noneIfEmpty(it.framework),
          if it.tags.len == 0: "None" else: it.tags.join(", "),
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp template info NAME")
    let name = args[0]
    for tmpl in templates:
      if tmpl.name == name:
        echo "Template: " & tmpl.name
        echo "Description: " & tmpl.description
        echo "Path: " & tmpl.path
        echo "Language: " & noneIfEmpty(tmpl.language)
        echo "Framework: " & noneIfEmpty(tmpl.framework)
        echo "Tags: " & (if tmpl.tags.len == 0: "None" else: tmpl.tags.join(", "))
        echo "Created: " & displayStamp(tmpl.createdAt)
        echo "Updated: " & displayStamp(tmpl.updatedAt)
        return
    die("Template '" & name & "' not found")
  of "set", "update", "edit":
    let description = popValue(args, ["-d", "--description", "--desc"])
    let templatePath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp template set NAME [options]")
    if description.len == 0 and templatePath.len == 0 and language.len == 0 and
        framework.len == 0:
      die("No template fields were provided", 2)
    if templatePath.len > 0 and not (fileExists(templatePath) or dirExists(
        templatePath)):
      die("Template path '" & templatePath & "' does not exist")
    let name = args[0]
    for i in 0 .. templates.high:
      if templates[i].name == name:
        if description.len > 0:
          templates[i].description = description
        if templatePath.len > 0:
          templates[i].path = templatePath
        if language.len > 0:
          templates[i].language = language
        if framework.len > 0:
          templates[i].framework = framework
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & name & "' updated successfully"
        return
    die("Template '" & name & "' not found")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp template rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if templates.anyIt(it.name == newName):
      die("Template '" & newName & "' already exists")
    for i in 0 .. templates.high:
      if templates[i].name == oldName:
        templates[i].name = newName
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & oldName & "' renamed to '" & newName & "'"
        return
    die("Template '" & oldName & "' not found")
  of "tag", "tags":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "dp template tag add|remove NAME TAG")
    let action = args[0]
    let name = args[1]
    let tag = args[2]
    for i in 0 .. templates.high:
      if templates[i].name == name:
        case action
        of "add":
          if not templates[i].tags.contains(tag):
            templates[i].tags.add(tag)
        of "remove", "rm":
          templates[i].tags = templates[i].tags.filterIt(it != tag)
        else:
          die("Unknown template tag action: " & action, 2)
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & name & "' tags updated"
        return
    die("Template '" & name & "' not found")
  of "apply", "use", "create":
    let projectName = popValue(args, ["-n", "--name"])
    let dryRun = popFlag(args, ["--dry-run"])
    let force = popFlag(args, ["--force"])
    let skipExisting = popFlag(args, ["--skip-existing"])
    let allowSymlinks = popFlag(args, ["--allow-symlinks"])
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp template apply TEMPLATE TARGET_PATH [--name PROJECT_NAME]")
    if force and skipExisting:
      die("--force and --skip-existing cannot be used together", 2)
    let templateName = args[0]
    let targetPath = args[1]
    var found: Template
    var hasFound = false
    for tmpl in templates:
      if tmpl.name == templateName:
        found = tmpl
        hasFound = true
        break
    if not hasFound:
      die("Template '" & templateName & "' not found")

    let renderedName = effectiveProjectName(projectName, targetPath)
    let plan = buildTemplatePlan(found.path, targetPath, renderedName, allowSymlinks)
    if dryRun:
      printTemplatePlan(templateName, targetPath, plan)
      if plan.rejectedSymlinks.len > 0:
        die("Template contains symlinks; use --allow-symlinks")
      if plan.conflicts.len > 0 and not (force or skipExisting):
        die("Template target has conflicts; use --force or --skip-existing")
      return
    if plan.rejectedSymlinks.len > 0:
      printTemplatePlan(templateName, targetPath, plan)
      die("Template contains symlinks; use --allow-symlinks")
    if plan.conflicts.len > 0 and not (force or skipExisting):
      printTemplatePlan(templateName, targetPath, plan)
      die("Template target has conflicts; use --force or --skip-existing")

    let skippedReplacements = applyTemplate(found.path, targetPath,
        renderedName, force, skipExisting, allowSymlinks)
    printList("Skipped placeholder replacements", skippedReplacements)
    echo "Template '" & templateName & "' successfully applied to '" &
        targetPath & "'"
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp template remove NAME")
    let name = args[0]
    let before = templates.len
    templates = templates.filterIt(it.name != name)
    if templates.len == before:
      die("Template '" & name & "' not found")
    writeTemplates(path, templates)
    echo "Template '" & name & "' removed successfully"
  else:
    die("Unknown template command: " & command, 2)

proc handleDataBackup(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showBackupHelp()
    return

  let command = args[0]
  args.delete(0)
  case command
  of "create", "new":
    let destination = popValue(args, ["-p", "--path"])
    rejectUnknownOptions(args)
    if args.len > 0:
      die("Usage: dp data backup create [--path PATH]", 2)
    try:
      let backupPath = createBackup(destination)
      echo "Backup created: " & backupPath
    except CatchableError as e:
      die(e.msg)
  of "restore":
    let force = popFlag(args, ["--force"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp data backup restore PATH [--force]")
    try:
      restoreBackup(args[0], force)
      echo "Backup restored from: " & args[0]
    except CatchableError as e:
      die(e.msg)
  else:
    die("Unknown backup command: " & command, 2)

proc interfaceExists(iface: string): bool =
  iface == "local" or not dirExists("/sys/class/net") or dirExists(
      "/sys/class/net" / iface)

proc parseHost(value: string): Host =
  let parts = value.split(":")
  if parts.len == 0 or parts.len > 3:
    die("Invalid host format: " & value, 2)
  try:
    discard parseIpAddress(parts[0])
  except ValueError:
    die("Invalid ip format: " & parts[0], 2)
  result = Host(ip: parts[0], port: "22", iface: "local")
  if parts.len == 2:
    if parts[1].allCharsInSet({'0'..'9'}):
      result.port = parts[1]
    else:
      result.iface = parts[1]
  elif parts.len == 3:
    result.port = parts[1]
    result.iface = parts[2]
  try:
    let portNumber = parseInt(result.port)
    if portNumber < 1 or portNumber > 65535:
      die("Invalid port format: " & result.port, 2)
  except ValueError:
    die("Invalid port format: " & result.port, 2)
  if not interfaceExists(result.iface):
    die("Invalid iface name: " & result.iface, 2)

proc sshArgs(machine: Machine; host: Host; remoteCommand: string): seq[string] =
  if machine.key.len > 0:
    result.add(@["-i", machine.key])
  if host.port != "22":
    result.add(@["-p", host.port])
  result.add(machine.username & "@" & host.ip)
  if remoteCommand.len > 0:
    result.add(remoteCommand)

proc shellDisplay(command: string; args: seq[string]): string =
  result = command
  for arg in args:
    result.add(" " & quoteShell(arg))

proc writeSshConfig(machine: Machine) =
  for host in machine.hosts:
    echo "Host " & machine.name & "-" & host.iface
    echo "  HostName " & host.ip
    echo "  User " & machine.username
    echo "  Port " & host.port
    if machine.key.len > 0:
      echo "  IdentityFile " & machine.key
    echo ""

proc tcpReachable(host: Host; timeoutMs: int): bool =
  var socket = newSocket()
  try:
    socket.connect(host.ip, Port(parseInt(host.port)), timeoutMs)
    result = true
  except CatchableError:
    result = false
  finally:
    socket.close()

proc handleMachine(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showMachineHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureMachinesFile()
  var machines = parseMachines(path)

  case command
  of "add", "a", "new":
    let username = popValue(args, ["-u", "--username"], getEnv("USER", "root"))
    let key = popValue(args, ["-k", "--key"], getHomeDir() / ".ssh" / "id_rsa")
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp machine add NAME IP[:PORT][:IFACE]... [options]")
    let name = args[0]
    args.delete(0)
    let hosts = args.mapIt(parseHost(it))
    var idx = -1
    for i, machine in machines:
      if machine.name == name:
        idx = i
        break
    if idx >= 0:
      for host in hosts:
        if machines[idx].hosts.anyIt(it.iface == host.iface):
          die("Error: Machine with name " & name & " and interface " &
              host.iface & " already exists")
      machines[idx].hosts.add(hosts)
      machines[idx].username = username
      machines[idx].key = key
    else:
      machines.add(Machine(name: name, username: username, key: key, hosts: hosts))
    writeMachines(path, machines)
    echo "Machine '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    discard popFlag(args, ["-H", "--hosty"])
    rejectUnknownOptions(args)
    if asJson:
      printJsonArray(machines, machineJson)
    elif raw:
      for machine in machines:
        for host in machine.hosts:
          echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" &
              host.port & "\t" & host.iface
    else:
      echo table(
        @["Name", "Username", "Hosts", "Key"],
        machines.mapIt(@[
          it.name,
          it.username,
          it.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(", "),
          noneIfEmpty(it.key)
        ])
      )
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp machine info NAME")
    let name = args[0]
    for machine in machines:
      if machine.name == name:
        echo "Machine: " & machine.name
        echo "Username: " & machine.username
        echo "Key: " & noneIfEmpty(machine.key)
        echo "Hosts:"
        if machine.hosts.len == 0:
          echo "  None"
        else:
          for host in machine.hosts:
            echo "  " & host.ip & ":" & host.port & " (" & host.iface & ")"
        return
    die("Machine '" & name & "' not found")
  of "set", "update", "edit":
    let username = popValue(args, ["-u", "--username"])
    let key = popValue(args, ["-k", "--key"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp machine set NAME [--username USER] [--key KEY]")
    if username.len == 0 and key.len == 0:
      die("No machine fields were provided", 2)
    let name = args[0]
    for i in 0 .. machines.high:
      if machines[i].name == name:
        if username.len > 0:
          machines[i].username = username
        if key.len > 0:
          machines[i].key = key
        writeMachines(path, machines)
        echo "Machine '" & name & "' updated successfully"
        return
    die("Machine '" & name & "' not found")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp machine rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if machines.anyIt(it.name == newName):
      die("Machine '" & newName & "' already exists")
    for i in 0 .. machines.high:
      if machines[i].name == oldName:
        machines[i].name = newName
        writeMachines(path, machines)
        echo "Machine '" & oldName & "' renamed to '" & newName & "'"
        return
    die("Machine '" & oldName & "' not found")
  of "host", "hosts":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "dp machine host add|remove NAME HOST_OR_IFACE")
    let action = args[0]
    let name = args[1]
    var idx = -1
    for i, machine in machines:
      if machine.name == name:
        idx = i
        break
    if idx < 0:
      die("Machine '" & name & "' not found")
    case action
    of "add":
      for rawHost in args[2 .. ^1]:
        let host = parseHost(rawHost)
        if machines[idx].hosts.anyIt(it.iface == host.iface):
          die("Error: Machine with name " & name & " and interface " &
              host.iface & " already exists")
        machines[idx].hosts.add(host)
      writeMachines(path, machines)
      echo "Machine '" & name & "' hosts updated"
    of "remove", "rm":
      let iface = args[2]
      let before = machines[idx].hosts.len
      machines[idx].hosts = machines[idx].hosts.filterIt(it.iface != iface)
      if machines[idx].hosts.len == before:
        die("Host interface '" & iface & "' not found on machine '" & name & "'")
      writeMachines(path, machines)
      echo "Machine '" & name & "' hosts updated"
    else:
      die("Unknown machine host action: " & action, 2)
  of "pick", "p", "select":
    rejectUnknownOptions(args)
    for machine in machines:
      for host in machine.hosts:
        echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" &
            host.port & "\t" & host.iface
  of "connect", "c", "ssh":
    let iface = popValue(args, ["-i", "--interface"])
    let remoteCommand = popValue(args, ["-c", "--command"])
    let dryRun = popFlag(args, ["--dry-run", "--print-command"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp machine connect NAME [--interface IFACE] [--command COMMAND] [--dry-run]")
    let name = args[0]
    var machine: Machine
    var hasMachine = false
    for item in machines:
      if item.name == name:
        machine = item
        hasMachine = true
        break
    if not hasMachine:
      die("Machine '" & name & "' not found")
    var host: Host
    var hasHost = false
    for item in machine.hosts:
      if (iface.len == 0 and not hasHost) or item.iface == iface:
        host = item
        hasHost = true
        if iface.len > 0:
          break
    if not hasHost:
      die("No suitable host found for machine '" & name & "'")
    let connectArgs = sshArgs(machine, host, remoteCommand)
    if dryRun:
      echo shellDisplay("ssh", connectArgs)
      return
    echo "Connecting to " & name & " via " & host.iface & "..."
    try:
      let process = startProcess("ssh", args = connectArgs, options = {poUsePath})
      let status = process.waitForExit()
      process.close()
      if status != 0:
        quit(status)
    except CatchableError as e:
      die("Unable to start ssh: " & e.msg)
  of "ssh-config", "config":
    rejectUnknownOptions(args)
    if args.len > 1:
      die("Usage: dp machine ssh-config [NAME]", 2)
    if args.len == 0:
      for machine in machines:
        writeSshConfig(machine)
    else:
      let name = args[0]
      for machine in machines:
        if machine.name == name:
          writeSshConfig(machine)
          return
      die("Machine '" & name & "' not found")
  of "check", "health":
    let all = popFlag(args, ["--all"])
    let timeoutValue = popValue(args, ["--timeout"], "1000")
    rejectUnknownOptions(args)
    var timeoutMs = 1000
    try:
      timeoutMs = parseInt(timeoutValue)
    except ValueError:
      die("Invalid timeout: " & timeoutValue, 2)
    if timeoutMs < 1:
      die("Invalid timeout: " & timeoutValue, 2)
    if not all:
      requireArgs(args, 1, "dp machine check NAME [--timeout MS]")
    var rows: seq[seq[string]] = @[]
    var failed = false
    for machine in machines:
      if all or machine.name == args[0]:
        for host in machine.hosts:
          let ok = tcpReachable(host, timeoutMs)
          if not ok:
            failed = true
          rows.add(@[
            machine.name,
            host.iface,
            host.ip,
            host.port,
            if ok: "reachable" else: "unreachable"
          ])
    if rows.len == 0:
      if all:
        die("No machines found")
      else:
        die("Machine '" & args[0] & "' not found")
    echo table(@["Machine", "Iface", "IP", "Port", "Status"], rows)
    if failed:
      quit(1)
  of "remove", "r", "rm", "delete":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp machine remove NAME")
    let name = args[0]
    let before = machines.len
    machines = machines.filterIt(it.name != name)
    if machines.len == before:
      die("Machine '" & name & "' not found")
    writeMachines(path, machines)
    echo "Machine '" & name & "' removed successfully"
  else:
    die("Unknown machine command: " & command, 2)

proc allDataJson(): string =
  let projects = parseProjects(ensureProjectsFile())
  let workspaces = parseWorkspaces(ensureWorkspacesFile())
  let machines = parseMachines(ensureMachinesFile())
  let templates = parseTemplates(ensureTemplatesFile())

  proc arrayJson[T](items: seq[T]; render: proc(item: T): string): string =
    result = "["
    for i, item in items:
      if i > 0:
        result.add(", ")
      result.add(render(item))
    result.add("]")

  "{\"projects\": " & arrayJson(projects, projectJson) & ", \"workspaces\": " &
      arrayJson(workspaces, workspaceJson) & ", \"machines\": " &
      arrayJson(machines, machineJson) & ", \"templates\": " &
      arrayJson(templates, templateJson) & "}"

proc handleDataExport(argsIn: seq[string]) =
  var args = argsIn
  let format = popValue(args, ["--format"], "toml")
  let destination = popValue(args, ["-p", "--path"])
  rejectUnknownOptions(args)
  if args.len > 0:
    die("Usage: dp data export [--format toml|json] [--path PATH]", 2)
  case format
  of "toml":
    try:
      let backupPath = createBackup(destination)
      echo "Exported TOML data: " & backupPath
    except CatchableError as e:
      die(e.msg)
  of "json":
    let data = allDataJson()
    if destination.len > 0:
      atomicWriteFile(destination, data & "\n")
      echo "Exported JSON data: " & destination
    else:
      echo data
  else:
    die("Unknown export format: " & format, 2)

proc mergeImport(path: string) =
  if not dirExists(path):
    die("Import path does not exist or is not a directory: " & path)

  var projects = parseProjects(ensureProjectsFile())
  for item in parseProjects(path / "projects.toml"):
    if not projects.anyIt(it.name == item.name and it.namespace ==
        item.namespace):
      projects.add(item)
  writeProjects(ensureProjectsFile(), projects)

  var workspaces = parseWorkspaces(ensureWorkspacesFile())
  for item in parseWorkspaces(path / "workspaces.toml"):
    if not workspaces.anyIt(it.name == item.name):
      workspaces.add(item)
  writeWorkspaces(ensureWorkspacesFile(), workspaces)

  var machines = parseMachines(ensureMachinesFile())
  for item in parseMachines(path / "machines.toml"):
    if not machines.anyIt(it.name == item.name):
      machines.add(item)
  writeMachines(ensureMachinesFile(), machines)

  var templates = parseTemplates(ensureTemplatesFile())
  for item in parseTemplates(path / "templates.toml"):
    if not templates.anyIt(it.name == item.name):
      templates.add(item)
  writeTemplates(ensureTemplatesFile(), templates)

proc handleDataImport(argsIn: seq[string]) =
  var args = argsIn
  let force = popFlag(args, ["--force"])
  let merge = popFlag(args, ["--merge"])
  rejectUnknownOptions(args)
  requireArgs(args, 1, "dp data import PATH [--merge|--force]")
  if force and merge:
    die("--force and --merge cannot be used together", 2)
  try:
    if merge:
      mergeImport(args[0])
      echo "Import merged from: " & args[0]
    else:
      restoreBackup(args[0], force)
      echo "Import restored from: " & args[0]
  except CatchableError as e:
    die(e.msg)

proc handleData(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showDataHelp()
    return

  let command = args[0]
  args.delete(0)
  case command
  of "backup", "bk", "backups":
    handleDataBackup(args)
  of "export":
    handleDataExport(args)
  of "import":
    handleDataImport(args)
  else:
    die("Unknown data command: " & command, 2)

proc handleInit(argsIn: seq[string]) =
  var args = argsIn
  let force = popFlag(args, ["--force"])
  rejectUnknownOptions(args)
  if args.len > 0:
    die("Usage: dp init [--force]", 2)

  discard ensureProjectsFile()
  discard ensureWorkspacesFile()
  discard ensureMachinesFile()
  let templatesPath = ensureTemplatesFile()
  let seeded = ensureEmbeddedTemplateSources(force)

  var templates = parseTemplates(templatesPath)
  installBuiltinTemplates(templatesPath, templates, force, seeded.root)

  echo "Initialized devpilot data: " & dataRoot()
  echo "Embedded template sources: " & seeded.root & " (" & $seeded.written &
      " written, " & $seeded.skipped & " skipped)"

proc handleCompletions(argsIn: seq[string]) =
  var args = argsIn
  rejectUnknownOptions(args)
  requireArgs(args, 1, "dp completions bash|zsh|fish")
  let commands = "project workspace machine template init data completions tui help"
  case args[0]
  of "bash":
    echo "complete -W '" & commands & "' dp"
  of "zsh":
    echo "#compdef dp"
    echo "_arguments '1:command:(" & commands & ")'"
  of "fish":
    for command in commands.splitWhitespace():
      echo "complete -c dp -f -a " & command
  else:
    die("Unknown completion shell: " & args[0], 2)

proc commandReferenceMarkdown(): string =
  """
# devpilot command reference

## Main commands

- `dp project ...` — manage projects, discovery, import, JSON listing.
- `dp workspace ...` — manage workspaces and run/status/open/env actions.
- `dp machine ...` — manage SSH hosts, SSH config, health checks.
- `dp template ...` — manage and safely apply project templates.

## Other commands

- `dp init` — initialize local devpilot data and write embedded templates.
- `dp data ...` — backup, restore, export, and import devpilot data.
- `dp completions SHELL` — generate bash, zsh, or fish completions.
- `dp tui` — open the terminal dashboard. Running `dp` with no arguments also opens it.
"""

proc handleHelpCommand(argsIn: seq[string]) =
  var args = argsIn
  let man = popFlag(args, ["--man"])
  let markdown = popFlag(args, ["--markdown"])
  rejectUnknownOptions(args)
  if man:
    echo commandReferenceMarkdown()
  elif markdown:
    echo commandReferenceMarkdown()
  else:
    showHelp()

proc main*() =
  var args = commandLineParams()
  if args.len == 0:
    showHelp()
    return
  if popFlag(args, ["-h", "--help"]):
    showHelp()
    return
  if popFlag(args, ["-V", "--version"]):
    echo Version
    return
  if popFlag(args, ["--about"]):
    echo About
    return
  if args.len > 0 and args[0] == "help":
    args.delete(0)
    handleHelpCommand(args)
    return

  requireArgs(args, 1, "dp <COMMAND>")
  let command = args[0]
  args.delete(0)
  case command
  of "workspace", "w", "workspaces", "ws":
    handleWorkspace(args)
  of "project", "p", "projects", "proj":
    handleProject(args)
  of "machine", "m", "machines", "host", "hosts":
    handleMachine(args)
  of "template", "t", "templates", "temp":
    handleTemplate(args)
  of "init", "initialize":
    handleInit(args)
  of "data", "d":
    handleData(args)
  of "completions", "completion":
    handleCompletions(args)
  else:
    die("Unknown command: " & command, 2)

when isMainModule:
  main()
