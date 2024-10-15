local c = require("cc.shell.completion")

shell.setCompletionFunction("play.lua", c.build(
  { c.file, true },
  { c.choice, { "-r", "-stupid-fast" } }
))
