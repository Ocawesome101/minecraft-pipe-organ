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

local staff1 = find(d, {"museScore", "Score", "Staff"}, {id="1"})
local staff2 = find(d, {"museScore", "Score", "Staff"}, {id="2"})

local m1, m2 = {}, {}

for i=1, #staff1, 1 do
  if staff1[i].tag == "Measure" then
    m1[#m1+1] = staff1[i]
  end
end
