extends Node
## Live-tunable constants for the whole game (dev mode). Systems read them every
## frame with Tuning.v("section.name"), so edits in the dev panel (F1) apply
## immediately. Save writes res://tuning.cfg, which overrides the defaults below
## on the next run.

signal changed(key: String)

const SAVE_PATH := "res://tuning.cfg"

# key, default, min, max, step, help
const SPECS := [
	["gun.rate", 140.0, 5.0, 600.0, 1.0, "Rays fired per second while the trigger is held."],
	["gun.spread", 2.0, 0.0, 15.0, 0.1, "Cone half-angle of the spray, degrees."],
	["gun.range", 45.0, 2.0, 100.0, 0.5, "Max ray length, metres."],
	["gun.brush", 0.05, 0.005, 0.4, 0.005, "Radius around each ray that gets revealed, metres."],
	["gun.color", Color(1.0, 0.12, 0.08), null, null, null, "Colour of rays, sparks, muzzle light and the reveal flash."],
	["gun.color_random", 0.2, 0.0, 1.0, 0.01, "Per-ray colour variation."],
	["gun.tracer_life", 0.1, 0.0, 1.0, 0.01, "How long a ray's tracer line stays, seconds."],
	["gun.spark_life", 0.35, 0.0, 2.0, 0.01, "How long the impact mark stays, seconds."],
	["gun.light_energy", 2.0, 0.0, 10.0, 0.1, "Muzzle light brightness while firing."],
	["gun.light_range", 8.0, 0.0, 30.0, 0.5, "Muzzle light reach, metres."],
	["reveal.hold", 1.5, 0.0, 20.0, 0.05, "Seconds a hit point stays fully visible."],
	["reveal.fade", 2.5, 0.0, 20.0, 0.05, "Seconds it then takes to disappear."],
	["reveal.dissolve", 1.0, 0.0, 1.0, 0.01, "Fade style: 0 = dims to black, 1 = points drop out randomly."],
	["reveal.flash", 0.85, 0.0, 1.0, 0.01, "How strongly fresh hits glow in the gun colour."],
	["reveal.flash_decay", 3.0, 0.1, 20.0, 0.1, "How fast that glow settles to the true colour."],
	["reveal.point_scale", 1.2, 0.2, 4.0, 0.05, "Point size relative to the sample spacing."],
	["reveal.min_pixels", 1.0, 0.5, 4.0, 0.1, "Smallest on-screen point size, pixels."],
	["reveal.penetration", 0.1, 0.0, 1.0, 0.01, "How far past the first surface a ray keeps revealing, metres."],
	["audio.full_at", 0.3, 0.01, 1.0, 0.01, "Fraction of the artifact visible at which its audio reaches full volume."],
	["audio.curve", 1.5, 0.2, 4.0, 0.05, "Volume response: >1 stays quiet longer, <1 comes in fast."],
	["audio.attack", 0.25, 0.0, 5.0, 0.05, "Seconds for the volume to rise."],
	["audio.release", 1.5, 0.0, 10.0, 0.05, "Seconds for the volume to fall."],
	["audio.max_db", 0.0, -40.0, 12.0, 0.5, "Volume at full reveal, dB."],
	["figure.speed", 0.9, 0.0, 4.0, 0.05, "Walking speed of the wandering figure, m/s."],
	["figure.stride", 1.0, 0.0, 2.0, 0.05, "How big the walk cycle's swings are."],
	["figure.anim_fps", 12.0, 1.0, 60.0, 1.0, "Pose updates per second (low = choppy PS1 animation; movement stays smooth)."],
	["figure.pause", 4.0, 0.5, 20.0, 0.1, "Longest pause between walks, seconds."],
	["gas.count", 3000, 200, 20000, 100, "Number of particles (rebuilds the gas)."],
	["gas.size", 2.2, 0.3, 8.0, 0.1, "Overall size of the gas around its core, metres (rebuilds)."],
	["gas.squash", 0.55, 0.1, 1.5, 0.05, "Vertical size relative to horizontal: <1 = flatter (rebuilds)."],
	["gas.core", 0.45, 0.0, 1.0, 0.01, "Share of particles packed into the dense core; the rest thin out around it (rebuilds)."],
	["gas.core_size", 0.14, 0.02, 0.6, 0.01, "Size of the core relative to gas.size (rebuilds)."],
	["gas.lag", 0.9, 0.0, 1.5, 0.01, "How far the outer gas trails behind the moving core, seconds (0 = moves as one blob)."],
	["gas.drift", 0.6, 0.0, 3.0, 0.05, "Speed when the core glides around the hall, m/s."],
	["gas.dart_speed", 3.0, 0.0, 10.0, 0.1, "Speed of the core's sudden darts, m/s."],
	["gas.hover", 4.0, 0.5, 20.0, 0.1, "Longest time the core stops and hovers, seconds."],
	["gas.curiosity", 0.25, 0.0, 1.0, 0.01, "Chance that the core's next move is to drift up to the player."],
	["gas.wobble", 0.12, 0.0, 1.0, 0.01, "Restless wobble of the core, metres (it's never fully still)."],
	["gas.breath", 0.08, 0.0, 0.5, 0.01, "Slow swelling and shrinking of the whole gas."],
	["gas.spin", 0.06, 0.0, 1.0, 0.01, "Slow rotation of the gas about its core, rad/s."],
	["gas.churn", 0.35, 0.0, 3.0, 0.01, "Speed of the swirling flow inside the gas."],
	["gas.swirl", 0.3, 0.0, 2.0, 0.01, "How far particles get carried by the swirl, metres."],
	["gas.hit_radius", 0.18, 0.01, 1.0, 0.01, "Distance from a ray at which a particle gets charged and glows, metres."],
	["gas.color", Color(0.35, 0.9, 1.0), null, null, null, "Glow colour of charged particles."],
	["gas.glow", 0.3, 0.0, 3.0, 0.01, "Brightness of a charged particle (faint = low)."],
	["gas.flash", 0.8, 0.0, 4.0, 0.05, "Extra brightness right when a ray hits a particle."],
	["gas.flash_decay", 4.0, 0.1, 20.0, 0.1, "How fast that hit flash settles to the glow."],
	["gas.hold", 1.5, 0.0, 20.0, 0.05, "Seconds a charged particle keeps its full glow."],
	["gas.fade", 3.0, 0.0, 20.0, 0.05, "Seconds it then takes to go invisible again."],
	["gas.particle_size", 0.025, 0.005, 0.2, 0.005, "Particle size, metres."],
	["gas.min_pixels", 1.0, 0.5, 4.0, 0.1, "Smallest on-screen particle size, pixels."],
	["gas.flicker", 0.35, 0.0, 1.0, 0.01, "Per-particle twinkle of the glow."],
	["gas.energy_needed", 2.0, 0.1, 20.0, 0.1, "Seconds of hitting the gas it takes to make it coagulate into a figure."],
	["gas.energy_decay", 0.4, 0.0, 5.0, 0.05, "How fast built-up energy leaks away when you stop hitting it, per second."],
	["gas.charge_glow", 1.5, 0.0, 5.0, 0.05, "How much brighter the glow gets as energy builds."],
	["gas.form", 1.8, 0.1, 10.0, 0.05, "Seconds for the gas to pull together into the figure."],
	["gas.perform", 5.0, 0.5, 30.0, 0.1, "Seconds the figure's animation lasts."],
	["gas.disperse", 2.2, 0.1, 10.0, 0.05, "Seconds for the figure to burst apart and drift back into gas."],
	["gas.scatter", 1.2, 0.0, 5.0, 0.05, "How far the figure bursts outward as it disperses, metres."],
	["gas.figure_glow", 0.6, 0.0, 1.0, 0.01, "Visibility of the figure without being hit (0 = you have to keep firing to see it)."],
	["gas.figure_jitter", 0.025, 0.0, 0.3, 0.005, "How much the figure's particles shimmer, metres."],
	["gas.sway", 0.04, 0.0, 0.3, 0.005, "Idle sway of the figure's body, radians."],
	["gas.face_offset", 0.0, -180.0, 180.0, 1.0, "Which way the figure faces, degrees from facing the player (0 = towards you)."],
	["gas.cooldown", 4.0, 0.0, 30.0, 0.5, "Seconds after dispersing before energy can build again."],
	["gas.show_all", 0.0, 0.0, 1.0, 0.01, "Debug: show the whole gas without firing (0 = off, the normal game)."],
	["menu.look_yaw", 45.0, 0.0, 90.0, 1.0, "How far the player can look left and right in the menu and opening sequence, degrees."],
	["menu.look_pitch", 22.0, 0.0, 80.0, 1.0, "How far the player can look up and down in the menu and opening sequence, degrees."],
	["menu.fov", 58.0, 30.0, 110.0, 1.0, "Camera field of view in the cabin, degrees (narrower = the door feels closer)."],
	["cabin.lamp", 1.3, 0.0, 6.0, 0.05, "Brightness of the cabin's ceiling lamp."],
	["cabin.flicker", 0.6, 0.0, 1.0, 0.01, "How badly the cabin lamp flickers in the menu."],
	["intro.dark_time", 2.2, 0.8, 10.0, 0.1, "Seconds from pressing START (lights die) until the shaking begins."],
	["intro.shake_time", 7.0, 0.5, 30.0, 0.1, "Seconds the cabin shakes, building from light to violent."],
	["intro.shake_amount", 0.07, 0.0, 0.4, 0.005, "How hard the camera is thrown about at the peak of the shaking."],
	["intro.hold", 1.2, 0.0, 6.0, 0.05, "Seconds of stillness after the shaking stops, before the doors open."],
	["intro.door_time", 0.6, 0.1, 5.0, 0.05, "Seconds the doors take to open."],
	["intro.throw_time", 0.9, 0.2, 4.0, 0.05, "Seconds the Cleaner is in the air between the cabin and the bay floor."],
	["intro.down_time", 2.0, 0.0, 10.0, 0.1, "Seconds lying on the floor before getting up."],
	["intro.getup_time", 3.2, 0.5, 10.0, 0.1, "Seconds to get up; the player takes control at the end."],
	["bay.fog", 0.006, 0.0, 0.1, 0.001, "Distance fog in the loading bay (it is far bigger than the test hall)."],
	["bay.ambient", 0.2, 0.0, 2.0, 0.01, "Ambient light in the loading bay."],
	["bay.haze", 0.014, 0.0, 0.2, 0.001, "Haze in the air: makes the window light visible as shafts."],
	["bay.sun", 1.3, 0.0, 8.0, 0.05, "Brightness of the light coming through the window."],
	["bay.sun_height", 3.0, 0.0, 60.0, 0.5, "Angle of the window light, degrees: low = it lands on the far wall, high = on the floor."],
	["bay.motes", 700, 0, 6000, 50, "Number of glowing gas motes in the air (rebuilds)."],
	["bay.mote_glow", 0.6, 0.0, 3.0, 0.01, "Brightness of the motes."],
	["bay.mote_size", 0.03, 0.005, 0.3, 0.005, "Size of a mote, metres."],
	["bay.mote_drift", 0.7, 0.0, 4.0, 0.05, "How far a mote wanders from its spot, metres."],
	["bay.mote_speed", 0.25, 0.0, 2.0, 0.01, "How fast the motes wander and pulse."],
	["bay.mote_pulse", 0.8, 0.0, 1.0, 0.01, "Firefly pulsing: 0 = steady glow, 1 = each mote fades fully in and out."],
	["bay.ship_delay", 5.0, 0.0, 60.0, 0.5, "Seconds after the station door shuts before the ship drifts into view in the window."],
	["bay.ship_drift", 20.0, 2.0, 120.0, 0.5, "Seconds the ship drifts across the window before it explodes."],
	["look.pixel_scale", 4, 1, 8, 1, "Screen pixels per game pixel (internal resolution divisor)."],
	["look.snap", 1.0, 0.1, 2.0, 0.05, "Vertex snap grid relative to the internal resolution (lower = more wobble)."],
	["look.affine", 0.6, 0.0, 1.0, 0.01, "PS1 texture warping."],
	["look.color_levels", 20.0, 2.0, 64.0, 1.0, "Colour levels per channel."],
	["look.dither", 1.0, 0.0, 3.0, 0.05, "Ordered dither strength."],
	["look.grain", 0.035, 0.0, 0.3, 0.005, "Film grain."],
	["look.vignette", 0.45, 0.0, 2.0, 0.01, "Darkening at the screen edges."],
	["look.fog", 0.08, 0.0, 0.5, 0.005, "Fog density."],
	["look.ambient", 0.15, 0.0, 2.0, 0.01, "Ambient light."],
	["look.fov", 72.0, 30.0, 110.0, 1.0, "Camera field of view, degrees."],
	["player.walk", 3.2, 0.5, 12.0, 0.1, "Walk speed, m/s."],
	["player.run", 5.5, 0.5, 20.0, 0.1, "Run speed (Shift), m/s."],
	["player.mouse_sens", 0.22, 0.02, 1.0, 0.01, "Mouse sensitivity."],
	["player.bob", 0.03, 0.0, 0.2, 0.005, "Head bob amount, metres."],
]

var values := {}
var specs := {}
var order: Array[String] = []


func _ready() -> void:
	for s in SPECS:
		specs[s[0]] = s
		values[s[0]] = s[1]
		order.append(s[0])
	load_saved()


func v(key: String) -> Variant:
	return values[key]


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	changed.emit(key)


func reset_to_defaults() -> void:
	for key in order:
		set_value(key, specs[key][1])


func save() -> Error:
	var cfg := ConfigFile.new()
	for key in order:
		cfg.set_value(key.get_slice(".", 0), key.get_slice(".", 1), values[key])
	return cfg.save(SAVE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in order:
		var section := key.get_slice(".", 0)
		var name := key.get_slice(".", 1)
		if cfg.has_section_key(section, name):
			set_value(key, cfg.get_value(section, name))


## Shared clock for hit times and the shaders' reveal_now.
func now() -> float:
	return Time.get_ticks_usec() / 1000000.0
