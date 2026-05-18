extends Node2D

## Draws map background + enemy path on World.
## Path2D curve data from .tscn can fail to load; we rebuild anchors in _ready() if needed.

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

var _enemy_path: Path2D
var _path_ready := false


func _ready() -> void:
	_enemy_path = get_node_or_null("PathFollowRoot/EnemyPath") as Path2D
	_ensure_path_curve()
	_path_ready = true
	queue_redraw()


func _ensure_path_curve() -> void:
	if _enemy_path == null:
		push_warning("WorldView: PathFollowRoot/EnemyPath not found; drawing fallback path only.")
		return
	if _enemy_path.curve == null:
		_enemy_path.curve = Curve2D.new()
	var curve := _enemy_path.curve
	if curve.get_point_count() >= 2:
		return
	curve.clear_points()
	for anchor in FALLBACK_ANCHORS:
		curve.add_point(anchor)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), background_color)
	if not _path_ready:
		return

	var path_points := _build_draw_points()
	if path_points.size() < 2:
		return
	draw_polyline(path_points, path_color, path_width, true)


func _build_draw_points() -> PackedVector2Array:
	# PathFollowRoot and EnemyPath start at (0, 0), so curve points == World coordinates.
	return _densify_polyline(_read_anchor_points(), path_sample_step)


func _read_anchor_points() -> PackedVector2Array:
	if _enemy_path != null and _enemy_path.curve != null:
		var curve := _enemy_path.curve
		if curve.get_point_count() >= 2:
			var anchors := PackedVector2Array()
			for i in curve.get_point_count():
				anchors.append(curve.get_point_position(i))
			return anchors
	return FALLBACK_ANCHORS


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
