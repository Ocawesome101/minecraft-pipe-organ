-- basic music tracker
-- this expects the range to be 63-101

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

local sides = {
  [0] = "back",
  "right",
  "front"
}

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
          integrators[index].setOutput(sides[octave], not not notes[note])
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

local music = {{"0"}}
local cur = 0

local function drawMusic()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  local offset = #music - cur
  for i=#music, 1, -1 do
    local y = (#music - i + 1) - offset
    if y > 0 and y < 16 then
      if i == cur then
        term.setTextColor(colors.green)
      else
        term.setTextColor(colors.white)
      end
      term.setCursorPos(18, y)
      print(table.concat(music[i], " "))
    end
  end
  term.setCursorPos(18, 1)
  term.setCursorBlink(true)
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
  drawMusic()
end

local function drawNote(note, octave)
  term.setBackgroundColor(colors.green)
  for i=1, 4, 1 do
    term.setCursorPos(note+2, i+(2-octave)*5)
    term.write(" ")
  end
end

stop()
while true do
  draw()
  local evt, bt, x, y = os.pullEvent()
  if evt == "mouse_click" or evt == "mouse_drag" then
    if x > 1 and x < 15 then
      local note = x - 2
      local octave = (y > 10 and 0) or (y > 5 and 1) or 2
      drawNote(note, octave)
      music[#music][#music[#music]+1] = lookup[note] .. octave
      apply { [octave] = { [note] = true } }
    end
  elseif evt == "mouse_up" then
    stop()
  elseif evt == "key" then
    if bt == keys.enter then
      music[#music+1] = {"0"}
      cur = #music
    elseif bt == keys.backspace then
      if #music[#music] == 0 and #music > 1 then
        music[#music] = nil
      else
        music[#music][#music[#music]] = nil
      end
    end
  elseif evt == "char" then
    if tonumber(bt) or bt == "." then
      music[#music][1] = (music[#music][1] or "") .. bt
    elseif bt == " " then
      local oc = cur
      os.sleep(0)
      for i=1, #music, 1 do
        cur = i
        draw()
        local dur = tonumber(music[i][1]) or 1
        local notes = {}
        for n=2, #music[i] do
          local name, oct = music[i][n]:match("([A-H]#?)(%d?)")
          oct = tonumber(oct)
          notes[oct] = notes[oct] or {}
          notes[oct][lookup[name] or -1] = true
          drawNote(lookup[name] or -1, oct)
        end
        apply(notes)
        os.sleep(dur)
      end
      stop()
      cur = oc
    elseif bt == "s" then
      term.setCursorPos(2, 18)
      io.write("save to? [music]: ")
      local inp = io.read()
      if #inp == 0 then inp = "music" end
      local h = io.open(inp, "w")
      for i=1, #music, 1 do
        h:write(table.concat(music[i], " "), "\n")
      end
      h:close()
      io.write("done")
      os.sleep(0.5)
    elseif bt == "l" then
      term.setCursorPos(2, 18)
      io.write("load from? [music]: ")
      local inp = io.read()
      if #inp == 0 then inp = "music" end
      local h = io.open(inp, "r")
      if h then
        music = {}
        for line in h:lines("l") do
          local words = {}
          for word in line:gmatch("[^ ]+") do
            words[#words+1] = word
          end
          music[#music+1] = words
        end
        cur = #music
      end
    elseif bt == "q" then
      term.clear()
      term.setCursorPos(1,1)
      error()
    end
  end
end
