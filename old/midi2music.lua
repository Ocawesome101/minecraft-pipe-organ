-- midi2music
-- requires the midialsa module (https://pjb.com.au/comp/lua/midialsa.html)
-- and posix.time

local alsa = require("midialsa")
local time = require("posix.time")

local MIN_NOTE = 48
local MAX_NOTE = 84

alsa.start()
local _ = alsa.client("m2m", 1, 1, true)
assert(alsa.connectfrom(0, 24, 0))

local lookup = {
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

-- range 42-78
local function pitch2note(p)
  if p < MIN_NOTE or p > MAX_NOTE then return end
  local base_id = (p - MIN_NOTE) % 12
  local octave = (p - MIN_NOTE) // 12
  if octave == 3 then base_id = 12 octave = 2 end
  return lookup[base_id] .. octave
end

local function get_time()
  local t = time.clock_gettime(time.CLOCK_REALTIME)
  return t.tv_sec + (math.floor(t.tv_nsec / 1000000 + 0.5) / 1000)
end

local last_update = get_time()
local notes = {}
while true do

  local evt = alsa.input()
  local ctime = get_time()
  if ctime - last_update > 0.03 then
    if #arg > 0 then
      print(table.concat(notes, " "))
    else
      print((math.ceil((ctime - last_update) * 20) / 20) .. " "
        .. table.concat(notes, " "))
    end
    last_update = ctime
  end

  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    notes[#notes+1] = pitch2note(pitch)

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    if pitch >= MIN_NOTE and pitch <= MAX_NOTE then
      local name = pitch2note(pitch)
      for i=1, #notes, 1 do
        if notes[i] == name then
          table.remove(notes, i)
          break
        end
      end
    end
  end
end
