extends CharacterBody3D
## First-person walker. Mouse look is fed in by main.gd via look(), because the
## player lives inside the SubViewport and main.gd owns input routing.

const RayGun := preload("res://scripts/ray_gun.gd")
const GRAVITY := 18.0
const JUMP_SPEED := 4.5

var head: Node3D
var camera: Camera3D
var gun: Node3D
var _bob_t := 0.0

# Set by scripts/opening.gd while it owns the camera.
var cinematic := false               # no walking or gravity; position is set from outside
var look_limit := Vector2.ZERO       # degrees (yaw, pitch) the player may look away from look_center; zero = free
var look_center := Vector2.ZERO      # radians (yaw, pitch)
var cine_offset := Vector3.ZERO      # camera offset, metres (shake, falling, getting up)
var cine_tilt := Vector3.ZERO        # extra camera rotation, radians (pitch, yaw, roll)
var fov_override := 0.0              # degrees; 0 = use look.fov

# Set by scripts/main.gd (touch controls) and scripts/game.gd.
var touch_active := false            # playing by touch: no mouse capture needed
var touch_move := Vector2.ZERO       # thumbstick, x right, y back (like Input.get_vector)
var shake := 0.0                     # camera shake while playing


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	head = Node3D.new()
	head.position.y = 1.55
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 4000.0   # the bay window looks out on stars and the Earth
	camera.current = true
	head.add_child(camera)
	gun = RayGun.new()
	camera.add_child(gun)


func look(relative: Vector2) -> void:
	look_radians(relative * float(Tuning.v("player.mouse_sens")) * 0.01)


## Turn by an angle (x = right, y = down), radians.
func look_radians(turn: Vector2) -> void:
	rotate_y(-turn.x)
	head.rotation.x = clampf(head.rotation.x - turn.y, -1.5, 1.5)
	if look_limit != Vector2.ZERO:
		var yaw := deg_to_rad(look_limit.x)
		var pitch := deg_to_rad(look_limit.y)
		rotation.y = look_center.x + clampf(angle_difference(look_center.x, rotation.y), -yaw, yaw)
		head.rotation.x = clampf(head.rotation.x, look_center.y - pitch, look_center.y + pitch)


func set_aim(yaw_deg: float, pitch_deg: float) -> void:
	rotation.y = deg_to_rad(yaw_deg)
	head.rotation.x = deg_to_rad(pitch_deg)


func _physics_process(delta: float) -> void:
	camera.fov = fov_override if fov_override > 0.0 else float(Tuning.v("look.fov"))
	if cinematic:
		camera.position = cine_offset + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.3
		camera.rotation = cine_tilt
		return
	camera.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.12
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or touch_active
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif playing and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if playing else Vector2.ZERO
	input = (input + touch_move).limit_length(1.0)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).limit_length(1.0)
	var speed: float = Tuning.v("player.run") if Input.is_action_pressed("run") else Tuning.v("player.walk")
	var blend := 1.0 - exp(-(10.0 if is_on_floor() else 2.0) * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, blend)
	velocity.z = lerpf(velocity.z, dir.z * speed, blend)
	move_and_slide()

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.2:
		_bob_t += delta * flat_speed * 2.4
	var bob: float = Tuning.v("player.bob")
	camera.position = Vector3(cos(_bob_t * 0.5) * bob * 0.6, absf(sin(_bob_t)) * bob, 0)
