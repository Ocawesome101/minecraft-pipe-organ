-- more barebones music player
-- might perform better
-- these defaults are for my local copy of v3 - they may differ for others

settings.define("organ.first_integrator", {
  description = "The ID of the first Redstone Integrator of the organ.",
  default = 63,
  type = "number"
})

settings.define("organ.side1", {
  descripton = "The side of the first set of Redstone Integrators to which the organ's whistles are connected.",
  default = "back",
  type = "string"
})

settings.define("organ.side2", {
  descripton = "The side of the second set of Redstone Integrators to which the organ's whistles are connected.",
  default = "right",
  type = "string"
})

settings.define("organ.side3", {
  descripton = "The side of the third set of Redstone Integrators to which the organ's whistles are connected.",
  default = "front",
  type = "string"
})

local lookup = {}
for k, v in pairs({
  ["F#"] = 0,
  G = 1,
  ["G#"] = 2,
  A = 3,
  ["A#"] = 4,
  B = 5,
  C = 6,
  ["C#"] = 7,
  D = 8,
  ["D#"] = 9,
  E = 10,
  F = 11,
  H = 12,
}) do lookup[k] = v; lookup[v] = k end

local sides = {
  [0] = settings.get("organ.side1"),
  settings.get("organ.side2"),
  settings.get("organ.side3"),
}

local integrators = {}

local base = settings.get("organ.first_integrator")
for i=0, 38, 1 do
  integrators[i] = peripheral.wrap("redstoneIntegrator_"..(base+i))
end

local state = {[0]={}, [1]={}, [2]={}}
local empty = {}
local function apply(notelist)
  local co = {}

  for octave = 0, 2 do
    local notes = notelist[octave] or empty
    for note = 0, 12 do
      local noteval = not not notes[note]
      if (not not state[octave][note]) ~= (noteval) then
        state[octave][note] = noteval
        co[#co+1] = coroutine.create(function()
          local index = note + (octave * 13)
          integrators[index].setOutput(sides[octave], noteval)
        end)
      end
    end
  end

  for i=1, #co, 1 do
    coroutine.resume(co[i])
  end
end

local function stop()
  local notes = {}
  for o=0, 2 do
    local O = {}
    notes[o] = O
    for n=0, 12 do
      O[n] = false
    end
  end
  apply(notes)
end

-- potential optimization: split and lookup notes before playing
local sequence = {}

for line in io.lines(arg[1]) do
  local words = {}
  for word in line:gmatch("[^ ]+") do
    words[#words+1] = tonumber(word) or word
  end
  local notes = {[3] = words[1]}

  for i=2, #words do
    local name, oct = words[i]:match("([A-H]#?)(%d?)")
    oct = tonumber(oct)
    notes[oct] = notes[oct] or {}
    notes[oct][lookup[name]] = true
  end

  sequence[#sequence+1] = notes
end

for i=1, #sequence do
  local s = sequence[i]
  apply(s)
  os.sleep(s[3])
end
