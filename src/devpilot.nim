import std/[net, os, osproc, sequtils, strutils, times]

const
  Version = "0.1.10"
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

  DashboardSection* = object
    title*: string
    empty*: string
    headers*: seq[string]
    rows*: seq[seq[string]]

  DashboardData* = object
    dataDir*: string
    sections*: seq[DashboardSection]

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

proc dataRoot(): string =
  let xdgData = getEnv("XDG_DATA_HOME")
  if xdgData.len > 0:
    result = xdgData / "devpilot"
  else:
    result = getHomeDir() / ".local" / "share" / "devpilot"
  createDir(result)

proc configPath(fileName: string): string =
  dataRoot() / fileName

proc readConfig(path: string): string =
  if fileExists(path): readFile(path) else: ""

proc ensureFile(path, defaultContent: string) =
  createDir(parentDir(path))
  if (not fileExists(path)) or getFileSize(path) == 0:
    writeFile(path, defaultContent)

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

proc popValue(args: var seq[string]; names: openArray[string]; defaultValue = ""): string =
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
        result[currentMachine].hosts.add(Host(ip: "", port: "22", iface: "local"))
        currentHost = result[currentMachine].hosts.high
    elif line.contains("=") and currentMachine >= 0:
      let (key, value) = splitKeyValue(line)
      if currentHost >= 0 and key in ["ip", "port", "iface"]:
        case key
        of "ip": result[currentMachine].hosts[currentHost].ip = unquoteToml(value)
        of "port": result[currentMachine].hosts[currentHost].port = unquoteToml(value)
        of "iface": result[currentMachine].hosts[currentHost].iface = unquoteToml(value)
        else: discard
      else:
        case key
        of "name": result[currentMachine].name = unquoteToml(value)
        of "username": result[currentMachine].username = unquoteToml(value)
        of "key": result[currentMachine].key = unquoteToml(value)
        else: discard

proc writeMachines(path: string; machines: seq[Machine]) =
  var text = ""
  if machines.len == 0:
    text = "machines = []\n"
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
  writeFile(path, text)

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
      result.add(Project(namespace: "default", tags: @[], createdAt: stamp, updatedAt: stamp))
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
  var text = ""
  if projects.len == 0:
    text = "projects = []\n"
  else:
    for project in projects:
      text.add("[[projects]]\n")
      text.add("name = " & tomlString(project.name) & "\n")
      text.add("path = " & tomlString(project.path) & "\n")
      text.add("namespace = " & tomlString(project.namespace) & "\n")
      if project.templateName.len > 0: text.add("template = " & tomlString(project.templateName) & "\n")
      if project.description.len > 0: text.add("description = " & tomlString(project.description) & "\n")
      if project.language.len > 0: text.add("language = " & tomlString(project.language) & "\n")
      if project.framework.len > 0: text.add("framework = " & tomlString(project.framework) & "\n")
      text.add("tags = " & tomlArray(project.tags) & "\n")
      text.add("created_at = " & tomlString(project.createdAt) & "\n")
      text.add("updated_at = " & tomlString(project.updatedAt) & "\n\n")
  writeFile(path, text)

proc ensureProjectsFile(): string =
  result = configPath("projects.toml")
  ensureFile(result, "projects = []\n")

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
      result.add(Workspace(components: @[], projects: @[], createdAt: stamp, updatedAt: stamp))
      currentWorkspace = result.high
      currentComponent = -1
    elif line == "[[workspaces.components]]":
      if currentWorkspace >= 0:
        result[currentWorkspace].components.add(Component(componentType: "project"))
        currentComponent = result[currentWorkspace].components.high
    elif line.contains("=") and currentWorkspace >= 0:
      let (key, value) = splitKeyValue(line)
      if currentComponent >= 0 and key in ["name", "component_type", "componentType", "path"]:
        case key
        of "name": result[currentWorkspace].components[currentComponent].name = unquoteToml(value)
        of "component_type", "componentType": result[currentWorkspace].components[currentComponent].componentType = unquoteToml(value)
        of "path": result[currentWorkspace].components[currentComponent].path = unquoteToml(value)
        else: discard
      else:
        case key
        of "name": result[currentWorkspace].name = unquoteToml(value)
        of "path": result[currentWorkspace].path = unquoteToml(value)
        of "description": result[currentWorkspace].description = unquoteToml(value)
        of "projects": result[currentWorkspace].projects = parseStringArray(value)
        of "created_at", "createdAt": result[currentWorkspace].createdAt = unquoteToml(value)
        of "updated_at", "updatedAt": result[currentWorkspace].updatedAt = unquoteToml(value)
        else: discard

proc writeWorkspaces(path: string; workspaces: seq[Workspace]) =
  var text = ""
  if workspaces.len == 0:
    text = "workspaces = []\n"
  else:
    for workspace in workspaces:
      text.add("[[workspaces]]\n")
      text.add("name = " & tomlString(workspace.name) & "\n")
      text.add("path = " & tomlString(workspace.path) & "\n")
      if workspace.description.len > 0: text.add("description = " & tomlString(workspace.description) & "\n")
      text.add("projects = " & tomlArray(workspace.projects) & "\n")
      text.add("created_at = " & tomlString(workspace.createdAt) & "\n")
      text.add("updated_at = " & tomlString(workspace.updatedAt) & "\n")
      for component in workspace.components:
        text.add("\n[[workspaces.components]]\n")
        text.add("name = " & tomlString(component.name) & "\n")
        text.add("component_type = " & tomlString(component.componentType) & "\n")
        if component.path.len > 0: text.add("path = " & tomlString(component.path) & "\n")
      text.add("\n")
  writeFile(path, text)

proc ensureWorkspacesFile(): string =
  result = configPath("workspaces.toml")
  ensureFile(result, "workspaces = []\n")

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
  var text = ""
  if templates.len == 0:
    text = "templates = []\n"
  else:
    for tmpl in templates:
      text.add("[[templates]]\n")
      text.add("name = " & tomlString(tmpl.name) & "\n")
      text.add("description = " & tomlString(tmpl.description) & "\n")
      text.add("path = " & tomlString(tmpl.path) & "\n")
      if tmpl.language.len > 0: text.add("language = " & tomlString(tmpl.language) & "\n")
      if tmpl.framework.len > 0: text.add("framework = " & tomlString(tmpl.framework) & "\n")
      text.add("tags = " & tomlArray(tmpl.tags) & "\n")
      text.add("created_at = " & tomlString(tmpl.createdAt) & "\n")
      text.add("updated_at = " & tomlString(tmpl.updatedAt) & "\n\n")
  writeFile(path, text)

proc ensureTemplatesFile(): string =
  result = configPath("templates.toml")
  ensureFile(result, "templates = []\n")

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
  echo """
Usage:  dp <COMMAND>

Commands:
  workspace  [w]    Workspace related commands
  project    [p]    Project and code creation
  machine    [m]    Add or edit hostnames and ssh
  template   [t]    Project template management
  tui         [ui]   Full-screen terminal dashboard

Options:
      --about       About the tool
  -h, --help        Print help information
  -V, --version     Print version information
"""

proc showProjectHelp() =
  echo """
Usage: dp project [--namespace NAMESPACE] <COMMAND>

Commands:
  add NAME [options]
  list [--raw]
  info NAME
  remove NAME
"""

proc showWorkspaceHelp() =
  echo """
Usage: dp workspace <COMMAND>

Commands:
  add NAME [options]
  list [--raw]
  info NAME
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
  apply TEMPLATE TARGET_PATH [--name PROJECT_NAME]
  remove NAME
"""

proc showMachineHelp() =
  echo """
Usage: dp machine <COMMAND>

Commands:
  add NAME IP[:PORT][:IFACE]... [--username USER] [--key KEY]
  list [--raw]
  info NAME
  pick
  connect NAME [--interface IFACE] [--command COMMAND]
  remove NAME
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
    echo "Project '" & name & "' added successfully to namespace '" & namespace & "'"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    rejectUnknownOptions(args)
    let filtered = projects.filterIt(it.namespace == namespace)
    if raw:
      for project in filtered:
        echo project.name & "\t" & project.namespace & "\t" & project.path & "\t" & unknownIfEmpty(project.language)
    else:
      echo table(
        @["Name", "Path", "Namespace", "Template", "Language", "Framework", "Tags", "Created"],
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
        echo "Tags: " & (if project.tags.len == 0: "None" else: project.tags.join(", "))
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
        echo workspace.name & "\t" & workspace.path & "\t" & workspace.projects.join(",")
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
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp workspace info NAME")
    let name = args[0]
    for workspace in workspaces:
      if workspace.name == name:
        echo "Workspace: " & workspace.name
        echo "Path: " & workspace.path
        echo "Description: " & noneIfEmpty(workspace.description)
        echo "Projects: " & (if workspace.projects.len == 0: "None" else: workspace.projects.join(", "))
        echo "Components:"
        if workspace.components.len == 0:
          echo "  None"
        else:
          for component in workspace.components:
            echo "  " & component.name & ": " & component.componentType & " (" & noneIfEmpty(component.path).replace("None", "no path") & ")"
        echo "Created: " & displayStamp(workspace.createdAt)
        echo "Updated: " & displayStamp(workspace.updatedAt)
        return
    die("Workspace '" & name & "' not found")
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
      workspaces[idx].components.add(Component(name: componentName, componentType: componentType, path: componentPath))
      workspaces[idx].updatedAt = nowStamp()
      writeWorkspaces(path, workspaces)
      echo "Component '" & componentName & "' added to workspace '" & workspaceName & "'"
    of "remove":
      requireArgs(args, 1, "dp workspace component WORKSPACE remove COMPONENT")
      let componentName = args[0]
      let before = workspaces[idx].components.len
      workspaces[idx].components = workspaces[idx].components.filterIt(it.name != componentName)
      if workspaces[idx].components.len == before:
        die("Component '" & componentName & "' not found in workspace '" & workspaceName & "'")
      workspaces[idx].updatedAt = nowStamp()
      writeWorkspaces(path, workspaces)
      echo "Component '" & componentName & "' removed from workspace '" & workspaceName & "'"
    of "list":
      echo "Components in workspace '" & workspaceName & "':"
      for component in workspaces[idx].components:
        echo "  - " & component.name & ": " & component.componentType & " (" & noneIfEmpty(component.path).replace("None", "no path") & ")"
    else:
      die("Unknown workspace component action: " & action, 2)
  else:
    die("Unknown workspace command: " & command, 2)

proc copyDirRecursive(src, dst: string) =
  createDir(dst)
  for kind, path in walkDir(src):
    let target = dst / splitPath(path).tail
    case kind
    of pcFile, pcLinkToFile:
      copyFile(path, target)
    of pcDir:
      copyDirRecursive(path, target)
    else:
      discard

proc replacePlaceholders(targetDir, projectName: string) =
  let kebab = projectName.replace("_", "-")
  let kebabLower = kebab.toLowerAscii()
  let replacements = [
    ("{{PROJECT_NAME}}", projectName),
    ("{{project_name}}", projectName),
    ("{{PROJECT-NAME}}", kebab),
    ("{{project-name}}", kebabLower)
  ]
  for kind, path in walkDir(targetDir):
    case kind
    of pcFile:
      try:
        var content = readFile(path)
        let original = content
        for pair in replacements:
          content = content.replace(pair[0], pair[1])
        if content != original:
          writeFile(path, content)
      except CatchableError:
        discard
    of pcDir:
      replacePlaceholders(path, projectName)
    else:
      discard

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
    rejectUnknownOptions(args)
    if raw:
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
  of "apply", "use", "create":
    let projectName = popValue(args, ["-n", "--name"])
    rejectUnknownOptions(args)
    requireArgs(args, 2, "dp template apply TEMPLATE TARGET_PATH [--name PROJECT_NAME]")
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
    createDir(targetPath)
    if dirExists(found.path):
      copyDirRecursive(found.path, targetPath)
    elif fileExists(found.path):
      copyFile(found.path, targetPath / splitPath(found.path).tail)
    else:
      die("Template path '" & found.path & "' does not exist")
    if projectName.len > 0:
      replacePlaceholders(targetPath, projectName)
    echo "Template '" & templateName & "' successfully applied to '" & targetPath & "'"
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

proc interfaceExists(iface: string): bool =
  iface == "local" or not dirExists("/sys/class/net") or dirExists("/sys/class/net" / iface)

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
          die("Error: Machine with name " & name & " and interface " & host.iface & " already exists")
      machines[idx].hosts.add(hosts)
      machines[idx].username = username
      machines[idx].key = key
    else:
      machines.add(Machine(name: name, username: username, key: key, hosts: hosts))
    writeMachines(path, machines)
    echo "Machine '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    discard popFlag(args, ["-H", "--hosty"])
    rejectUnknownOptions(args)
    if raw:
      for machine in machines:
        for host in machine.hosts:
          echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" & host.port & "\t" & host.iface
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
  of "pick", "p", "select":
    rejectUnknownOptions(args)
    for machine in machines:
      for host in machine.hosts:
        echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" & host.port & "\t" & host.iface
  of "connect", "c", "ssh":
    let iface = popValue(args, ["-i", "--interface"])
    let remoteCommand = popValue(args, ["-c", "--command"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "dp machine connect NAME [--interface IFACE] [--command COMMAND]")
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
    var cmd = "ssh"
    if machine.key.len > 0:
      cmd.add(" -i " & quoteShell(machine.key))
    cmd.add(" " & quoteShell(machine.username & "@" & host.ip))
    if host.port != "22":
      cmd.add(" -p " & quoteShell(host.port))
    if remoteCommand.len > 0:
      cmd.add(" " & quoteShell(remoteCommand))
    echo "Connecting to " & name & " via " & host.iface & "..."
    let status = execCmd(cmd)
    if status != 0:
      quit(status)
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
  else:
    die("Unknown command: " & command, 2)

when isMainModule:
  main()
