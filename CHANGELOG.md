# Unearth version log

The same log is shown in the game (menu, "Version log").

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
