extends Node2D

## Draws map, path, and Week 3 test enemy (all via _draw — same path that already works).

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

var _enemy_path: Path2D
var _path_ready := false
var _enemy_distance: float = 0.0
var _enemy_finished := false
var _path_length: float = 0.0


func _ready() -> void:
	_enemy_path = get_node_or_null("PathFollowRoot/EnemyPath") as Path2D
	_ensure_path_curve()
	_path_length = _polyline_length(_read_anchor_points())
	_path_ready = true
	_enemy_distance = 0.0
	_enemy_finished = false
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _path_ready or _enemy_finished or _path_length <= 0.0:
		return
	_enemy_distance += enemy_speed * delta
	if _enemy_distance >= _path_length:
		_enemy_distance = _path_length
		_enemy_finished = true
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
