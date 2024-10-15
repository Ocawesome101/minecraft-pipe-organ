-- Configure the New Pipe Organ
-- There are four pipes per note: two for redundancy (faster note repeats)
-- and two for volume

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

if #wrappers % 12 > 0 then
  error("number of Redstone Integrators connected ("..#wrappers..") is not a multiple of 12", 0)
end

print("Beginning configuration.")

local conf = {}
local sides = {"up", "down", "left", "right", "front", "back"}
local cside = 1
conf.side = sides[cside]
local function nextSide()
  cside = (cside % #sides) + 1
  conf.side = sides[cside]
end

local function playNote(ri)
  ri.setOutput(conf.side, true)
  sleep(0)
  ri.setOutput(conf.side, false)
  sleep(0)
end

local function playScale(begin)
  for i=begin, begin+11 do
    playNote(wrappers[i])
  end
end

for i=1, #sides do
  conf.side = sides[i]
  print("Trying side "..conf.side..".")
  for i=1, 8 do
    playNote(wrappers[math.random(1, #wrappers)])
  end
  print("Did you hear sounds? [y = yes, n = try another side]")
  local inp
  repeat
    inp = read()
  until inp == "y" or inp == "n"
  if inp == "y" then break end
end

for i=1, #wrappers/12 do
  print("Playing scale using side '"..conf.side.."'...")
  local riindex = (i-1)*12+1
  playScale(riindex)

  local octave
  repeat
    print("Which octave? [1 = lowest, 2 = middle, 3 = highest, a = play Again] ")
    local command = read()
    if command == "a" then
      playScale(riindex)
    end
    octave = tonumber(command)
  until octave and octave > 0 and octave < 4

  conf[octave] = conf[octave] or {}

  local direction
  repeat
    print("Which direction? [1 = up, -1 = down] ")
    direction = tonumber(read())
  until direction and direction == 1 or direction == -1

  if direction == -1 then riindex = riindex + 11 end
  
  local oconf = {start = riindex, direction = direction}

  conf[octave][#conf[octave]+1] = oconf
end

local oc = io.open("/organ-config","w")
oc:write(textutils.serialize(conf))
oc:close()
