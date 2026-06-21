import std/os

import devpilot
import devpilot_tui

when isMainModule:
  var args = commandLineParams()
  if args.len > 0 and args[0] in ["tui", "ui", "dashboard"]:
    args.delete(0)
    runTui(args)
  else:
    devpilot.main()
