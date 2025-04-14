-- the Multivoice Pipe Organ
-- a real multitrack midi player

-- Uses analog signals on two dedicated Redstone Integrators to configure
-- each single-octave rank, so 14 Integrators/octave
-- the first 12 are notes
-- 13 sets the octave (lowest (1) begins on G-1),
-- 14 sets the voice/stop ID
-- the analog signal must come in on the same side used for pipe control

local midi = require("midi")

local min_octave = math.huge
local max_octave = 0

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

for i=1, #names do
  wrappers[i] = peripheral.wrap(names[i])
end

if #wrappers % 14 > 0 then
  error("number of Redstone Integrators connected ("..#wrappers..") is not a multiple of 14", 0)
end

term.setBackgroundColor(colors.gray)
term.clear()
local current = term.current()
local outputwin = window.create(current, 1, 1, 41, 19, true)
term.redirect(outputwin)

-- Keeps track of which notes are playing.
--  pipes[voice_id] = {
--    [note_id] = { i1 = {playing=true,side='...'},
--      i2 = {playing=false,side='...'} }
--  }
local pipes = {}
-- MIDI specifies 16 tracks.
-- tracks[n] = {voices = {}, events = {}, lastEvent = 0}
local tracks = {}

local sides = {"back", "top", "bottom", "left", "right", "front"}

local INT_OCTAVE = 12
local INT_VOICE = 13
local BASE_NOTE = 7 -- G-1, the G below A0

local function getNoteID(octave, index)
  return BASE_NOTE+(octave+1)*12 + index
end

local function findSide(begin)
  for i=1, #sides do
    if wrappers[begin+INT_OCTAVE].getInput(sides[i]) then
      return sides[i]
    end
  end
  printError("WARNING! " .. peripheral.getName(wrappers[begin]))
end

do
  local finders = {}

  for i=1, #wrappers, 14 do
    finders[#finders+1] = function()
      local side = findSide(i)
      if side then
        local octave = wrappers[i+INT_OCTAVE].getAnalogInput(side) - 2
        local voice = wrappers[i+INT_VOICE].getAnalogInput(side)

        min_octave = math.min(min_octave, octave)
        max_octave = math.max(max_octave, octave+1)
    
        pipes[voice] = pipes[voice] or {}
        pipes[voice].min_octave =
          math.min(pipes[voice].min_octave or math.huge, octave)
        pipes[voice].max_octave =
          math.max(pipes[voice].max_octave or 0, octave+1)

        for note=0, 11 do
          local note_id = getNoteID(octave, note)
          pipes[voice][note_id] = pipes[voice][note_id] or {}
          table.insert(pipes[voice][note_id], {integrator=i+note, side=side})
        end
      end
    end
  end

  parallel.waitForAll(table.unpack(finders))
end

do
  print(#wrappers, "pipes")
  print(#wrappers/14, "octaves")
  local voices = 0
  for k in pairs(pipes) do voices = voices + 1 end
  print(voices, "voices")
end

min_note = BASE_NOTE+(min_octave)*12
max_note = BASE_NOTE+(max_octave+1)*12-1

local function shutoffAll()
  for i=1, #wrappers do
    for _, side in pairs{'top', 'bottom', 'left', 'right', 'front', 'back'} do
      wrappers[i].setOutput(side, false)
    end
  end
end

shutoffAll()

local file = arg[1]
if not file then
  error("File argument required", 0)
end

term.blit("> play ", "4000000", "fffffff")
print(file)
print("min note: ", min_note)
print("max note: ", max_note)

local function printf(...)
  print(string.format(...))
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

local function clamp(id)
  while id > max_note do
    id = id - 12
  end
  while id < min_note do
    id = id + 12
  end
  return id
end

local hand = assert(io.open(file, "r"))
local tNum, tDen = 4, 4
local tempo = 120
local tempo_mod = 1
local tpqn = 0

local enabled = {}
do
  local voiceCount = 0
  local voiceId = 0
  for voice in pairs(pipes) do voiceCount = voiceCount + 1; voiceId = voice end
  if voiceCount == 1 then enabled[voiceId] = true end
end

-- read MIDI file
do
  local currentTrack = 0

  local time = os.epoch("utc")/1000

  midi.process(hand, function(...)
    local evt = table.pack(...)
    if evt[1] == "track" then
      currentTrack = evt[2]
      tracks[currentTrack] = {
        voices = enabled,
        events = {}, nextEvent = time}
    elseif evt[1] == "sequencerOrTrackName" then
      print(evt[2])
    elseif evt[1] == "header" then
      printf("Format %d. %d tracks, %d/quarter-note.", evt[2], evt[3], evt[4])
      tpqn = evt[4]
    else
      table.insert(tracks[currentTrack].events, evt)
    end
  end)
end

hand:close()

for i=1, #arg do
  if arg[i] == "-half" then
    tempo_mod = tempo_mod / 2
  elseif arg[i] == "-double" then
    tempo_mod = tempo_mod * 2
  elseif arg[i] == "-three" then
    tempo_mod = tempo_mod * 0.75
  end
end

--[[local function voiceEnabled()
  for i=0, 15 do if enabled_voices[i] then return true end end
end]]

local function noteOn(id, vel, voices)
  local evt = {vel>0 and "on" or "off", clamp(id), math.floor(vel*16+0.5)}
  for voice in pairs(voices) do
    evt[#evt+1] = voice
  end
  return evt
end

local function apply(changes)
  local parallels = {}
  for i, event in ipairs(changes) do
    local state, note_id, velocity = table.unpack(event)

    for v=4, #event do
--  pipes[voice_id] = {
--    min_octave = 2, max_octave = 4,
--    [note_id] = { {integrator=i1,playing=true,side='...'},
--      {integrator=i2,playing=false,side='...'} }
--  }
      local voice_id = event[v]
      local integrators = pipes[voice_id][note_id] or {}
      
      for _, note in ipairs(integrators) do
        if (state == "on") ~= note.playing then
          parallels[#parallels+1] = function()
            note.playing = state == "on" and velocity or false
            wrappers[note.integrator].setAnalogOutput(note.side, velocity)
          end
        end
      end
    end
  end

  if #parallels > 255 then
    printError("WARNING - too many pipe updates? ("..#parallels..">255)")
  end
  local start = os.epoch("utc")/1000
  parallel.waitForAll(table.unpack(parallels))
  local time = os.epoch("utc")/1000 - start
  if time > 50 then
    printError("WARNING - update too slow (<50ms)")
  end
  return time
end

local function getTime()
  return os.epoch("utc")/1000
end

-- how lax to be with timing requirements
local timingSlop = 0

local function timeFromTicks(ticks, _tempo)
  _tempo = _tempo or tempo
  -- 60/tempo = seconds per beat
  -- tDen = this note is 1 beat
  -- tpqn = ticks per quarter-note
  -- 4/tDen * tpqn = ticks per beat
  -- 60/tempo * 4/tDen * tpqn = time to sleep per quarter-note
  -- 60/tempo * 4/tDen * ticks/tpqn = time to sleep for N ticks
  return 60/_tempo * 4/tDen * ticks/tpqn
end

local function ticksFromTime(time, _tempo)
  _tempo = _tempo or tempo
  return time*tpqn / (4/tDen) / (60/_tempo)
end

local function playNextEvent()
  local changes = {}
-- tracks[n] = {voices = {}, events = {}, nextEvent = 0}

  local nextEventMin = math.huge
  local currentTime = getTime()
  local tracksWithEvents = 0
  local oldTempo
  local onOldTempo = {}

  for t, track in ipairs(tracks) do
    track.ticks = track.ticks or 0
    if #track.events > 0 then
      tracksWithEvents = tracksWithEvents + 1
    else
      track.nextEvent = math.huge
    end
    while track.nextEvent <= currentTime + timingSlop and #track.events > 0 do
      repeat
        local evt = table.remove(track.events, 1)
        if evt[1] == "deltatime" then
          track.ticks = track.ticks + evt[2]
          track.nextEvent = track.nextEvent + timeFromTicks(evt[2], oldTempo)
        elseif evt[1] == "timeSignature" then
          tNum, tDen = evt[2], evt[3]
          print("Time: " .. tNum.."/"..tDen)
        elseif evt[1] == "setTempo" then
          oldTempo = tempo
          tempo = evt[2] * tempo_mod
          print("Tempo: " .. evt[2].."bpm (mod: "..tempo..")")
        elseif evt[1] == "noteOn" then
          changes[#changes+1] = noteOn(evt[3], evt[4], track.voices)
        elseif evt[1] == "noteOff" then
          changes[#changes+1] = noteOn(evt[3], 0, track.voices)
        end
      until #track.events == 0 or (evt[1] == "deltatime" and evt[2] > 0)
    end
    nextEventMin = math.min(nextEventMin, track.nextEvent)
  end

  -- scale time remaining for all tracks to match new tempo
  if oldTempo then
    local oldNextEventMin = nextEventMin
    nextEventMin = math.huge
    --local delta = oldNextEventMin - currentTime
    for t, track in ipairs(tracks) do
      local delta = track.nextEvent - currentTime
      track.nextEvent = track.nextEvent - delta +
        timeFromTicks(ticksFromTime(delta, oldTempo))
      
      nextEventMin = math.min(nextEventMin, track.nextEvent)
    end
  end

  apply(changes)

  if nextEventMin > 0 and nextEventMin < math.huge then
    accurate_sleep(nextEventMin - currentTime)
  end

  return tracksWithEvents > 0
end

local function voiceEnabled()
  for i=0, 15 do if enabled[i] then return true end end
end

local paused = false--getTime()
local function pause()
  paused = getTime()
  for v, voice in pairs(pipes) do
    for n, note in pairs(voice) do
      if type(note) == "table" then
        for i=1, #note do
          if note[i].playing then
            wrappers[note[i].integrator].setAnalogOutput(note[i].side, 0)
          end
          if not enabled[v] then note[i].playing = false end
        end
      end
    end
  end
end

local function play()
  local time = getTime()
  for _, track in ipairs(tracks) do
    track.nextEvent = track.nextEvent + (time - paused)
  end
  paused = false
  for v, voice in pairs(pipes) do
    for n, note in pairs(voice) do
      if type(note) == "table" then
        for i=1, #note do
          if note[i].playing then
            wrappers[note[i].integrator].setAnalogOutput(note[i].side,
              note[i].playing)
          end
        end
      end
    end
  end
end

if not voiceEnabled() then pause() end

parallel.waitForAny(function()
  while true do
    while paused do
      os.sleep(0)
    end
    if not voiceEnabled() then pause() end
    if not playNextEvent() then break end
  end
end, function()
  local function draw(x, y)
    term.redirect(current)
    
    local cy = 0
    for i=0, 15 do
      if pipes[i] ~= nil then
        cy = cy + 1
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(43, cy)
        local min, max = pipes[i].min_octave, pipes[i].max_octave
        term.write(string.format("G%d-F#%d", min, max))
        if x and x > 48 and y == cy then
          if enabled[i] then enabled[i] = nil else enabled[i] = true end end
        term.setCursorPos(50, cy)
        term.setBackgroundColor(enabled[i] and colors.green or colors.red)
        term.setTextColor(colors.white)
        term.write(tostring(i))
        if i < 10 then term.write(" ") end
      end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    cy = cy + 2
    if x and x > 48 and y == cy then
      if paused then play() else pause() end end
    term.setCursorPos(50, cy)
    if not paused then
      term.write("\x95\x95")
    else
      term.blit("\x95\x84", "f0", "0f")
    end

    term.redirect(outputwin)
  end

  draw()

  while true do
    local evt, b, x, y = os.pullEvent()
    if evt == "mouse_click" then
      draw(x, y)
    else
      draw()
    end
  end
end)

shutoffAll()
