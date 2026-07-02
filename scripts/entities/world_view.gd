extends Node2D

## Weeks 3–8: map, path, waves, tower placement, HUD (gold / lives / wave).

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
@export var starting_gold: int = 100
@export var starting_lives: int = 20
@export var gold_per_kill: int = 15

@export var wave_enemy_count: int = 6
@export var wave_spawn_interval: float = 0.85

@export var projectile_radius: float = 7.0
@export var show_tower_range: bool = true
@export_range(0.0, 1.0) var sell_refund_ratio: float = 0.8

const TOWER_COSTS: Dictionary = {
	&"archer": 100,
	&"cannon": 150,
	&"rapid": 125,
}

## Which tower profile is active (week 7: build panel + placement).
var _active_tower_id: StringName = &"archer"

@export_group("Build grid (week 7)")
@export var build_cell_size: float = 72.0
@export var build_grid_origin: Vector2 = Vector2(48, 48)
@export var build_grid_cols: int = 14
@export var build_grid_rows: int = 8
@export var path_block_margin: float = 56.0
@export var show_build_grid: bool = true

var _enemy_path: Path2D
var _path_ready := false
var _path_length: float = 0.0

var _wave_running := false
var _wave_number: int = 0
var _spawns_remaining: int = 0
var _spawn_timer: float = 0.0
var _enemies: Array[Dictionary] = []

var _projectiles: Array[Dictionary] = []

var _gold: int = 0
var _lives: int = 0
var _placed_towers: Array[Dictionary] = []
var _occupied_cells: Dictionary = {}
var _gold_label: Label
var _lives_label: Label
var _wave_label: Label
var _start_wave_button: Button
var _restart_button: Button
var _sell_button: Button
var _debug_gold_button: Button
var _debug_lives_button: Button
var _hint_label: Label
var _lose_screen: Control
var _game_over := false

var _hover_cell: Vector2i = Vector2i(-1, -1)

var _tower_pick_group: ButtonGroup = ButtonGroup.new()
var _btn_archer: Button
var _btn_cannon: Button
var _btn_rapid: Button


func _ready() -> void:
	_gold_label = get_node_or_null("../../UI/TopBar/GoldLabel") as Label
	_lives_label = get_node_or_null("../../UI/TopBar/LivesLabel") as Label
	_wave_label = get_node_or_null("../../UI/TopBar/WaveLabel") as Label
	_start_wave_button = get_node_or_null("../../UI/ActionPanel/ActionVBox/StartWaveButton") as Button
	if _start_wave_button != null:
		# Use button_up so disabling the button does not leave a stuck "pressed" style (weird overlay).
		_start_wave_button.button_up.connect(_on_start_wave_button_up)

	_restart_button = get_node_or_null("../../UI/ActionPanel/ActionVBox/RestartButton") as Button
	if _restart_button != null:
		_restart_button.pressed.connect(_on_restart_button_pressed)

	_sell_button = get_node_or_null("../../UI/ActionPanel/ActionVBox/SellButton") as Button
	if _sell_button != null:
		_sell_button.button_up.connect(_on_sell_button_up)

	_debug_gold_button = get_node_or_null("../../UI/TopBar/DebugGoldButton") as Button
	if _debug_gold_button != null:
		_debug_gold_button.pressed.connect(_on_debug_gold_button_pressed)

	_debug_lives_button = get_node_or_null("../../UI/TopBar/DebugLivesButton") as Button
	if _debug_lives_button != null:
		_debug_lives_button.pressed.connect(_on_debug_lives_button_pressed)

	_hint_label = get_node_or_null("../../UI/HintLabel") as Label

	_lose_screen = get_node_or_null("../../UI/LoseScreen") as Control

	_btn_archer = get_node_or_null("../../UI/BuildPanel/BuildVBox/TowerButton_Archer") as Button
	_btn_cannon = get_node_or_null("../../UI/BuildPanel/BuildVBox/TowerButton_Cannon") as Button
	_btn_rapid = get_node_or_null("../../UI/BuildPanel/BuildVBox/TowerButton_Rapid") as Button
	_setup_tower_type_buttons()

	_enemy_path = get_node_or_null("PathFollowRoot/EnemyPath") as Path2D
	var tower_marker: Marker2D = get_node_or_null("TowerRoot/DemoTower") as Marker2D
	if tower_marker != null:
		tower_marker.visible = false
	_ensure_path_curve()
	_path_length = _polyline_length(_read_anchor_points())
	_path_ready = true
	_wave_running = false
	_wave_number = 0
	_spawns_remaining = 0
	_spawn_timer = 0.0
	_enemies.clear()
	_projectiles.clear()
	_placed_towers.clear()
	_occupied_cells.clear()
	_gold = starting_gold
	_lives = starting_lives
	_update_gold_label()
	_update_lives_label()
	_update_wave_ui()
	_update_start_button()
	_update_sell_button()
	_update_hint_label()
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		return
	if event.is_action_pressed("ui_accept"):
		_try_start_wave()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_place_tower_on_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_try_sell_tower_on_click()


func _try_place_tower_on_click() -> void:
	if _game_over:
		return
	var world_pos: Vector2 = get_global_mouse_position()
	var cell := _world_pos_to_cell(world_pos)
	if cell.x < 0 or _is_cell_occupied(cell):
		return
	var center := _cell_center(cell)
	if not _is_valid_build_cell(center, _read_anchor_points()):
		return
	var cost := _get_tower_cost(_active_tower_id)
	if _gold < cost:
		return
	_gold -= cost
	_update_gold_label()
	_placed_towers.append(_make_tower(cell, center, _active_tower_id))
	_occupied_cells[_cell_key(cell)] = true
	_update_hint_label()
	_update_sell_button()
	queue_redraw()


func _try_sell_tower_on_click() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var cell := _world_pos_to_cell(world_pos)
	if cell.x < 0:
		return
	_sell_tower_at_cell(cell)


func _on_sell_button_up() -> void:
	_sell_tower_at_cell(_hover_cell)


func _on_debug_gold_button_pressed() -> void:
	_gold += 100
	_update_gold_label()
	queue_redraw()


func _on_debug_lives_button_pressed() -> void:
	_lose_life()


func _sell_tower_at_cell(cell: Vector2i) -> void:
	var idx := _find_tower_index_at_cell(cell)
	if idx < 0:
		return
	var tower: Dictionary = _placed_towers[idx]
	_gold += _get_sell_value(tower)
	_placed_towers.remove_at(idx)
	_occupied_cells.erase(_cell_key(cell))
	_update_gold_label()
	_update_sell_button()
	queue_redraw()


func _find_tower_index_at_cell(cell: Vector2i) -> int:
	for i in _placed_towers.size():
		var tower_cell: Vector2i = _placed_towers[i]["cell"] as Vector2i
		if tower_cell == cell:
			return i
	return -1


func _get_sell_value(tower: Dictionary) -> int:
	var cost: int = int(tower.get("cost", 0))
	return int(floor(float(cost) * sell_refund_ratio))


func _setup_tower_type_buttons() -> void:
	for b: Button in [_btn_archer, _btn_cannon, _btn_rapid]:
		if b == null:
			continue
		b.toggle_mode = true
		b.button_group = _tower_pick_group
	if _btn_archer != null:
		_btn_archer.toggled.connect(_on_tower_type_toggled.bind(&"archer"))
	if _btn_cannon != null:
		_btn_cannon.toggled.connect(_on_tower_type_toggled.bind(&"cannon"))
	if _btn_rapid != null:
		_btn_rapid.toggled.connect(_on_tower_type_toggled.bind(&"rapid"))
	# Default selection so range / DPS match the visible profile before first click.
	if _btn_archer != null:
		_btn_archer.set_pressed_no_signal(true)
	elif _btn_cannon != null:
		_btn_cannon.set_pressed_no_signal(true)
	elif _btn_rapid != null:
		_btn_rapid.set_pressed_no_signal(true)


func _on_tower_type_toggled(pressed: bool, id: StringName) -> void:
	if not pressed:
		return
	_active_tower_id = id
	_update_hint_label()
	queue_redraw()


func _tower_stats_for(id: StringName) -> Dictionary:
	match id:
		&"cannon":
			return {
				"range": 220.0,
				"fire_interval": 0.95,
				"projectile_damage": 52.0,
				"projectile_speed": 420.0,
				"tower_radius": 28.0,
				"tower_color": Color(0.55, 0.35, 0.2, 1.0),
				"projectile_color": Color(1.0, 0.55, 0.15, 1.0),
			}
		&"rapid":
			return {
				"range": 240.0,
				"fire_interval": 0.22,
				"projectile_damage": 14.0,
				"projectile_speed": 720.0,
				"tower_radius": 22.0,
				"tower_color": Color(0.35, 0.75, 0.45, 1.0),
				"projectile_color": Color(0.85, 1.0, 0.45, 1.0),
			}
		_:
			return {
				"range": 280.0,
				"fire_interval": 0.4,
				"projectile_damage": 28.0,
				"projectile_speed": 560.0,
				"tower_radius": 26.0,
				"tower_color": Color(0.25, 0.45, 0.85, 1.0),
				"projectile_color": Color(1.0, 0.95, 0.35, 1.0),
			}


func _get_tower_cost(id: StringName) -> int:
	return int(TOWER_COSTS.get(id, 100))


func _make_tower(cell: Vector2i, position: Vector2, id: StringName) -> Dictionary:
	var stats := _tower_stats_for(id)
	return {
		"id": id,
		"cell": cell,
		"position": position,
		"cost": _get_tower_cost(id),
		"fire_timer": 0.0,
		"range": stats["range"],
		"fire_interval": stats["fire_interval"],
		"projectile_damage": stats["projectile_damage"],
		"projectile_speed": stats["projectile_speed"],
		"tower_radius": stats["tower_radius"],
		"tower_color": stats["tower_color"],
		"projectile_color": stats["projectile_color"],
	}


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _is_cell_occupied(cell: Vector2i) -> bool:
	return _occupied_cells.has(_cell_key(cell))


func _tower_display_name(id: StringName) -> String:
	match id:
		&"cannon":
			return "Cannon"
		&"rapid":
			return "Rapid"
		_:
			return "Archer"


func _update_hint_label() -> void:
	if _hint_label == null:
		return
	var tname := _tower_display_name(_active_tower_id)
	var cost := _get_tower_cost(_active_tower_id)
	var refund_pct := int(round(sell_refund_ratio * 100.0))
	_hint_label.text = "%s (%d gold) — left-click green cell to place. Right-click occupied cell or Sell (%d%% refund)." % [tname, cost, refund_pct]


func _on_start_wave_button_up() -> void:
	_try_start_wave()


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _try_start_wave() -> void:
	if _game_over or _wave_running:
		return
	_begin_wave()


func _begin_wave() -> void:
	_wave_number += 1
	_wave_running = true
	_spawns_remaining = wave_enemy_count
	_spawn_timer = 0.0
	_enemies.clear()
	_projectiles.clear()
	_update_wave_ui()
	_update_start_button()
	_update_sell_button()
	_update_hint_label()
	queue_redraw()


func _process(delta: float) -> void:
	if not _path_ready or _game_over:
		return

	_update_build_hover()

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

	for tower: Dictionary in _placed_towers:
		var fire_timer: float = float(tower["fire_timer"]) - delta
		tower["fire_timer"] = fire_timer
		var tower_pos: Vector2 = tower["position"] as Vector2
		var tower_range: float = float(tower["range"])
		var target_pos: Variant = _closest_enemy_in_range(anchors, tower_pos, tower_range)
		if target_pos != null and tower_range > 0.0 and fire_timer <= 0.0:
			tower["fire_timer"] = float(tower["fire_interval"])
			_projectiles.append({
				"pos": tower_pos,
				"damage": tower["projectile_damage"],
				"speed": tower["projectile_speed"],
				"color": tower["projectile_color"],
			})

	_update_projectiles(delta, anchors)

	if _spawns_remaining <= 0 and _enemies.is_empty() and _projectiles.is_empty():
		_wave_running = false
		_update_wave_ui()
		_update_start_button()
		_update_hint_label()
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
			_lose_life()
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
		var shot_speed: float = float(p["speed"])
		var shot_damage: float = float(p["damage"])
		var target_v: Variant = _closest_enemy_to_point(anchors, pos)
		if target_v == null:
			_projectiles.remove_at(i)
			continue
		var target: Vector2 = target_v as Vector2
		var to_enemy := target - pos
		var dist := to_enemy.length()
		var hit_r := enemy_radius + projectile_radius
		if dist < hit_r:
			_projectiles.remove_at(i)
			_damage_enemy_near(anchors, pos, hit_r * 1.25, shot_damage)
			continue
		if dist > 0.001:
			p["pos"] = pos + to_enemy.normalized() * shot_speed * delta


func _lose_life() -> void:
	if _game_over or _lives <= 0:
		return
	_lives -= 1
	_update_lives_label()
	if _lives <= 0:
		_trigger_game_over()


func _trigger_game_over() -> void:
	_game_over = true
	_wave_running = false
	_enemies.clear()
	_projectiles.clear()
	_update_wave_ui()
	_update_start_button()
	_set_build_controls_enabled(false)
	if _lose_screen != null and _lose_screen.has_method("play_defeat"):
		_lose_screen.play_defeat(_wave_number)


func _set_build_controls_enabled(enabled: bool) -> void:
	if _sell_button != null:
		_sell_button.disabled = not enabled
	if _start_wave_button != null:
		_start_wave_button.disabled = not enabled or _wave_running
	if _restart_button != null:
		_restart_button.disabled = false
	for b: Button in [_btn_archer, _btn_cannon, _btn_rapid]:
		if b != null:
			b.disabled = not enabled


func _update_gold_label() -> void:
	if _gold_label != null:
		_gold_label.text = "Gold: %d" % _gold


func _update_lives_label() -> void:
	if _lives_label != null:
		_lives_label.text = "Lives: %d" % _lives


func _update_wave_ui() -> void:
	if _wave_label != null:
		_wave_label.text = "Wave: %d" % _wave_number


func _update_sell_button() -> void:
	if _sell_button == null or _game_over:
		return
	var can_sell := _hover_cell.x >= 0 and _is_cell_occupied(_hover_cell)
	_sell_button.disabled = not can_sell
	if can_sell:
		var idx := _find_tower_index_at_cell(_hover_cell)
		if idx >= 0:
			var refund := _get_sell_value(_placed_towers[idx])
			_sell_button.text = "Sell (+%d)" % refund
		else:
			_sell_button.text = "Sell"
	else:
		_sell_button.text = "Sell"


func _update_start_button() -> void:
	if _start_wave_button != null:
		if _wave_running:
			_start_wave_button.set_pressed_no_signal(false)
			_start_wave_button.release_focus()
		_start_wave_button.disabled = _wave_running or _game_over


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

	_draw_build_grid()

	for tower: Dictionary in _placed_towers:
		var tower_pos: Vector2 = tower["position"] as Vector2
		var tower_range: float = float(tower["range"])
		var tower_radius: float = float(tower["tower_radius"])
		var tower_color: Color = tower["tower_color"] as Color
		if show_tower_range:
			draw_arc(tower_pos, tower_range, 0.0, TAU, 96, Color(0.4, 0.65, 1.0, 0.22), 2.0, true)
		draw_circle(tower_pos, tower_radius + 3.0, Color(0.08, 0.1, 0.14, 1.0))
		draw_circle(tower_pos, tower_radius, tower_color)

	for p: Dictionary in _projectiles:
		var shot_pos: Vector2 = p["pos"] as Vector2
		var shot_color: Color = p["color"] as Color
		draw_circle(shot_pos, projectile_radius + 1.0, Color(0.1, 0.08, 0.02, 0.6))
		draw_circle(shot_pos, projectile_radius, shot_color)

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


func _is_valid_build_cell(center: Vector2, anchors: PackedVector2Array) -> bool:
	var poly := _densify_polyline(anchors, path_sample_step)
	return _min_dist_to_polyline(center, poly) >= path_block_margin


func _min_dist_to_polyline(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return INF
	var best: float = INF
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i] as Vector2
		var b: Vector2 = poly[i + 1] as Vector2
		var d: float = _dist_point_to_segment(p, a, b)
		if d < best:
			best = d
	return best


func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _world_pos_to_cell(world_pos: Vector2) -> Vector2i:
	var rel: Vector2 = world_pos - build_grid_origin
	var cx: int = int(rel.x / build_cell_size)
	var cy: int = int(rel.y / build_cell_size)
	if cx < 0 or cy < 0 or cx >= build_grid_cols or cy >= build_grid_rows:
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)


func _cell_center(cell: Vector2i) -> Vector2:
	return build_grid_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * build_cell_size


func _update_build_hover() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var cell: Vector2i = _world_pos_to_cell(world_pos)
	if cell != _hover_cell:
		_hover_cell = cell
		_update_sell_button()
		queue_redraw()


func _draw_build_grid() -> void:
	if not show_build_grid:
		return
	var anchors := _read_anchor_points()
	for cy in range(build_grid_rows):
		for cx in range(build_grid_cols):
			var cell := Vector2i(cx, cy)
			var top_left: Vector2 = build_grid_origin + Vector2(float(cx), float(cy)) * build_cell_size
			var rect := Rect2(top_left, Vector2(build_cell_size, build_cell_size))
			var center := _cell_center(cell)
			var fill := Color(1.0, 1.0, 1.0, 0.06)
			if _is_cell_occupied(cell):
				fill = Color(0.45, 0.45, 0.5, 0.32)
			elif cell == _hover_cell and cell.x >= 0:
				if not _is_valid_build_cell(center, anchors):
					fill = Color(0.95, 0.28, 0.28, 0.28)
				elif _gold < _get_tower_cost(_active_tower_id):
					fill = Color(0.95, 0.82, 0.2, 0.32)
				else:
					fill = Color(0.25, 0.95, 0.35, 0.28)
			draw_rect(rect, fill, true)
			draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)


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
