-- basic music tracker
-- this expects the range to be 63-101
-- only works on Pipe Organ v3

local integrators = {}

for i=63, 101, 1 do
  integrators[i] = peripheral.wrap("redstoneIntegrator_"..i)
end

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

local empty = {}
local state = {}
local function apply(notelist)
  local co = {}

  for octave = 0, 2 do
    local notes = notelist[octave] or empty
    for note = 0, 12 do
      if (state[octave] and state[octave][note]) ~= (not not notes[note])
          or (not state[octave]) or (state[octave][note] == nil) then
        state[octave] = state[octave] or {}
        state[octave][note] = not not notes[note]
        co[#co+1] = function()
          local index = note + (octave * 13) + 63
          integrators[index].setOutput("back", not not notes[note])
        end
      end
    end
  end

  for i=1, #co, 1 do
    coroutine.resume(coroutine.create(co[i]))
  end
  --parallel.waitForAll(table.unpack(co))
end

local function stop()
  local notes = {}
  for o=0, 2, 1 do
    for i=0, 12, 1 do
      notes[#notes+1] = {note=i,octave=o,yes=false}
    end
  end
  apply(notes)
end

local function drawKeyboard(oct)
  term.setTextColor(colors.black)
  for i=1, 4, 1 do
    term.setCursorPos(2, i + (oct * 5))
    if i > 3 then
      term.write((" "):rep(13))
    else
      term.write("# # #  # #  #")
    end
  end
end

local function draw()
  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setBackgroundColor(colors.white)
  for i=0, 2 do
    drawKeyboard(i)
  end
  term.setCursorPos(1, 16)
  print("first field is duration, type with numbers")
  term.setCursorPos(1, 17)
  print("s - save; l - load; \x1b - del item; \\n - next; q - quit")
end

local function drawNote(note, octave)
  term.setBackgroundColor(colors.green)
  for i=1, 4, 1 do
    term.setCursorPos(note+2, i+(2-octave)*5)
    term.write(" ")
  end
end


stop()

local sock = http.websocket("ws://127.0.0.1:25000")
while true do
  local msg = sock.receive()
  draw()
  local music = {}
  for word in msg:gmatch("[^ ]+") do
    music[#music+1] = word
  end
  local notes = {}
  for n=1, #music do
    local name, oct = music[n]:match("([A-H]#?)(%d?)")
    if oct then
      oct = tonumber(oct)
      notes[oct] = notes[oct] or {}
      notes[oct][lookup[name] or -1] = true
      drawNote(lookup[name] or -1, oct)
    end
  end
  apply(notes)
end
