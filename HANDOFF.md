# Handoff: Unearth (written 2026-11-06)

**Newer than this file:** the menu, opening sequence and level 1 (2026-11-09) are described in README.md, sections "Menu, opening sequence and level 1" and "State".

Summary of the first working session (2026-11-02 to 2026-11-05), for picking up in a new chat. Read this first, then [README.md](README.md) (how to run it, controls, architecture), [ideas/unearth-game.md](../ideas/unearth-game.md) (pitch, references, plan) and [LEARNINGS.md](../LEARNINGS.md) (Godot section).

## How to work with the director

- They direct; I engineer. **Focus on implementation and hold back on creative suggestions** (story, setting, themes) unless asked. When their direction comes out jumbled, restate it back clearly.
- They want to tune effects themselves: **every new constant goes into dev mode** (one line in `SPECS` in `scripts/tuning.gd`).
- Verify visually with capture-mode screenshots before handing over, and send them the images.

## What exists

| Folder | What | State |
|---|---|---|
| `~/Code/prism` | The original web prototype (Three.js, Jan 2025, never committed) | Left untouched |
| `unearth/` | Copy of prism: the web ray-gun scanner over image + depth point clouds | Runs with `npm run dev --prefix unearth` (port 5199). Not being developed further; it's the reference. |
| `unearth-game/` | **The game, Godot 4.7.2** (installed via `brew install --cask godot`) | First playable prototype, active |

Ideas INDEX has both rows: `unearth` (active, the prototype) and `unearth-game` (active).

**Run it:** `godot --path unearth-game` from `create/`. Click to play, WASD/Shift/Space to move, hold left mouse to fire, Esc to release the mouse, **F1 for dev mode**.

## Decisions made

- **Engine: Godot 4**, because scenes and scripts are text and can be generated and edited by script.
- **Aesthetic references: Iron Lung** (Unity, solo developer, you only see the world through a bad camera) **and Lorn's Lure** (Unity, solo developer, a lo-fi brutalist megastructure). The director confirmed these two are enough; the plane-maintenance game was dropped.
- **Look:** render at 400×225 in a SubViewport scaled up with nearest-neighbour, PS1 vertex snapping and affine warping on geometry, then a post pass with dither, colour reduction, grain and vignette. A dark, foggy concrete hall; the gun's muzzle light is the main light source.
- **Reveal mechanic (director's first draft):** exhibits are completely invisible and silent. Spraying shows parts of them. Each ray has a lasting effect: points stay for `reveal.hold`, then fade or dissolve over `reveal.fade`. **Audio fades in the more of the exhibit is visible, and fades out as the reveal decays.**
- **Dev mode is essential** (director): sliders for all constants, applied live while playing, saved to `unearth-game/tuning.cfg`. Nothing has been saved yet, so the defaults are in use.

## Built so far (all verified with screenshots)

1. A lo-fi render, a first-person controller, and the test hall (`scripts/level.gd`).
2. **Ray gun** (`scripts/ray_gun.gd`): a spray of raycasts, 1px tracers, impact marks and a muzzle light. Tracers are drawn from the live muzzle, which fixes the director's bug report about beams detaching when moving while firing. Clouds are tested nearest-first so near exhibits block far ones.
3. **Image exhibits** (`scripts/reveal_cloud.gd`): the 8 image + depth pairs from the prototype (`assets/relics/`; depth maps are dark = near, and pixels brighter than 0.65 are background), placed on the hall walls. Visibility is computed on the GPU from per-point hit times (`shaders/reveal_points.gdshader`).
4. **Audio driven by the reveal:** currently a generated placeholder loop for each exhibit (a drone plus a muffled "voice"). **Not yet checked by ear, only through the reported levels.**
5. **Dev panel** (`scripts/dev_panel.gd`): gun / reveal / audio / figure / look / player sections, plus live visible % and audio % for each exhibit.
6. **Wandering figure** (`scripts/figure.gd`), added at the director's request to try a moving video-game character as an exhibit. It's a procedural boxy PS1 person: box-shaped body parts covered in points, each parented to an animated bone. It has a procedural walk cycle with choppy pose updates (`figure.anim_fps`), wanders the centre aisle, and has one audio source for the whole body.
7. **Capture mode** for automated screenshots: `--capture --pos --yaw --pitch --fire --sweep --strafe --settle --frames --tune=key:value --panel` (see README).

## Next up

1. **The video recording reveal (the agreed next milestone).** A video with a depth map shown as moving points, with audio. You must keep firing to watch and hear it. Planned approach (in the idea file):
   - Placeholder clip: the **director OK'd downloading an openly licensed clip with speech**; say exactly what was downloaded.
   - Generate depth for each frame with Video Depth Anything. **Ask before downloading the model weights** (roughly 100–400 MB).
   - ffmpeg packs colour and depth side by side into a low-res `.ogv` (Godot only plays Theora natively), with the audio as a separate `.ogg`.
   - A GPU point grid samples the video texture, with the reveal and audio logic reused from the static exhibits.
   - **Open question to ask the director:** when you stop firing, does the recording pause, or keep playing so you miss part of it? It isn't answered yet; build it so both work.
2. Known rough edges:
   - Every image uses the same depth threshold, and some artifacts sit off-centre on their walls.
   - The gun model is still a bit big.
   - No footstep or gun sound effects.
   - The figure walks through the player and may clip the tiger-skull plinth.
3. Offered but not decided: replace the procedural figure with a real rigged character. That's an asset download, so ask first.

## Gotchas learned (details in LEARNINGS.md)

- **Metal, macOS: a point shader drew nothing, with no error.** The cause was PS1 vertex snapping on quads of about 1px. Points aren't snapped any more. Debug shaders by bisecting with a magenta `ALBEDO`.
- GDScript `:=` can't infer types from Array or Dictionary values; annotate them.
- A capture needs a real window (a window pops up briefly), because headless uses a dummy renderer.
