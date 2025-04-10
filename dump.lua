local midi = require("midi")
local file = assert(io.open(..., "r"))

midi.process(file, function(...)
  print(...)
end)

file:close()
