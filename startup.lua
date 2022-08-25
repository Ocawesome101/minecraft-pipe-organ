local c = require("cc.shell.completion")

shell.setCompletionFunction("play.lua", c.build(c.file))
