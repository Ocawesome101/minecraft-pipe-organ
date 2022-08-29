-- more barebones music player
-- might perform better

-- my LSP likes to complain about undefined globals
local term = rawget(_G, "term")
local epoch = rawget(os, "epoch")
local sleep = rawget(os, "sleep")
local settings = rawget(_G, "settings")
local pullEvent = rawget(os, "pullEvent")
local peripheral = rawget(_G, "peripheral")

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

local played = 0
local state = {[0]={}, [1]={}, [2]={}}
local empty = {}
local function tweak(notelist)
  local co = {}

  for octave = 0, 2 do
    local notes = notelist[octave] or empty
    for note = 0, 12 do
      local noteval = not not notes[note]
      if (not not state[octave][note]) ~= (noteval) then
        state[octave][note] = noteval
        co[#co+1] = coroutine.create(function()
          local index = note + (octave * 13)
          played = played + 1
          integrators[index].setAnalogOutput(sides[octave], noteval and 1 or 0)
        end)
      end
    end
  end

  return co
end

local function apply(_state)
  for i=1, #_state, 1 do
    coroutine.resume(_state[i])
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
  apply(tweak(notes))
end

-- potential optimization: split and lookup notes before playing
local sequence = {}

local totaltime = 0

local name = "file " .. arg[1]

for line in io.lines(arg[1]) do
  local words = {}
  for word in line:gmatch("[^ ]+") do
    words[#words+1] = tonumber(word) or word
  end
  local notes = {[3] = words[1]}

  if type(words[1]) ~= "number" then
    name = '"'..line..'"'
  else

    for i=2, #words do
      local name, oct = words[i]:match("([A-H]#?)(%d?)")
      oct = tonumber(oct)
      notes[oct] = notes[oct] or {}
      notes[oct][lookup[name]] = true
    end

    sequence[#sequence+1] = notes
    totaltime = totaltime + notes[3]
  end
end

local function accurate_sleep(time)
  if arg[2] == "-stupid-fast" then
    return sleep(0)
  end

  local sleep_time = math.max(0, time - 0.05)
  local start = epoch("utc") / 1000
  sleep(sleep_time)
  repeat
    local delta = (epoch("utc") / 1000) - start
  until delta >= time
end

stop()

local times = {}
local states = {}
for i=1, #sequence do
  local s = sequence[i]
  states[#states+1] = tweak(s)
  times[#times+1] = sequence[i][3]
end

if arg[2] == "-r" then
  print("Waiting for a redstone signal...")
  pullEvent("redstone")
end

term.clear()
term.setCursorPos(1,1)
print("Playing " .. name)
if arg[2] == "-stupid-fast" then
  printError("saw -stupid-fast option, not liable for damages")
end
print("Total Duration: ", os.date("%H:%M:%S", totaltime - (19*3600)))
local x, y = term.getCursorPos()
local elapsed = 0
local totalelapsed = 0

local average = 0
local min = math.huge
local max = 0

for i=1, #states, 1 do
  local start = epoch("utc")
  apply(states[i])
  elapsed = elapsed + times[i]
  if elapsed > 1 then
    totalelapsed = totalelapsed + elapsed
    elapsed = 0
    term.setCursorPos(x, y)
    print("Time Elapsed: ", os.date("%H:%M:%S", totalelapsed - (19*3600)))
    print("Notes Played: ", played)
  end
  local delta = epoch("utc") - start
  average = (average + delta) / (average == 0 and 1 or 2)
  min = delta < min and delta or min
  max = delta > max and delta or max
  accurate_sleep(times[i])
end

stop()

print(("Update time avg/min/max: %.2fms/%.2fms/%.2fms"):format(average,min,max))
