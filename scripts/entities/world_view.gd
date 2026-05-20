extends Node2D

## Weeks 3–6: map, path, waves (button + timer spawns), multi-enemy, tower, gold.

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
@export var enemy_max_hp: float = 120.0
@export var gold_per_kill: int = 15

@export var wave_enemy_count: int = 6
@export var wave_spawn_interval: float = 0.85

@export var tower_position: Vector2 = Vector2(420, 260)
@export var tower_range: float = 280.0
@export var tower_radius: float = 26.0
@export var fire_interval: float = 0.4
@export var projectile_speed: float = 560.0
@export var projectile_radius: float = 7.0
@export var projectile_damage: float = 28.0
@export var tower_color: Color = Color(0.25, 0.45, 0.85, 1.0)
@export var projectile_color: Color = Color(1.0, 0.95, 0.35, 1.0)
@export var show_tower_range: bool = true

var _enemy_path: Path2D
var _path_ready := false
var _path_length: float = 0.0

var _wave_running := false
var _spawns_remaining: int = 0
var _spawn_timer: float = 0.0
var _enemies: Array[Dictionary] = []

var _fire_timer: float = 0.0
var _projectiles: Array[Dictionary] = []

var _gold: int = 0
var _gold_label: Label
var _wave_label: Label
var _start_wave_button: Button


func _ready() -> void:
	_gold_label = get_node_or_null("../../UI/TopBar/GoldLabel") as Label
	_wave_label = get_node_or_null("../../UI/TopBar/WaveLabel") as Label
	_start_wave_button = get_node_or_null("../../UI/ActionPanel/ActionVBox/StartWaveButton") as Button
	if _start_wave_button != null:
		# Use button_up so disabling the button does not leave a stuck "pressed" style (weird overlay).
		_start_wave_button.button_up.connect(_on_start_wave_button_up)

	_enemy_path = get_node_or_null("PathFollowRoot/EnemyPath") as Path2D
	var tower_marker: Marker2D = get_node_or_null("TowerRoot/DemoTower") as Marker2D
	if tower_marker != null:
		tower_position = tower_marker.position
	_ensure_path_curve()
	_path_length = _polyline_length(_read_anchor_points())
	_path_ready = true
	_wave_running = false
	_spawns_remaining = 0
	_spawn_timer = 0.0
	_enemies.clear()
	_fire_timer = 0.0
	_projectiles.clear()
	_gold = 0
	_update_gold_label()
	_update_wave_ui()
	_update_start_button()
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_try_start_wave()


func _on_start_wave_button_up() -> void:
	_try_start_wave()


func _try_start_wave() -> void:
	if _wave_running:
		return
	_begin_wave()


func _begin_wave() -> void:
	_wave_running = true
	_spawns_remaining = wave_enemy_count
	_spawn_timer = 0.0
	_enemies.clear()
	_projectiles.clear()
	_fire_timer = 0.0
	_update_wave_ui()
	_update_start_button()
	queue_redraw()


func _process(delta: float) -> void:
	if not _path_ready:
		return

	if not _wave_running:
		queue_redraw()
		return

	var anchors := _read_anchor_points()

	# Timed spawns
	if _spawns_remaining > 0:
		_spawn_timer -= delta
		while _spawn_timer <= 0.0 and _spawns_remaining > 0:
			_enemies.append({"dist": 0.0, "hp": enemy_max_hp})
			_spawns_remaining -= 1
			_spawn_timer += wave_spawn_interval

	_move_enemies(delta, anchors)

	var target_pos: Variant = _closest_enemy_in_range(anchors, tower_position, tower_range)

	_fire_timer -= delta
	if target_pos != null and tower_range > 0.0 and _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_projectiles.append({"pos": tower_position})

	_update_projectiles(delta, anchors)

	if _spawns_remaining <= 0 and _enemies.is_empty() and _projectiles.is_empty():
		_wave_running = false
		_update_wave_ui()
		_update_start_button()
	else:
		_update_wave_ui()

	queue_redraw()


func _move_enemies(delta: float, _anchors: PackedVector2Array) -> void:
	for i in range(_enemies.size() - 1, -1, -1):
		var e: Dictionary = _enemies[i]
		var hp: float = float(e["hp"])
		if hp <= 0.0:
			_enemies.remove_at(i)
			continue
		var dist: float = float(e["dist"])
		dist += enemy_speed * delta
		if dist >= _path_length:
			_enemies.remove_at(i)
			continue
		e["dist"] = dist


func _closest_enemy_in_range(anchors: PackedVector2Array, from: Vector2, max_range: float) -> Variant:
	var best := Vector2.ZERO
	var best_d := INF
	for e: Dictionary in _enemies:
		var hp: float = float(e["hp"])
		if hp <= 0.0:
			continue
		var pos: Vector2 = _sample_polyline_at(anchors, float(e["dist"]))
		var d: float = from.distance_to(pos)
		if d <= max_range and d < best_d:
			best_d = d
			best = pos
	if best_d < INF:
		return best
	return null


func _closest_enemy_to_point(anchors: PackedVector2Array, point: Vector2) -> Variant:
	var best := Vector2.ZERO
	var best_d := INF
	for e: Dictionary in _enemies:
		var hp: float = float(e["hp"])
		if hp <= 0.0:
			continue
		var pos: Vector2 = _sample_polyline_at(anchors, float(e["dist"]))
		var d: float = point.distance_to(pos)
		if d < best_d:
			best_d = d
			best = pos
	if best_d < INF:
		return best
	return null


func _damage_enemy_near(anchors: PackedVector2Array, world_point: Vector2, max_dist: float, amount: float) -> void:
	var best_i := -1
	var best_d := max_dist
	for i in _enemies.size():
		var e: Dictionary = _enemies[i]
		if float(e["hp"]) <= 0.0:
			continue
		var ep: Vector2 = _sample_polyline_at(anchors, float(e["dist"]))
		var d: float = world_point.distance_to(ep)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return
	var e2: Dictionary = _enemies[best_i]
	var hp: float = float(e2["hp"]) - amount
	e2["hp"] = hp
	if hp <= 0.0:
		e2["hp"] = 0.0
		_gold += gold_per_kill
		_update_gold_label()
		_enemies.remove_at(best_i)


func _update_projectiles(delta: float, anchors: PackedVector2Array) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var pos: Vector2 = p["pos"] as Vector2
		var target_v: Variant = _closest_enemy_to_point(anchors, pos)
		if target_v == null:
			var tw: Variant = _closest_enemy_in_range(anchors, tower_position, tower_range * 2.0)
			if tw != null:
				target_v = tw
			else:
				_projectiles.remove_at(i)
				continue
		var target: Vector2 = target_v as Vector2
		var to_enemy := target - pos
		var dist := to_enemy.length()
		var hit_r := enemy_radius + projectile_radius
		if dist < hit_r:
			_projectiles.remove_at(i)
			_damage_enemy_near(anchors, pos, hit_r * 1.25, projectile_damage)
			continue
		if dist > 0.001:
			p["pos"] = pos + to_enemy.normalized() * projectile_speed * delta


func _update_gold_label() -> void:
	if _gold_label != null:
		_gold_label.text = "Gold: %d" % _gold


func _update_wave_ui() -> void:
	if _wave_label != null:
		if _wave_running:
			var alive := _enemies.size()
			_wave_label.text = "Wave: 1 (%d alive)" % alive
		else:
			_wave_label.text = "Wave: —"


func _update_start_button() -> void:
	if _start_wave_button != null:
		if _wave_running:
			_start_wave_button.set_pressed_no_signal(false)
			_start_wave_button.release_focus()
		_start_wave_button.disabled = _wave_running


func _ensure_path_curve() -> void:
	if _enemy_path == null:
		push_warning("WorldView: PathFollowRoot/EnemyPath not found.")
		return
	if _enemy_path.curve == null:
		_enemy_path.curve = Curve2D.new()
	var curve: Curve2D = _enemy_path.curve
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

	for p: Dictionary in _projectiles:
		var shot_pos: Vector2 = p["pos"] as Vector2
		draw_circle(shot_pos, projectile_radius + 1.0, Color(0.1, 0.08, 0.02, 0.6))
		draw_circle(shot_pos, projectile_radius, projectile_color)

	for e: Dictionary in _enemies:
		var hp: float = float(e["hp"])
		if hp <= 0.0:
			continue
		var enemy_pos: Vector2 = _sample_polyline_at(anchors, float(e["dist"]))
		draw_circle(enemy_pos, enemy_radius, enemy_color)
		draw_arc(enemy_pos, enemy_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
		_draw_hp_bar_at(enemy_pos, hp)


func _draw_hp_bar_at(center: Vector2, hp: float) -> void:
	var ratio := 0.0 if enemy_max_hp <= 0.0 else clampf(hp / enemy_max_hp, 0.0, 1.0)
	var bar_w := 44.0
	var bar_h := 6.0
	var top_left := center + Vector2(-bar_w * 0.5, -enemy_radius - 14.0)
	draw_rect(Rect2(top_left, Vector2(bar_w, bar_h)), Color(0.05, 0.05, 0.06, 0.85))
	draw_rect(Rect2(top_left, Vector2(bar_w * ratio, bar_h)), Color(0.2, 0.85, 0.35, 0.95))


func _read_anchor_points() -> PackedVector2Array:
	if _enemy_path != null and _enemy_path.curve != null:
		var curve: Curve2D = _enemy_path.curve
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
