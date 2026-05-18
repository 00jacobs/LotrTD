extends Node2D

## Week 3: spawns one test enemy on the path. Waves will replace this later.

const FALLBACK_ANCHORS: PackedVector2Array = [
	Vector2(-40, 360),
	Vector2(320, 360),
	Vector2(320, 200),
	Vector2(960, 200),
	Vector2(960, 520),
	Vector2(1320, 520),
]

@export var enemy_scene: PackedScene


func _ready() -> void:
	call_deferred("_spawn_test_enemy")


func _spawn_test_enemy() -> void:
	if enemy_scene == null:
		push_error("EnemySpawner: assign enemy_scene in the inspector.")
		return

	var path := get_node_or_null("../PathFollowRoot/EnemyPath") as Path2D
	if path == null:
		push_error("EnemySpawner: could not find PathFollowRoot/EnemyPath.")
		return

	_ensure_path_curve(path)

	var enemy := enemy_scene.instantiate()
	add_child(enemy)
	if enemy.has_method("setup"):
		enemy.setup(path)
	else:
		push_error("EnemySpawner: enemy scene is missing setup(path) method.")


func _ensure_path_curve(path: Path2D) -> void:
	if path.curve == null:
		path.curve = Curve2D.new()
	var curve := path.curve
	if curve.get_point_count() >= 2 and curve.get_baked_length() > 0.0:
		return
	curve.clear_points()
	for anchor in FALLBACK_ANCHORS:
		curve.add_point(anchor)
	curve.bake_interval = 8.0
	curve.get_baked_points()
