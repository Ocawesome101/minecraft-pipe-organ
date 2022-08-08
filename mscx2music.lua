#!/usr/bin/env lua
-- Convert MSCX files to the Minecraft Pipe Organ Format
-- uses xmllpegparser

local xml = require("xmllpegparser")

local file = arg[1] and assert(io.open(arg[1], "r")) or io.stdin
local data = file:read("a")
file:close()

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
          for _, attr in ipairs(elem.children[i].attrs) do
            if k == attr.name and v ~= attr.value then
              match = false
            end
          end
        end
      end
      if match then return find(elem.children[i], path) end
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

local durationMap = {
  measure = 1.2,
  half = 0.6,
  quarter = 0.3,
  eighth = 0.15
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

local function pitchToNote(p)
  while p < MIN_NOTE do p = p + 12 end
  while p > MAX_NOTE do p = p - 12 end

  local base_id = (p - MIN_NOTE) % 12
  local octave = (p - MIN_NOTE) // 12

  if octave == 3 then base_id = 12 octave = 2 end

  return noteLookup[base_id] .. octave
end

local function inChord(c, n)
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
local function getRawNoteSequence(...)
  local ret = {}

  for _, measure in ipairs(table.pack(...)) do
    for i=1, #measure, 1 do
      if measure[i].tag == "voice" then
        local voice = measure[i].children

        local voiceData = {}

        local nextRealDurationOffset = 0

        for c=1, #voice, 1 do
          if voice[c].tag == "Chord" or voice[c].tag == "Rest" then
            local chord = {}
            local durType = find(voice[c], {"durationType"}).children[1].text
            local duration

            if find(voice[c], {"acciaccatura/"}) then
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
              duration = duration - nextRealDurationOffset
              nextRealDurationOffset = 0
            end

            chord[1] = duration

            local didOffset = false
            for _, child in ipairs(voice[c].children) do
              if child.tag == "Note" then
                local pitch = tonumber(find(child, {"pitch"}).children[1].text)
                -- make repeated notes work
                if #voiceData > 0 and inChord(voiceData[#voiceData], pitch)
                    and not didOffset then
                  didOffset = true
                  voiceData[#voiceData+1] = { 0.05 }
                  chord[1] = chord[1] - 0.05
                end
                chord[#chord+1] = pitchToNote(pitch)
              end
            end

            voiceData[#voiceData+1] = chord
          end
        end

        ret[#ret+1] = voiceData
      end
    end
  end

  return ret
end

-- merge voices, splitting longer notes accordingly
local function getNoteSequence(...)
  local final = {}

  local raw = getRawNoteSequence(...)

  local function readLength(voice, length)
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
    return ret
  end

  while #raw[1] > 0 do
    -- find shortest chord within any voice
    local shortest = math.huge
    for v=1, #raw, 1 do
      shortest = math.min(raw[v][1][1], shortest)
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

  local chords = getNoteSequence(measure1, measure2)

  for i=1, #chords, 1 do
    print(table.unpack(chords[i]))
  end

end
