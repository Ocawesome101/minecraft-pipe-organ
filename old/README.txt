This repository contains files for the Minecraft
Pipe Organ.

trackers/:      Contains trackers for several
                versions of the organ.
v4/:            All data related to version 4.
play.lua:       Micro-optimized music player.
from-ws.lua:    Reads from a WebSocket on
                127.0.0.1:25000.
midi2music.lua: Reads MIDI input using midialsa
                and posix.time;  writes it in the
                trackers' music format.  If given
                any arguments, omits the time -
                pipe that over a websocket to an
                instance of from-ws.lua to play in
                almost-real-time.
mscx2music.lua: Converts MuseScore 3 scores into
                the trackers' music format. Should
                be *mostly* bug-free.
e:      A little bit of Rush E.
ge:     Entry of the Gladiators (Julius Fucik).
im:     Half of Star Wars' Imperial March.
mk:     In the Hall of the Mountain King (Grieg).
riff:   A piece I wrote based on a meme riff.
pirate: He's a Pirate by Hans Zimmer (arr. Klaus
        Badelt)
