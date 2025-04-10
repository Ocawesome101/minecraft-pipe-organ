# the Minecraft Pipe Organ

This repository contains all the files for the Minecraft Pipe Organ.

Everything in `old/` is the stuff used in videos.  I've since rewritten everything to be much cleaner and generally better.

Everything in `new-old/` is the second iteration of organ controllers.  It plays MIDI and supports arbitrary configurations of octaves.

The root folder of this repository contains the newest controller.  It is a real multitrack MIDI player.  The biggest practical effect of this is that tempo changes now work exactly as they should.  The player supports individual voices (currently as 'stops' that the user must toggle, but with planned support for standard General MIDI program numbers).  It also requires no configuration once the organ has been built.

## Setup

The player script expects a continuous array of [Advanced Peripherals](https://modrinth.com/mod/advancedperipherals)'s Redstone Integrators, which should power a continuous array of Steam Whistles from [Create](https://modrinth.com/mod/create), or from [Create: Sound of Steam](https://modrinth.com/mod/create-sound-of-steam).  Each set of 14 Integrators must contain one octave (12 pipes, with the lowest note being G), in ascending order, plus two analog signals (provided by Analog Levers, or Redstone Links, or any other source), which *must* power the same side of the Integrators that will be used to power organ pipes.  The first signal sets the octave of that pipe rank, and the second sets which voice it uses.  If the octave signal is 0, the player will display a warning and will move on to the next set of pipes.  The octave signal is offset by -2, e.g. signal 1 = octave -1, signal 5 = octave 3, etc.  Create's built-in Steam Whistles range from octave 2 (octave signal 4) to octave 4 (octave signal 6).

The exact details of what any given Redstone Integrator provides power to are not important.  The Steam Whistles may just as easily be note blocks, or anything else pitched or unpitched.  Notably, the player script outputs *analog* signals from 0 to 15 based on note velocity, which may be used to construct a machine capable of dynamics.

`midi.lua` - MIDI support code.

`play.lua` - The player script.  It takes a single MIDI file as its argument, and will parse and play the file.  Any MIDI file should work.  Using pipes from *Create: Sound Of Steam*, it is possible to build very large organ ranges that can play any file with no range limits (from G-1 to F#8 or so).
