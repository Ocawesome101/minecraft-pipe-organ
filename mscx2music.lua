#!/usr/bin/env lua
-- Convert MSCX files to the Minecraft Pipe Organ Format
-- uses xmllpegparser

local xml = require("xmllpegparser")

if arg[1] == "--help" then
  io.stderr:write([[
usage: mscx2music [/path/to/mscx] [baseTime]

baseTime is the time in seconds that one 16th note should take.
Does not support anything shorter than 16th notes.  Acciaccatura
are always 0.05s (1 tick).
]])
  os.exit(1)
end

local file = arg[1] and assert(io.open(arg[1], "r")) or io.stdin
local data = file:read("a")
file:close()

-- get around some slight weirdness
data = data:gsub("<(acciaccatura)/>", "<%1></%1>")
local d = xml.parse(data)

-- find museScore.Score.Staff id="1" and id="2"

local function find(elem, path, attrs)
  if #path == 0 then return elem end

  local look = table.remove(path, 1)
  for i=1, #elem.children, 1 do
    if elem.children[i].tag == look then
      local match = true
      if #path == 0 and attrs then
        for k, v in pairs(attrs) do
          if elem.children[i].attrs[k] ~= v then
            match = false
          end
        end
      end
      if match then return find(elem.children[i], path, attrs) end
    end
  end
end

local staff1 = find(d, {"museScore", "Score", "Staff"}, {id="1"}).children
local staff2 = find(d, {"museScore", "Score", "Staff"}, {id="2"}).children

local m1, m2 = {}, {}

for i=1, #staff1, 1 do
  if staff1[i].tag == "Measure" then
    m1[#m1+1] = staff1[i]
  end
end

for i=1, #staff2, 1 do
  if staff2[i].tag == "Measure" then
    m2[#m2+1] = staff2[i]
  end
end

if #m1 ~= #m2 then
  error("mismatched measure counts - this doesn't make sense", 0)
end

local base = tonumber(arg[2]) or 0.10

local durationMap = {
  measure =     base*32,
  whole =       base*32,
  half =        base*16,
  quarter =     base*8,
  eighth =      base*4,
  ["16th"] =    base*2,
  ["32nd"] =    base
}

local graceMap = {
  eighth = 0.05
}

local noteLookup = {
  [0] = "F#",
  "G",
  "G#",
  "A",
  "A#",
  "B",
  "C",
  "C#",
  "D",
  "D#",
  "E",
  "F",
  "H"
}

local MIN_NOTE = 42
local MAX_NOTE = 78
local WRAP_OCTAVE = 3

local wrapped = {up = 0, down = 0}

local function pitchToNote(p)
  while p < MIN_NOTE do wrapped.up = wrapped.up + 1 p = p + 12 end
  while p > MAX_NOTE do wrapped.down = wrapped.down + 1 p = p - 12 end

  local base_id = (p - MIN_NOTE) % 12
  local octave = (p - MIN_NOTE) // 12

  if octave == WRAP_OCTAVE then base_id = 12 octave = WRAP_OCTAVE - 1 end

  return noteLookup[base_id] .. octave
end

local function inChord(c, n, N)
  if not c then return end
  for i=2, #c, 1 do
    if c[i] == n then
      return true
    end
  end
end

-- returns {
--   [1] = {
--     { duration, <chord> },
--     { duration, <chord> },
--   },
--   [2] = {
--     { duration, <chord> },
--     { duration, <chord> },
--   }
-- }
-- where each [n] is a voice
local previous = {}
local function getRawNoteSequence(...)
  local ret = {}

  local vid = 0
  for _, measure in ipairs(table.pack(...)) do
    for i=1, #measure, 1 do
      if measure[i].tag == "voice" then
        vid = vid + 1
        local voice = measure[i].children

        local voiceData = {}

        local nextRealDurationOffset = 0

        for c=1, #voice, 1 do
          if voice[c].tag == "Chord" or voice[c].tag == "Rest" then
            local chord = {}
            local durType = find(voice[c], {"durationType"}).children[1].text
            local duration

            if find(voice[c], {"acciaccatura"}) then
              duration = graceMap[durType]
              if not duration then
                error("unknown acciaccatura type - " .. durType, 0)
              end
              nextRealDurationOffset = nextRealDurationOffset + duration

            else
              duration = durationMap[durType]
              if not duration then
                error("unknown duration type - " .. durType, 0)
              end
              if find(voice[c], {"dots"}) then
                duration = duration * 1.5^tonumber(
                  find(voice[c], {"dots"}).children[1].text)
              end
              duration = duration - nextRealDurationOffset
              nextRealDurationOffset = 0
            end

            chord[1] = duration

            local didOffset = false
            for _, child in ipairs(voice[c].children) do
              if child.tag == "Note" then
                local pitch = tonumber(find(child, {"pitch"}).children[1].text)
                pitch = pitchToNote(pitch)
                -- make repeated notes work
                local prev = previous[vid] or {}

                if inChord(prev[#prev], pitch, "PREV"..vid) or
                    (#voiceData > 0 and inChord(voiceData[#voiceData],
                      pitch)) then

                  if not didOffset then
                    didOffset = true

                    local _prev = voiceData[#voiceData] or prev[#prev]
                    _prev[1] = _prev[1] - 0.05

                    local new = { 0.05 }
                    local tab = voiceData[#voiceData] or prev[#prev]
                    for j=2, #tab do
                      local note = tab[j]

                      if note ~= pitch then
                        new[#new+1] = note
                      end
                    end

                    voiceData[#voiceData+1] = new
                    chord[1] = chord[1] -- 0.05

                  else
                    local _data = voiceData[#voiceData] or prev[#prev]

                    for j=#_data, 2, -1 do
                      if _data[j] == pitch then
                        table.remove(_data, j)
                      end
                    end
                  end
                end

                if not inChord(chord, pitch) then
                  chord[#chord+1] = pitch
                end
              end
            end

            voiceData[#voiceData+1] = chord
          end
        end

        ret[vid] = voiceData
      end
    end
  end

  previous = ret
  return ret
end

local function copy(t)
  local c = {}
  for k,v in pairs(t) do
    if type(v) == "table" then v = copy(v) end
    c[k] = v
  end
  return c
end

-- merge voices, splitting longer notes accordingly
local function getNoteSequence(...)
  local final = {}

  local raw = copy(getRawNoteSequence(...))

  local function readLength(voice, length)
    local _l = length
    local ret = {}

    while length > 0 and #raw[voice] > 0 do
      local chord = raw[voice][1]
      local sub = math.min(chord[1], length)
      length = length - sub

      if chord[1] <= sub then
        ret[#ret+1] = table.remove(raw[voice], 1)

      else
        chord[1] = chord[1] - sub
        ret[#ret+1] = { sub, table.unpack(chord, 2) }
      end
    end

    io.stderr:write(("%f; %d\n"):format(_l, #ret))
    return ret
  end

  while #raw[1] > 0 and #raw[2] > 0 do
    -- find shortest chord within any voice
    local shortest = math.huge

    for v=1, #raw, 1 do
      shortest = math.min(raw[v][1] and raw[v][1][1] or math.huge, shortest)
    end

    local finalChord = { shortest }

    for i=1, #raw, 1 do
      local chords = readLength(i, shortest)

      for c=1, #chords, 1 do
        for n=2, #chords[c], 1 do
          finalChord[#finalChord+1] = chords[c][n]
        end
      end
    end

    final[#final+1] = finalChord
  end

  return final
end

for mid=1, #m1, 1 do

  local measure1, measure2 = m1[mid].children, m2[mid].children

  io.stderr:write(("BEGIN MEASURE %d\n"):format(mid))
  local chords = getNoteSequence(measure1, measure2)
  io.stderr:write(("have %d chords\n"):format(#chords))

  for i=1, #chords, 1 do
    local duration = math.ceil(chords[i][1] * 20) / 20
    print(string.format("%.2f %s", duration,
      table.concat(chords[i], " ", 2)))
  end

end

io.stderr:write("Wrapped " .. wrapped.up .. " notes up and " .. wrapped.down .. " notes down (" .. (wrapped.up + wrapped.down) .. " total).\n")
