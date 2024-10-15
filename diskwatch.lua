-- Watch for disks with MIDI files on them.

print("Watching for disk insertions.")

while true do
  local name, side = os.pullEvent("disk")
  local drive = peripheral.wrap(side)
  local path = drive.getMountPath()

  local files = fs.list(path)
  for i=1, #files do
    if files[i]:sub(-4) == ".mid" then
      shell.run("play /"..path.."/"..files[i])
    end
  end
end
