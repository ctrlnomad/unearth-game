# Unearth version log

The same log is shown in the game (menu, "Version log").

## v0.2.1 (2026-11-13): mouse fix

- Bug: on itch.io the mouse did nothing when the browser refused to capture the pointer (an iPad never grants it). The mouse now plays uncaptured in that case: move to look, hold the button to fire, WASD to walk.
- A real mouse click switches back from touch controls; the on-screen FIRE button and thumbstick only show while playing by touch.

## v0.2 (2026-11-13): moved to Godot

Direction decisions
- The game is developed in Godot again (4.7.2) and exported to the browser, so the laptop game and the iPad build are one project. The v0.1 browser prototype in `web/` is no longer developed.
- The web export uses Godot's Compatibility renderer. The Loading Bay's volumetric haze is not available there, so in the browser the bay has distance fog only; the desktop build keeps the haze.
- The scanner is amber (it was red in the first Godot prototype), so it reads against the red emergency lights and the cyan gas. Its spray is wider and denser, because it now paints the room with dots.

What is in
- Everything from v0.1, ported to Godot: power cells, scanner dots, ghosts that follow the scanner's radiation and freeze under the beam, solar flares, emergency lights and vents, getting caught, Level 2 (Reception), the end card.
- Level 1 is the original Godot Loading Bay (the larger octagonal hall, the Earth, the ship exploding), now with three cells, emergency lights, the cargo door opening and the shape in the dust.
- Touch controls: thumbstick on the left, look on the right, FIRE button. In the menu, tap the START button by the door.
- Menu buttons for the version log and for starting at level 2.
- New dev-mode constants: `gun.dot_life`, `cell.charge_time`, `ghost.*`, `flare.every`, `rec.*`.
- Capture mode: `--level=2`, `--charge=N` (fill N cells), `--ghost=x,z` (stand a lit ghost there).

Not checked
- Sound by ear, and how the web build runs on a real iPad.

## v0.1 (2026-11-13): first browser build

Direction decisions
- Rebuilt the game for the browser (Three.js, single page) so it plays on an iPad. The Godot project stays in the repo as reference.
- The Cleaner is a contractor answering an automated request: "restore emergency power". The pod is single use.
- The gas is Omni-23. It has no eyes: it finds you by the radiation of your scanner, so ghosts walk faster while you fire.
- The scanner cannot hurt the gas. Holding the beam on a ghost freezes it for a few seconds.
- Solar flares from the pale sun arrive in Reception (level 2) instead of the Canteen, so the player has a fair way to see every ghost.
- Being caught sends you back to the level door; charged cells stay charged.

What is in
- Menu inside the pod, with the maintenance request on the terminal and a START button by the door.
- Opening sequence: lights die, the pod shakes, the door opens, the Cleaner is thrown into the station.
- Level 1, the Loading Bay: three power cells, no threat, the gas as fireflies, the ship drifting past the window and exploding, a shape in the dust when the vents start.
- Level 2, Reception: four cells, the scripted first ghost behind the desk, one more ghost for each cell charged, flares, the vents clearing the gas.
- Scanner rays leave fading dots on every surface, so you map the dark by firing.
- Touch controls (left thumb moves, right thumb looks, hold FIRE) and mouse/keyboard controls.
- Generated sound: room tone, scanner, charge tone, proximity clicks, stings. Not yet checked by ear.

Not in yet
- The Lab, Canteen and Reactor levels, the second gun, overcharging cells, music.
