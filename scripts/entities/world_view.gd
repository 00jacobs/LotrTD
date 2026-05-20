extends Node2D

## Map + path + test enemy (Week 3) + one tower that shoots in range (Week 4).

const FALLBACK_ANCHORS: PackedVector2Array = [
	Vector2(-40, 360),
	Vector2(320, 360),
	Vector2(320, 200),
	Vector2(960, 200),
	Vector2(960, 520),
	Vector2(1320, 520),
]

@export var background_color: Color = Color(0.12, 0.18, 0.12, 1.0)
@export var path_color: Color = Color(1.0, 0.45, 0.1, 1.0)
@export var path_width: float = 10.0
@export var viewport_size: Vector2 = Vector2(1280, 720)
@export var path_sample_step: float = 24.0

@export var enemy_speed: float = 140.0
@export var enemy_radius: float = 18.0
@export var enemy_color: Color = Color(1.0, 0.12, 0.12, 1.0)

@export var tower_position: Vector2 = Vector2(420, 260)
@export var tower_range: float = 280.0
@export var tower_radius: float = 26.0
@export var fire_interval: float = 0.4
@export var projectile_speed: float = 560.0
@export var projectile_radius: float = 7.0
@export var tower_color: Color = Color(0.25, 0.45, 0.85, 1.0)
@export var projectile_color: Color = Color(1.0, 0.95, 0.35, 1.0)
@export var show_tower_range: bool = true

var _enemy_path: Path2D
var _path_ready := false
var _enemy_distance: float = 0.0
var _enemy_finished := false
var _path_length: float = 0.0

var _fire_timer: float = 0.0
var _projectiles: Array[Dictionary] = []


func _ready() -> void:
	_enemy_path = get_node_or_null("PathFollowRoot/EnemyPath") as Path2D
	var tower_marker := get_node_or_null("TowerRoot/DemoTower") as Marker2D
	if tower_marker != null:
		tower_position = tower_marker.position
	_ensure_path_curve()
	_path_length = _polyline_length(_read_anchor_points())
	_path_ready = true
	_enemy_distance = 0.0
	_enemy_finished = false
	_fire_timer = 0.0
	_projectiles.clear()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _path_ready:
		return

	var anchors := _read_anchor_points()
	var enemy_pos := Vector2.ZERO

	if not _enemy_finished and _path_length > 0.0:
		_enemy_distance += enemy_speed * delta
		if _enemy_distance >= _path_length:
			_enemy_distance = _path_length
			_enemy_finished = true
			_projectiles.clear()
		enemy_pos = _sample_polyline_at(anchors, _enemy_distance)

		_fire_timer -= delta
		if tower_range > 0.0 and _fire_timer <= 0.0 and tower_position.distance_to(enemy_pos) <= tower_range:
			_fire_timer = fire_interval
			_projectiles.append({"pos": tower_position})

		for i in range(_projectiles.size() - 1, -1, -1):
			var p: Dictionary = _projectiles[i]
			var pos: Vector2 = p["pos"]
			var to_enemy := enemy_pos - pos
			var dist := to_enemy.length()
			if dist < enemy_radius + projectile_radius:
				_projectiles.remove_at(i)
				continue
			if dist > 0.001:
				p["pos"] = pos + to_enemy.normalized() * projectile_speed * delta

	queue_redraw()


func _ensure_path_curve() -> void:
	if _enemy_path == null:
		push_warning("WorldView: PathFollowRoot/EnemyPath not found.")
		return
	if _enemy_path.curve == null:
		_enemy_path.curve = Curve2D.new()
	var curve := _enemy_path.curve
	if curve.get_point_count() >= 2 and curve.get_baked_length() > 0.0:
		return
	curve.clear_points()
	for anchor in FALLBACK_ANCHORS:
		curve.add_point(anchor)
	curve.bake_interval = 8.0
	curve.get_baked_points()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), background_color)
	if not _path_ready:
		return

	var anchors := _read_anchor_points()
	var path_points := _densify_polyline(anchors, path_sample_step)
	if path_points.size() >= 2:
		draw_polyline(path_points, path_color, path_width, true)

	if show_tower_range:
		draw_arc(tower_position, tower_range, 0.0, TAU, 96, Color(0.4, 0.65, 1.0, 0.22), 2.0, true)

	draw_circle(tower_position, tower_radius + 3.0, Color(0.08, 0.1, 0.14, 1.0))
	draw_circle(tower_position, tower_radius, tower_color)

	for p in _projectiles:
		draw_circle(p["pos"], projectile_radius + 1.0, Color(0.1, 0.08, 0.02, 0.6))
		draw_circle(p["pos"], projectile_radius, projectile_color)

	if not _enemy_finished:
		var enemy_pos := _sample_polyline_at(anchors, _enemy_distance)
		draw_circle(enemy_pos, enemy_radius, enemy_color)
		draw_arc(enemy_pos, enemy_radius, 0.0, TAU, 32, Color.WHITE, 2.0)


func _read_anchor_points() -> PackedVector2Array:
	if _enemy_path != null and _enemy_path.curve != null:
		var curve := _enemy_path.curve
		if curve.get_point_count() >= 2:
			var anchors := PackedVector2Array()
			for i in curve.get_point_count():
				anchors.append(curve.get_point_position(i))
			return anchors
	return FALLBACK_ANCHORS


func _polyline_length(anchors: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, anchors.size()):
		total += anchors[i].distance_to(anchors[i - 1])
	return total


func _sample_polyline_at(anchors: PackedVector2Array, dist: float) -> Vector2:
	if anchors.is_empty():
		return Vector2.ZERO
	if anchors.size() == 1:
		return anchors[0]
	var remaining := dist
	for i in range(1, anchors.size()):
		var from: Vector2 = anchors[i - 1]
		var to: Vector2 = anchors[i]
		var segment_length := from.distance_to(to)
		if segment_length < 0.001:
			continue
		if remaining <= segment_length:
			return from.lerp(to, remaining / segment_length)
		remaining -= segment_length
	return anchors[anchors.size() - 1]


func _densify_polyline(anchors: PackedVector2Array, step: float) -> PackedVector2Array:
	if anchors.size() < 2:
		return anchors
	var result := PackedVector2Array()
	result.append(anchors[0])
	for i in range(1, anchors.size()):
		var from: Vector2 = anchors[i - 1]
		var to: Vector2 = anchors[i]
		var segment: Vector2 = to - from
		var dist := segment.length()
		if dist < 0.001:
			continue
		var dir := segment / dist
		var traveled := step
		while traveled < dist:
			result.append(from + dir * traveled)
			traveled += step
		result.append(to)
	return result
