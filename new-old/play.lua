-- Play music on the New Pipe Organ

local midi = require("midi")

local names = peripheral.getNames()
for i=#names, 1, -1 do
  if not names[i]:match("redstoneIntegrator") then
    table.remove(names, i)
  end
end

local wrappers = {}

table.sort(names, function(a, b)
  return tonumber(a:match("_(%d+)")) < tonumber(b:match("_(%d+)"))
end)

local config
do
  local hand = io.open("/organ-config", "r")
  if not hand then
    error("Could not open /organ-config - have you run config.lua?", 0)
  end
  local dat = hand:read("a")
  hand:close()
  config = textutils.unserialize(dat)
end


for i=1, #names do
  wrappers[i] = peripheral.wrap(names[i])
  wrappers[i].setOutput(config.side, false)
end

local file = arg[1]
if not file then
  error("File argument required", 0)
end

local function printf(...)
  print(string.format(...))
end

local tNum, tDen = 4, 4
local tempo = 120
local tempo_mod = 1
local tpqn = 0

local ranks = {}

for octave=1, #config do
  for rank=1, #config[octave] do
    ranks[rank] = ranks[rank] or {}
    ranks[rank][octave] = config[octave][rank]
  end
end

local MIN_NOTE, MAX_NOTE = 43-12, 78+12
local MAX_OCTAVE = 5

local function getIDs(id)
  local base_id = (id - MIN_NOTE) % 12
  local octave = math.floor((id - MIN_NOTE) / 12) + 1
  if octave > MAX_OCTAVE then octave = MAX_OCTAVE end
  if octave < 1 then octave = 1 end

  return base_id, octave
end

local function getUnusedPipe(id)
  while id < MIN_NOTE do
    id = id + 12
  end
  while id > MAX_NOTE do
    id = id - 12
  end

  local base_id, octave = getIDs(id)

  for rank=1, #ranks do
    if type(ranks[rank][octave][base_id]) == "number" then
      --if os.epoch("utc") - ranks[rank][octave][base_id] >= 50 then
        ranks[rank][octave][base_id] = true
        return rank, octave, base_id
      --end
    end
    if not ranks[rank][octave][base_id] then
      ranks[rank][octave][base_id] = true
      return rank, octave, base_id
    end
  end

  printError("Ran out of pipes! Note ID: " .. id)
end

local function accurate_sleep(time)
  local sleep_time = math.max(0, time - 0.05)
  local start = os.epoch("utc") / 1000
  if sleep_time < 100000 then
    sleep(sleep_time)
  else
    error("Uncharacteristically large sleep value: " .. tostring(sleep_time), 0)
  end
  repeat
    local delta = (os.epoch("utc") / 1000) - start
  until delta >= time
end

local queue = {}
local function noteOn(id, vel)
  local base_id, octave = getIDs(id)
  for i=1, #queue do
    local r, o, n, s = queue[i]
    if s == "on" and o == octave and n == base_id then
      print"ignore duplicate"
      return
    end
  end
  for i=1, math.floor(1.5) do
    local rank, octave, note = getUnusedPipe(id)
    if not rank then return end
    queue[#queue+1] = {rank, octave, note, "on"}
  end
end

local function noteOff(id)
  local base_id, octave = getIDs(id)

  for rank=1, #ranks do
    if ranks[rank][octave][base_id] == true then
      queue[#queue+1] = {rank, octave, base_id, "off"}
    end
  end
end

local function flushQueue()
  local parallels = {}
  for i=1, #queue do
    local func
    local rank, octave, id, state = table.unpack(queue[i])
    local integrator =
        ranks[rank][octave].start + ranks[rank][octave].direction * id
    if state == "off" then
      func = function()
        --print("note off", octave, id)
        if type(ranks[rank][octave][id]) ~= "number" then
          wrappers[integrator].setOutput(config.side, false)
          ranks[rank][octave][id] = os.epoch("utc")
        end
      end
    elseif state == "on" then
      func = function()
        --print("note on", octave, id)
        wrappers[integrator].setOutput(config.side, true)
      end
    end
    parallels[#parallels+1] = func
  end
  queue = {}
  parallel.waitForAll(table.unpack(parallels))
end

local function playbackCallback(...)
  local evt = table.pack(...)
  if evt[1] == "header" then
    printf("Playing SMF format %d. %d tracks, %d ticks per quarter-note.", evt[2], evt[3], evt[4])
    tpqn = evt[4]
  elseif evt[1] == "track" then
    printf("Begin track %d.", evt[2])
  elseif evt[1] == "timeSignature" then
    tNum, tDen = evt[2], evt[3]
    print("Time: " .. tNum.."/"..tDen)
  elseif evt[1] == "setTempo" then
    tempo = evt[2] * tempo_mod
    print("Tempo: " .. evt[2].."bpm (multiplied: "..tempo..")")
  elseif evt[1] == "deltatime" then
    if evt[2] > 0 then
      flushQueue()
      
      -- 60/tempo = seconds per beat
      -- tDen = this note is 1 beat
      -- tpqn = ticks per quarter-note
      -- 4/tDen * tpqn = ticks per beat
      -- 60/tempo * 4/tDen * tpqn = time to sleep per quarter-note
      -- 60/tempo * 4/tDen * ticks/tpqn = time to sleep for N ticks
      accurate_sleep(60/tempo * 4/tDen * evt[2]/tpqn)
    end
  elseif evt[1] == "noteOn" then
    if evt[4] == 0 then
      noteOff(evt[3])
    else
      noteOn(evt[3], evt[4])
    end
  elseif evt[1] == "noteOff" then
    noteOff(evt[2])
  end
end

local hand = assert(io.open(file, "r"))
local events = {}

do
  local intermediate = {[0]={}}
  local pointers = {}

  local tracked_events = {
    noteOn = true, noteOff = true, deltatime = true, setTempo = true,
    timeSignature = true
  }

  midi.process(hand, function(...)
    local evt = table.pack(...)
    if evt[1] == "track" then
      printf("Process track %d.", evt[2])
      intermediate[evt[2]] = {}
      pointers[evt[2]] = 1
    elseif tracked_events[evt[1]] then
      intermediate[#intermediate][#intermediate[#intermediate]+1] = evt
    else -- time signature events, etc
      -- this behavior is not quite correct
      events[#events+1] = evt
    end
  end)

  -- get beginning noteOn events
  local function popTrack(n)
    pointers[n] = pointers[n]+1
    return intermediate[n][pointers[n]-1]
  end

  local current = {}
  for i=1, #intermediate do
    current[i] = popTrack(i)
  end

  local c = 0
  local function isPresent()
    for i=1, #pointers do if current[i] then return true end end
  end

  while isPresent() do
    local shortest, shortestTime = 0, math.huge

    for i=1, #pointers do
      while current[i] and (current[i][1] ~= "deltatime" or current[i][2] == 0) do
        events[#events+1] = current[i]
        --print(i, ":", table.unpack(current[i]))
        current[i] = popTrack(i)
      end

      if not current[i] then current[i] = false end
    end

    for i=1, #current do
      if current[i] then
        --print(table.unpack(current[i]))
        if current[i][2] < shortestTime then
          shortest, shortestTime = i, current[i][2]
        end
      end
    end

    if shortest > 0 then events[#events+1] = {"deltatime", shortestTime} end
    local shortestDifference = math.huge

    for i=1, #current do
      if current[i] then
        current[i][2] = current[i][2] - shortestTime
      end
    end
  end
end

hand:close()

print(#events, "events")

for i=1, #arg do
  if arg[i] == "-half" then
    tempo_mod = tempo_mod / 2
  elseif arg[i] == "-double" then
    tempo_mod = tempo_mod * 2
  elseif arg[i] == "-three" then
    tempo_mod = tempo_mod * 0.75
  end
end

for i=1, #events do
  playbackCallback(table.unpack(events[i]))
end

for i=1, #wrappers do
  wrappers[i].setOutput(config.side, false)
end
