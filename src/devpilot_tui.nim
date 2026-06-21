import std/[cmdline, os, osproc, sequtils, streams, strutils]

import illwill

import devpilot

type
  ViewState = object
    section: int
    cursor: int
    scroll: int
    filter: string
    message: string

  CommandResult = object
    code: int
    output: string

proc tuiHelp() =
  echo """
Usage: dp tui [--snapshot] [--command COMMAND]

Options:
  --snapshot         Print a non-interactive dashboard summary
  --command COMMAND  Run a devpilot command through the TUI command runner
  -h, --help         Print help information

Keys:
  Left/Right, h/l, Tab, 1-4   Switch sections
  Up/Down, j/k                Move selection
  PageUp/PageDown             Move faster
  /                           Filter current view
  :                           Command palette; type any normal dp command
  a                           Add shortcut for the current section
  d                           Delete selected item after confirmation
  Enter                       Show selected item details
  r                           Reload data
  ?                           Show this help in the TUI
  q, Esc, Ctrl-C              Quit
"""

proc hasFlag(args: seq[string]; names: openArray[string]): bool =
  for arg in args:
    for name in names:
      if arg == name:
        return true

proc valueAfter(args: seq[string]; names: openArray[string]): string =
  for i, arg in args:
    for name in names:
      if arg == name and i + 1 < args.len:
        return args[i + 1]
      let prefix = name & "="
      if arg.startsWith(prefix):
        return arg[prefix.len .. ^1]

proc fit(value: string; width: int): string =
  if width <= 0:
    return ""
  if value.len <= width:
    return value
  if width <= 1:
    return value[0 ..< width]
  value[0 ..< max(0, width - 1)] & "…"

proc pad(value: string; width: int): string =
  let clipped = fit(value, width)
  clipped & repeat(" ", max(0, width - clipped.len))

proc clampInt(value, low, high: int): int =
  if high < low:
    return low
  if value < low:
    low
  elif value > high:
    high
  else:
    value

proc filteredRows(section: DashboardSection; filter: string): seq[seq[string]] =
  let needle = filter.strip().toLowerAscii()
  if needle.len == 0:
    return section.rows
  for row in section.rows:
    if row.join(" ").toLowerAscii().contains(needle):
      result.add(row)

proc currentSection(data: DashboardData; state: ViewState): DashboardSection =
  data.sections[state.section]

proc sectionRows(data: DashboardData; state: ViewState): seq[seq[string]] =
  if data.sections.len == 0:
    return @[]
  filteredRows(currentSection(data, state), state.filter)

proc selectedRow(data: DashboardData; state: ViewState): seq[string] =
  let rows = sectionRows(data, state)
  if rows.len == 0:
    @[]
  else:
    rows[clampInt(state.cursor, 0, rows.high)]

proc clampState(state: var ViewState; data: DashboardData) =
  if data.sections.len == 0:
    state.section = 0
    state.cursor = 0
    state.scroll = 0
    return
  state.section = clampInt(state.section, 0, data.sections.high)
  let rows = sectionRows(data, state)
  if rows.len == 0:
    state.cursor = 0
    state.scroll = 0
  else:
    state.cursor = clampInt(state.cursor, 0, rows.high)
    state.scroll = clampInt(state.scroll, 0, state.cursor)

proc writeLine(tb: var TerminalBuffer; x, y, width: int; text: string; color = fgWhite) =
  if width <= 0 or y < 0 or y >= tb.height.int or x >= tb.width.int:
    return
  tb.write(max(0, x), y, color, fit(text, min(width, tb.width.int - max(0, x))))

proc clearLine(tb: var TerminalBuffer; y: int) =
  if y >= 0 and y < tb.height.int:
    tb.write(0, y, repeat(" ", tb.width.int))

proc drawHorizontal(tb: var TerminalBuffer; y: int; color = fgBlue) =
  if y >= 0 and y < tb.height.int:
    tb.write(0, y, color, repeat("─", tb.width.int))

proc drawTabs(tb: var TerminalBuffer; data: DashboardData; state: ViewState; y: int) =
  var x = 2
  for i, section in data.sections:
    let active = i == state.section
    let label = if active: "[" & section.title & "]" else: " " & section.title & " "
    tb.write(x, y, if active: fgYellow else: fgWhite, label)
    inc x, label.len + 1

proc drawTable(tb: var TerminalBuffer; section: DashboardSection; state: var ViewState; x, y, width, height: int) =
  if height <= 0:
    return
  let rows = filteredRows(section, state.filter)
  if rows.len == 0:
    let message =
      if state.filter.len == 0: section.empty
      else: "No rows match filter: " & state.filter
    writeLine(tb, x, y, width, message, fgYellow)
    return

  let markerWidth = 2
  let headerWidth = max(8, (width - markerWidth) div max(1, section.headers.len))
  var header = repeat(" ", markerWidth)
  for item in section.headers:
    header.add(pad(item, headerWidth))
    header.add(" ")
  writeLine(tb, x, y, width, header, fgCyan)
  drawHorizontal(tb, y + 1)

  let visible = max(0, height - 2)
  if state.cursor < state.scroll:
    state.scroll = state.cursor
  if state.cursor >= state.scroll + visible:
    state.scroll = max(0, state.cursor - visible + 1)

  for i in 0 ..< min(visible, rows.len - state.scroll):
    let rowIndex = state.scroll + i
    let row = rows[rowIndex]
    var line = if rowIndex == state.cursor: "› " else: "  "
    for cell in row:
      line.add(pad(cell, headerWidth))
      line.add(" ")
    writeLine(tb, x, y + 2 + i, width, line, if rowIndex == state.cursor: fgYellow else: fgWhite)

proc drawDetails(tb: var TerminalBuffer; section: DashboardSection; state: ViewState; x, y, width, height: int) =
  if height <= 0:
    return
  writeLine(tb, x, y, width, "Details", fgCyan)
  drawHorizontal(tb, y + 1)
  let rows = filteredRows(section, state.filter)
  if rows.len == 0:
    writeLine(tb, x, y + 2, width, "Nothing selected.", fgWhite)
    return

  let row = rows[clampInt(state.cursor, 0, rows.high)]
  let limit = min(min(section.headers.len, row.len), max(0, height - 3))
  for i in 0 ..< limit:
    writeLine(tb, x, y + 2 + i, width, section.headers[i] & ": " & row[i], fgWhite)
  writeLine(tb, x, y + height - 1, width, "Enter details · a add · d delete · : command · / filter", fgYellow)

proc drawDashboard(tb: var TerminalBuffer; data: DashboardData; state: var ViewState) =
  tb.clear()
  let width = tb.width.int
  let height = tb.height.int
  clampState(state, data)
  let section = currentSection(data, state)
  let rows = sectionRows(data, state)

  writeLine(tb, 2, 0, width - 4, "devpilot", fgYellow)
  writeLine(tb, 13, 0, width - 15, "Development workflow dashboard", fgWhite)
  drawTabs(tb, data, state, 2)
  drawHorizontal(tb, 3)

  let filterLabel = if state.filter.len == 0: "off" else: state.filter
  writeLine(tb, 2, 4, width - 4, section.title & " · " & $rows.len & " row(s) · filter " & filterLabel, fgWhite)

  let detailHeight = 8
  let tableHeight = max(3, height - detailHeight - 7)
  drawTable(tb, section, state, 2, 6, width - 4, tableHeight)
  drawDetails(tb, section, state, 2, height - detailHeight, width - 4, detailHeight - 2)

  drawHorizontal(tb, height - 2)
  let message = if state.message.len == 0: "q quit · ? help · data " & data.dataDir else: state.message
  writeLine(tb, 2, height - 1, width - 4, message, fgWhite)
  tb.display()

proc drawOverlay(tb: var TerminalBuffer; title: string; lines: seq[string]) =
  let width = tb.width.int
  let height = tb.height.int
  let boxWidth = max(30, min(width - 4, 100))
  let boxHeight = min(height - 4, max(6, lines.len + 4))
  let left = max(0, (width - boxWidth) div 2)
  let top = max(0, (height - boxHeight) div 2)

  for y in top ..< min(height, top + boxHeight):
    clearLine(tb, y)
  writeLine(tb, left, top, boxWidth, "┌" & repeat("─", max(0, boxWidth - 2)) & "┐", fgYellow)
  writeLine(tb, left, top + 1, boxWidth, "│ " & fit(title, max(0, boxWidth - 4)) & repeat(" ", max(0, boxWidth - title.len - 4)) & " │", fgYellow)
  writeLine(tb, left, top + 2, boxWidth, "├" & repeat("─", max(0, boxWidth - 2)) & "┤", fgYellow)
  let bodyRows = max(0, boxHeight - 5)
  for i in 0 ..< bodyRows:
    let text = if i < lines.len: lines[i] else: ""
    writeLine(tb, left, top + 3 + i, boxWidth, "│ " & fit(text, max(0, boxWidth - 4)) & repeat(" ", max(0, boxWidth - text.len - 4)) & " │", fgWhite)
  writeLine(tb, left, top + boxHeight - 2, boxWidth, "├" & repeat("─", max(0, boxWidth - 2)) & "┤", fgYellow)
  writeLine(tb, left, top + boxHeight - 1, boxWidth, "│ press any key" & repeat(" ", max(0, boxWidth - 17)) & "│", fgYellow)
  tb.display()

proc waitOverlay(tb: var TerminalBuffer; title: string; content: string) =
  let lines = if content.len == 0: @["No output."] else: content.splitLines()
  drawOverlay(tb, title, lines)
  discard getKeyWithTimeout(120000)

proc printable(key: Key): string =
  let code = ord(key)
  if code >= 32 and code <= 126:
    $chr(code)
  else:
    ""

proc prompt(tb: var TerminalBuffer; data: DashboardData; state: var ViewState; title, initial: string): tuple[ok: bool, value: string] =
  var value = initial
  while true:
    drawDashboard(tb, data, state)
    drawOverlay(tb, title, @["> " & value, "", "Enter accepts · Esc cancels · Backspace deletes"])
    let key = getKeyWithTimeout(80)
    case key
    of Key.Escape, Key.CtrlC:
      return (false, "")
    of Key.Enter:
      return (true, value.strip())
    of Key.Backspace, Key.CtrlH:
      if value.len > 0:
        value.setLen(value.len - 1)
    else:
      value.add(printable(key))

proc runCliCommand(commandInput: string): CommandResult =
  var command = commandInput.strip()
  if command.startsWith("dp "):
    command = command[3 .. ^1].strip()
  if command.len == 0:
    return CommandResult(code: 1, output: "Empty command")

  var args: seq[string]
  try:
    args = parseCmdLine(command)
  except ValueError as e:
    return CommandResult(code: 1, output: e.msg)

  if args.len == 0:
    return CommandResult(code: 1, output: "Empty command")
  if args[0] in ["tui", "ui", "dashboard"]:
    return CommandResult(code: 1, output: "Nested TUI commands are disabled inside the TUI")
  if args.len >= 2 and args[0] in ["machine", "m", "machines", "host", "hosts"] and args[1] in ["connect", "c", "ssh"]:
    return CommandResult(code: 1, output: "Interactive ssh is disabled inside the TUI; run this from the normal CLI")

  try:
    let process = startProcess(getAppFilename(), args = args, options = {poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let code = process.waitForExit()
    process.close()
    result = CommandResult(code: code, output: output)
  except OSError as e:
    result = CommandResult(code: 1, output: e.msg)

proc infoCommand(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " info " & quoteShell(row[0])
  of "Workspaces":
    "workspace info " & quoteShell(row[0])
  of "Machines":
    "machine info " & quoteShell(row[0])
  of "Templates":
    "template info " & quoteShell(row[0])
  else:
    ""

proc deleteCommand(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " remove " & quoteShell(row[0])
  of "Workspaces":
    "workspace remove " & quoteShell(row[0])
  of "Machines":
    "machine remove " & quoteShell(row[0])
  of "Templates":
    "template remove " & quoteShell(row[0])
  else:
    ""

proc addTemplate(section: DashboardSection): string =
  let cwd = quoteShell(getCurrentDir())
  case section.title
  of "Projects":
    "project add NAME --path " & cwd & " --language LANGUAGE"
  of "Workspaces":
    "workspace add NAME --path " & cwd
  of "Machines":
    "machine add NAME 127.0.0.1:22:local --username " & quoteShell(getEnv("USER", "user"))
  of "Templates":
    "template add NAME --description DESC --path " & cwd
  else:
    ""

proc renderSnapshot(data: DashboardData): string =
  result.add("devpilot tui\n")
  result.add("data: " & data.dataDir & "\n")
  for section in data.sections:
    result.add(section.title & ": " & $section.rows.len & "\n")

proc helpText(): string =
  """
Navigation:
  arrows/hjkl, Tab, 1-4

Actions:
  Enter  show details
  a      prefilled add command
  d      delete selected item
  /      filter rows
  :      run any non-interactive dp command
  r      reload data
  ?      help
  q/Esc  quit
"""

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc runTui*(args: seq[string] = @[]) =
  if hasFlag(args, ["-h", "--help"]):
    tuiHelp()
    return

  let nonInteractiveCommand = valueAfter(args, ["--command", "--exec"])
  if nonInteractiveCommand.len > 0:
    let res = runCliCommand(nonInteractiveCommand)
    stdout.write(res.output)
    quit(res.code)

  var data = loadDashboardData()
  if hasFlag(args, ["--snapshot"]):
    stdout.write(renderSnapshot(data))
    return

  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()
  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  var state = ViewState(section: 0, cursor: 0, scroll: 0)

  while true:
    if tb.width != terminalWidth() or tb.height != terminalHeight():
      tb = newTerminalBuffer(terminalWidth(), terminalHeight())

    drawDashboard(tb, data, state)

    case getKeyWithTimeout(80)
    of Key.None:
      discard
    of Key.Escape, Key.Q, Key.ShiftQ, Key.CtrlC:
      exitProc()
    of Key.QuestionMark:
      waitOverlay(tb, "Help", helpText())
    of Key.R, Key.ShiftR:
      data = loadDashboardData()
      state.message = "reloaded"
      clampState(state, data)
    of Key.Left, Key.H:
      dec state.section
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Right, Key.L, Key.Tab:
      inc state.section
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Up, Key.K:
      dec state.cursor
    of Key.Down, Key.J:
      inc state.cursor
    of Key.PageUp:
      dec state.cursor, 10
    of Key.PageDown:
      inc state.cursor, 10
    of Key.One:
      state.section = 0
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Two:
      state.section = 1
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Three:
      state.section = 2
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Four:
      state.section = 3
      state.cursor = 0
      state.scroll = 0
      state.filter = ""
    of Key.Slash:
      let answer = prompt(tb, data, state, "Filter " & currentSection(data, state).title, state.filter)
      if answer.ok:
        state.filter = answer.value
        state.cursor = 0
        state.scroll = 0
    of Key.Colon:
      let answer = prompt(tb, data, state, "Run devpilot command", "")
      if answer.ok:
        let res = runCliCommand(answer.value)
        data = loadDashboardData()
        state.message = if res.code == 0: "ok: " & answer.value else: "failed: " & answer.value
        waitOverlay(tb, "Command result (" & $res.code & ")", res.output)
    of Key.A, Key.ShiftA:
      let answer = prompt(tb, data, state, "Add " & currentSection(data, state).title, addTemplate(currentSection(data, state)))
      if answer.ok:
        let res = runCliCommand(answer.value)
        data = loadDashboardData()
        state.message = if res.code == 0: "added" else: "add failed"
        waitOverlay(tb, "Add result (" & $res.code & ")", res.output)
    of Key.Enter:
      let row = selectedRow(data, state)
      let command = infoCommand(currentSection(data, state), row)
      if command.len > 0:
        let res = runCliCommand(command)
        waitOverlay(tb, "Details (" & $res.code & ")", res.output)
    of Key.D, Key.ShiftD, Key.Delete:
      let section = currentSection(data, state)
      let row = selectedRow(data, state)
      let command = deleteCommand(section, row)
      if command.len > 0:
        let confirm = prompt(tb, data, state, "Delete " & section.title & " item", "type yes to delete " & row[0])
        if confirm.ok and confirm.value == "yes":
          let res = runCliCommand(command)
          data = loadDashboardData()
          state.message = if res.code == 0: "deleted " & row[0] else: "delete failed"
          waitOverlay(tb, "Delete result (" & $res.code & ")", res.output)
    else:
      discard
    clampState(state, data)
