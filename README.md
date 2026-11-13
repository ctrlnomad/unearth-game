# Unearth (game)

First playable prototype of the lo-fi horror game. Idea and references: [ideas/unearth-game.md](../ideas/unearth-game.md). **Picking this up in a new chat? Start with [HANDOFF.md](HANDOFF.md).** It grew out of the web prototype in [unearth/](../unearth/).

The game now opens on the menu inside the Cleaner's ship, plays the opening sequence, and puts you in level 1, the Loading Bay of Meridian Labs. The earlier prototype (a dark test hall with the ghost gas, and the image artifacts you reveal with the ray gun) is still there: run with `-- --level=hall`.

## Run

Godot 4.7 (`brew install --cask godot`).

```bash
godot --path unearth-game
```

Run that from `create/`. To open it in the editor, use `godot -e --path unearth-game`. On a fresh checkout, run `godot --headless --path unearth-game --import` once first.

## Controls

| | |
|---|---|
| Menu: look at START or OPTIONS, click | start the game / open options |
| Click | capture the mouse / play |
| WASD, Shift, Space | move, run, jump |
| Hold left mouse | fire the scanner |
| Esc | release the mouse |
| **F1** or **`** | **dev mode panel** |

## Dev mode

F1 opens a panel with a slider for every constant: gun, reveal, audio, look and player. Changes apply live, and you can keep playing with the panel open (click the game). Hover over a name to see what it does. The panel also shows FPS and, for each artifact, how much of it is visible and its audio level.

- **Save** writes `tuning.cfg` in this folder. Those values override the defaults on every later run.
- **Defaults** goes back to the values in `scripts/tuning.gd`. **Reload saved** goes back to the last save.
- **Hide reveals** hides every artifact again.

To add a new constant, add one line to `SPECS` in `scripts/tuning.gd` and read it with `Tuning.v("section.name")`. It shows up in the panel automatically.

## How it works

### Menu, opening sequence and level 1

- `scripts/loading_bay.gd`: **level 1 and the ship's cabin**, all built from script. The bay is a 36 x 20 x 56 m octagonal hall along -z (cross-section `PROFILE`), with ribs every 6 m, the window in the left wall (the ribs are its mullions), "MERIDIAN LABS / LOADING BAY" on the right wall, the hexagonal docking door in the entry wall and a big hexagonal cargo door (shut) at the far end. Stand-in props: two tracks, carts with containers, a container stack, a console, an overhead crane. Light comes through the window from a shadowed `DirectionalLight3D` into haze (a `FogVolume` inside the bay only), plus a few strip lights and a red beacon. Outside: single-pixel stars, the Earth (`shaders/planet.gdshader`, generated texture) and the ship, which drifts across the window and explodes after you arrive (`bay.ship_delay`, `bay.ship_drift`). The gas motes (`shaders/motes.gdshader`) are decoration only: faint cyan points that wander and pulse like fireflies (`bay.mote_*`); they do not react to the gun. The cabin sits outside the entry wall and is deleted once the Cleaner is through and the station door has shut.
- `scripts/opening.gd`: **the menu and the opening sequence.** In the menu the camera sits in the cabin facing the door with "UNEARTH" painted on it; the player can look around within `menu.look_yaw` / `menu.look_pitch` and click the START or OPTIONS button on the panel right of the door (a ray from the crosshair against the buttons' own physics layer; the button under the crosshair lights up). START runs the sequence, which is one function of time `t` with every duration in the dev panel under `intro`: lights flicker and die -> shaking builds from light to violent (the lamp sparks back for instants) -> it stops dead -> both doors open -> the Cleaner is thrown through onto the bay floor (the picture is knocked dark) -> lies there -> gets up in two stages -> the player takes control and the gun comes up. The limited look stays active the whole time.
- `scripts/options_menu.gd`: mouse sensitivity, volume, fullscreen. Saved to `user://options.cfg`, separate from dev tuning.
- `scripts/level_kit.gd`: building blocks shared by script-built levels: `box`, `slab` (a box along a profile edge), `prism` (an extruded polygon), `wall_with_hex_hole`, `hex_ring`, `pipe`, `paint` (wall text), and the generated 64 px textures (`panel`, `deck`, `dark`, `rust`, `cargo`, `hazard`).
- `scripts/sfx.gd`: generated stand-in sounds (cabin hum, rumble, power-down, clunk, hiss, impact, room tone). **Not checked by ear.**
- `scripts/player.gd` has a `cinematic` mode (no walking; the camera takes an offset and tilt from the sequence) and the look limit. `scripts/ray_gun.gd` has `enabled` (holstered and unable to fire in the menu and sequence).

### The earlier prototype (`--level=hall`)

- `scripts/main.gd`: renders the 3D game into a low-res `SubViewport` (1/`look.pixel_scale` of the window, 400×225 by default) and scales it up with nearest-neighbour. Routes input, pushes Tuning values into the shaders and environment, and hosts capture mode (below).
- `scripts/level.gd`: the test hall, built from boxes with a generated concrete texture, plus where the artifacts are placed.
- `scripts/reveal_cloud.gd`: an artifact. Turns image + depth into a MultiMesh of points; depth maps are dark = near, and pixels brighter than `depth_threshold` are background. Each point stores the last time a ray hit it, and `shaders/reveal_points.gdshader` derives visibility from that age on the GPU, so fading costs nothing on the CPU. A spatial grid makes the ray tests cheap. The audio level comes from a histogram of hit times, using the same visibility curve as the shader. Right now the audio is a generated placeholder loop (drone + muffled "voice"); set `audio_path` to use a real file.
- `scripts/gas.gd` + `shaders/gas_points.gdshader`: **the first gas** (current focus; it's the only thing in the level right now, see `SHOW_EXHIBITS` in `level.gd` to bring the artifacts and figure back). It has a dense core (`gas.core`, `gas.core_size`) that moves like a ghost: it glides, hovers, darts and sometimes drifts up to the player (`gas.drift`, `gas.dart_speed`, `gas.hover`, `gas.curiosity`, `gas.wobble`). The rest of the gas thins out around the core and trails behind it: the core's recent path is kept as a 3.2 s trail, and each particle follows it with a lag that grows with its distance from the core (`gas.lag`). On top of that, particles spin slowly, swirl and the whole gas breathes. All of that motion runs in the shader, and ray hits evaluate the same maths on the CPU (`_trail_at`, `_particle_pos`), so keep the two in sync. The gas is invisible until a ray passes within `gas.hit_radius` of a particle; it then glows faint cyan for `gas.hold` s and fades over `gas.fade` s. Rays pass through the gas. `gas.show_all` shows the whole gas for debugging. **Coagulation:** hitting the gas builds energy (`gas.energy_needed` seconds of hits, leaking at `gas.energy_decay`; the glow brightens as it builds). When it's full the gas stops, pulls into a human figure (`gas.form` s), plays a short animation (`gas.perform` s), then bursts apart and drifts back into gas (`gas.disperse` s), with a `gas.cooldown` before it can charge again. `scripts/gas_figure.gd` holds the figure: an 11-bone boxy skeleton, the keyframed placeholder animation (head bowed, looks up, reaches a hand out, lets it fall) and the sampling of each particle's spot on the body. Each particle keeps a fixed bone + offset (stored in its instance basis and custom data), so the shader and the CPU hit tests place it on the animated figure the same way. `gas.figure_glow` sets how visible the figure is without being hit; `gas.face_offset` turns it away from the player. The dev panel shows what the core is doing (glide/hover/dart/approach).
- `scripts/figure.gd`: a wandering figure, the third kind of exhibit (after images, and before video). It's a boxy PS1-style person built from box-shaped body parts. Each part is a RevealCloud (`set_points()` with procedurally sampled, shade-baked points) parented to a bone, so revealed points stick to the body as it walks. The walk cycle is procedural, and poses update at `figure.anim_fps` for choppy PS1 animation while movement stays smooth. It wanders between random spots in the centre aisle and pauses to look around. There's one audio source for the whole body, driven by the share of the body that's visible.
- `scripts/ray_gun.gd`: spray of physics raycasts from the camera, stopped by walls, tested against every reveal cloud nearest-first so closer exhibits block farther ones. Draws 1px tracers (always from the live muzzle) and impact marks, plus a muzzle light.
- `shaders/psx_lit.gdshader`: PS1 vertex snapping and affine texture warping on world geometry. `shaders/lofi_post.gdshader` adds dither, colour depth reduction, grain and vignette.
- `scripts/tuning.gd`: an autoload holding every live constant.

## Capture mode (automated screenshots)

```bash
godot --path unearth-game -- --capture=renders/shot.png --pos=0,0.1,-27.5 --yaw=0 --pitch=2 --fire --sweep=16 --frames=420
```

This puts the player at `pos`, holds the trigger (`--fire`), wobbles the aim (`--sweep` degrees), saves the low-res frame, and prints each exhibit's visible % and audio %. Other options:

- `--strafe=m/s` moves the player sideways while firing.
- `--settle=N` releases the trigger N frames before the shot.
- `--tune=reveal.hold:60,figure.speed:0` overrides dev-mode values for that run.
- `--panel` saves the full window with the dev panel instead.
- `--fire_frames=N` (with `--fire`) only holds the trigger for the first N frames.
- `--series=N` also saves `name_000.png`, `name_001.png`... every N frames (turn them into a clip with ffmpeg).
- `--level=hall` loads the old test hall. Without it you get the menu; a capture then shows the cabin.
- `--state=play` skips the menu and sequence and starts standing in the bay.
- `--start` presses START on the first frame; `--intro_t=11.3` jumps to that second of the sequence.
- `--click` clicks whatever the crosshair is on (aim with `--yaw`/`--pitch`); `--options` opens the options screen and saves the full window.

## State (2026-11-09)

- **First menu and level.** Menu in the cabin, the opening sequence and the Loading Bay are in and verified with captures: `renders/menu_cabin.png`, `renders/opening_sequence_sheet.png`, `renders/loading_bay_sheet.png`. 120 fps in the bay. Checked by capture: the START button's click path, the options screen, every stage of the sequence, the ship drifting and exploding, the old hall still loading.
- **Not checked:** playing it by hand with a real mouse, and all sound by ear.
- **Not in level 1 yet:** the real (ghost) gas, anything to unearth, a way out through the far door, gun and footstep sounds. The Earth, the ship, the containers and the crane are stand-ins.

## State before that (2026-11-07)

- **Gas session:** the level holds only the first gas. Its dense core moves around like a ghost (glide, hover, dart, approach the player) with the rest trailing behind; it stays invisible and glows faint cyan where the gun's rays pass through it, then fades. Verified with captures (renders/gas_*.png): idle is invisible, hits land exactly on the beam even with the cloud moving fast, and 12,000 particles run at 120 fps while firing.
- **Coagulation (2026-11-07):** sustained hits charge the gas until it forms a human figure, plays a placeholder animation and disperses. Verified with captures (renders/gas_figure_*): the full cycle runs, the animation reads from the side, and hits land on the figure. In practice it takes about 5 s of firing with the defaults, because not every ray touches a particle.
- Next for the gas (director's direction): figures that replay specific memories (with audio).
- Working from before: the lo-fi render, walking, the gun, image artifacts with fading reveals and audio, the wandering figure, and the dev panel. The artifacts and figure are switched off (`SHOW_EXHIBITS`).
- Not done yet: video recordings, real audio, gun and footstep sounds, per-artifact depth thresholds. The placeholder audio has only been checked through its reported levels, not by ear.
