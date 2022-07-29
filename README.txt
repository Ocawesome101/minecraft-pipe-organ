This repository contains files for the Minecraft
Pipe Organ.

trackers/:      Contains trackers for all
                versions of the organ.
from-ws.lua:    Reads from a WebSocket on
                127.0.0.1:25000.
midi2music.lua: Reads MIDI input using midialsa
                and posix.time;  writes it in the
                trackers' music format.  If given
                any arguments, omits the time -
                pipe that over a websocket to an
                instance of from-ws.lua to play in
                almost-real-time.
e:      A little bit of Rush E.
ge:     Entry of the Gladiators (Julius Fucik).
im:     Half of Star Wars' Imperial March.
mk:     In the Hall of the Mountain King (Grieg).
riff:   A piece I wrote based on a meme riff.
