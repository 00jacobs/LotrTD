extends Node2D

## Moves along EnemyPath. Uses fallback anchors when the baked curve length is 0.

signal reached_exit

const FALLBACK_ANCHORS: PackedVector2Array = [
	Vector2(-40, 360),
	Vector2(320, 360),
	Vector2(320, 200),
	Vector2(960, 200),
	Vector2(960, 520),
	Vector2(1320, 520),
]

@export var speed: float = 140.0
@export var body_radius: float = 18.0
@export var body_color: Color = Color(1.0, 0.12, 0.12, 1.0)

var _path: Path2D
var _distance: float = 0.0
var _total_length: float = 0.0
var _use_fallback: bool = false


func setup(path: Path2D) -> void:
	_path = path
	_distance = 0.0
	_use_fallback = _needs_fallback()
	_total_length = _compute_total_length()
	z_index = 10
	_apply_position()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _total_length <= 0.0:
		return

	_distance += speed * delta
	if _distance >= _total_length:
		_distance = _total_length
		_apply_position()
		queue_redraw()
		reached_exit.emit()
		queue_free()
		return

	_apply_position()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 32, Color.WHITE, 2.0)


func _needs_fallback() -> bool:
	if _path == null or _path.curve == null:
		return true
	return _path.curve.get_baked_length() <= 0.0


func _compute_total_length() -> float:
	if not _use_fallback:
		return _path.curve.get_baked_length()
	return _polyline_length(FALLBACK_ANCHORS)


func _apply_position() -> void:
	global_position = _sample_at_distance(_distance)


func _sample_at_distance(dist: float) -> Vector2:
	if not _use_fallback:
		return _path.to_global(_path.curve.sample_baked(dist))
	return _sample_fallback(dist)


func _sample_fallback(dist: float) -> Vector2:
	var remaining: float = dist
	for i in range(1, FALLBACK_ANCHORS.size()):
		var from: Vector2 = _path.to_global(FALLBACK_ANCHORS[i - 1] as Vector2)
		var to: Vector2 = _path.to_global(FALLBACK_ANCHORS[i] as Vector2)
		var segment_length: float = from.distance_to(to)
		if segment_length < 0.001:
			continue
		if remaining <= segment_length:
			return from.lerp(to, remaining / segment_length)
		remaining -= segment_length
	return _path.to_global(FALLBACK_ANCHORS[FALLBACK_ANCHORS.size() - 1] as Vector2)


func _polyline_length(anchors: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, anchors.size()):
		total += (anchors[i] as Vector2).distance_to(anchors[i - 1] as Vector2)
	return total
