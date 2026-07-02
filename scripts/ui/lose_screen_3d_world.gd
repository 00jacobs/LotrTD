extends Node3D

## Builds and animates the 3D defeat backdrop (CC0 shaders + CC0 audio).

@export var fire_count: int = 22
@export var lava_inset: float = 0.9
@export var lava_y_lift_min: float = 0.04
@export var lava_y_lift_max: float = 0.22
@export var eye_world_z: float = 3.15
@export var fire_behind_eye_margin: float = 1.85
@export var fire_quad_scale: Vector3 = Vector3(1.1, 1.55, 1.0)
@export var camera_fov: float = 56.0

@onready var _camera: Camera3D = $Camera3D
@onready var _eye_pivot: Node3D = $EyePivot
@onready var _eye_mesh: MeshInstance3D = $EyePivot/EyeMesh
@onready var _eye_glow: OmniLight3D = $EyePivot/EyeGlow
@onready var _lava_ground: MeshInstance3D = $LavaGround
@onready var _fire_root: Node3D = $FireRoot
@onready var _fire_template: MeshInstance3D = $FireRoot/FireTemplate
@onready var _fire_crackle: AudioStreamPlayer = $FireCrackle

var _eye_material: ShaderMaterial
var _fires: Array[Dictionary] = []
var _time := 0.0
var _active := false
var _eye_open := 0.0


func _ready() -> void:
	if _eye_mesh != null:
		_eye_material = _eye_mesh.get_surface_override_material(0) as ShaderMaterial
		if _eye_material != null:
			_eye_material.set_shader_parameter("eye_open", 0.35)
	_assign_fire_noise(_fire_template)
	_build_fire_field()
	_frame_camera()
	if _fire_template != null:
		_fire_template.visible = false
	if _fire_crackle != null:
		_fire_crackle.stream_paused = true


func play() -> void:
	_active = true
	_time = 0.0
	_eye_open = 0.35
	if _eye_material != null:
		_eye_material.set_shader_parameter("eye_open", _eye_open)
	if _fire_crackle != null:
		if not _fire_crackle.playing:
			_fire_crackle.play()
		_fire_crackle.stream_paused = false
	set_process(true)


func stop() -> void:
	_active = false
	if _fire_crackle != null:
		_fire_crackle.stream_paused = true
	set_process(false)


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	_eye_open = clampf(_eye_open + delta * 0.85, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 1.85)
	var pulse_deep := 0.5 + 0.5 * sin(_time * 0.72 + 1.1)
	if _eye_material != null:
		_eye_material.set_shader_parameter("eye_open", _eye_open)
		_eye_material.set_shader_parameter("pulse", pulse)
		_eye_material.set_shader_parameter("pulse_deep", pulse_deep)
	if _eye_glow != null:
		_eye_glow.light_energy = lerpf(0.02, 0.14, _eye_open) * (0.88 + pulse * 0.05 + pulse_deep * 0.03)
	if _eye_pivot != null:
		_eye_pivot.rotation.y = sin(_time * 0.35) * 0.06
	_animate_fires()


func _build_fire_field() -> void:
	if _fire_template == null or _fire_root == null:
		return
	var template_mat := _fire_template.get_surface_override_material(0) as ShaderMaterial
	for i in fire_count:
		var fire := _fire_template.duplicate() as MeshInstance3D
		fire.name = "Fire_%d" % i
		fire.visible = true

		var spawn := _random_point_on_lava()
		fire.position = spawn
		fire.rotation.y = randf_range(-0.22, 0.22)
		var depth_scale := _depth_scale_for_z(spawn.z)
		fire.scale = fire_quad_scale * Vector3(
			randf_range(0.82, 1.28) * depth_scale,
			randf_range(0.88, 1.42) * depth_scale,
			1.0
		)

		var entry := _configure_fire(fire, template_mat, {
			"height_min": 2.2, "height_max": 4.2,
			"width_min": 0.85, "width_max": 1.85,
			"emission_min": 9.5, "emission_max": 15.5,
		})
		_fires.append(entry)
		_fire_root.add_child(fire)


func _configure_fire(fire: MeshInstance3D, template_mat: ShaderMaterial, cfg: Dictionary) -> Dictionary:
	var mat: ShaderMaterial = null
	var base_emission := 10.0
	if template_mat != null:
		mat = template_mat.duplicate() as ShaderMaterial
		base_emission = randf_range(float(cfg["emission_min"]), float(cfg["emission_max"]))
		mat.set_shader_parameter("fire_height", randf_range(float(cfg["height_min"]), float(cfg["height_max"])))
		mat.set_shader_parameter("fire_width", randf_range(float(cfg["width_min"]), float(cfg["width_max"])))
		mat.set_shader_parameter("time_scale", randf_range(0.022, 0.055))
		mat.set_shader_parameter("time_offset", randf_range(0.0, 24.0))
		mat.set_shader_parameter("wobble_speed", randf_range(4.0, 11.0))
		mat.set_shader_parameter("wobble_strength", randf_range(1.2, 2.8))
		mat.set_shader_parameter("noise_threshold", randf_range(0.36, 0.5))
		mat.set_shader_parameter("emission_strength", base_emission)
		fire.set_surface_override_material(0, mat)
		_assign_fire_noise(fire)

	return {
		"mat": mat,
		"phase": randf() * TAU,
		"pulse_speed": randf_range(0.9, 3.8),
		"base_emission": base_emission,
		"flicker": randf_range(0.12, 0.32),
	}


func _animate_fires() -> void:
	for entry: Dictionary in _fires:
		var mat: ShaderMaterial = entry.get("mat") as ShaderMaterial
		if mat == null:
			continue
		var phase: float = float(entry["phase"])
		var pulse_speed: float = float(entry["pulse_speed"])
		var base_emission: float = float(entry["base_emission"])
		var flicker: float = float(entry["flicker"])
		var pulse := 0.68 + flicker * sin(_time * pulse_speed + phase)
		pulse += 0.12 * sin(_time * pulse_speed * 2.7 + phase * 1.9)
		mat.set_shader_parameter("emission_strength", base_emission * pulse)


func _assign_fire_noise(fire_mesh: MeshInstance3D) -> void:
	if fire_mesh == null:
		return
	var mat := fire_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		return
	var noise: NoiseTexture3D = mat.get_shader_parameter("sample_noise")
	if noise == null and _fire_template != null:
		var template_mat := _fire_template.get_surface_override_material(0) as ShaderMaterial
		if template_mat != null:
			noise = template_mat.get_shader_parameter("sample_noise")
	if noise != null:
		mat.set_shader_parameter("sample_noise", noise)


func _random_point_on_lava() -> Vector3:
	var lava_center := _lava_ground.position if _lava_ground != null else Vector3(0.0, -2.05, -1.5)
	var lava_size := Vector2(26.0, 12.0)
	if _lava_ground != null and _lava_ground.mesh is PlaneMesh:
		lava_size = (_lava_ground.mesh as PlaneMesh).size
	var half_x := lava_size.x * 0.5 * lava_inset
	var half_z := lava_size.y * 0.5 * lava_inset
	var x := randf_range(-half_x, half_x)
	var z_offset := randf_range(-half_z, half_z)
	var max_z := eye_world_z - fire_behind_eye_margin
	var world_z := minf(lava_center.z + z_offset, max_z)
	var y := randf_range(lava_y_lift_min, lava_y_lift_max)
	return Vector3(lava_center.x + x, lava_center.y + y, world_z)


func _depth_scale_for_z(world_z: float) -> float:
	if _lava_ground == null:
		return 1.0
	var lava_z := _lava_ground.position.z
	var lava_half_z := 6.0
	if _lava_ground.mesh is PlaneMesh:
		lava_half_z = (_lava_ground.mesh as PlaneMesh).size.y * 0.5
	var t := inverse_lerp(lava_z + lava_half_z, lava_z - lava_half_z, world_z)
	return lerpf(0.82, 1.18, clampf(t, 0.0, 1.0))


func _frame_camera() -> void:
	if _camera == null:
		return

	var eye_pos := _eye_pivot.global_position if _eye_pivot != null else Vector3(0.0, 1.55, 3.15)
	var lava_pos := _lava_ground.global_position if _lava_ground != null else Vector3(0.0, -2.05, -1.5)

	# Keep eye in the upper third; lava stays visible but de-emphasized.
	var look_target := Vector3(
		0.0,
		lerpf(lava_pos.y + 0.35, eye_pos.y, 0.78),
		lerpf(lava_pos.z, eye_pos.z, 0.62)
	)

	_camera.global_position = Vector3(0.0, 0.72, 6.45)
	_camera.fov = camera_fov
	_camera.look_at(look_target, Vector3.UP)

