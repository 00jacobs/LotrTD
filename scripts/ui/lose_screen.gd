extends Control

## 3D defeat overlay — CC0 raymarched fire + procedural eye (SubViewport).

signal restart_requested

const DEFEAT_WORLD_SCENE := preload("res://scenes/ui/defeat_world_3d.tscn")

@export var fade_duration: float = 1.4
@export var restart_delay: float = 2.0
@export var dim_overlay_alpha: float = 0.52

var _active := false
var _time := 0.0

var _viewport: SubViewport
var _world: Node3D
var _title: Label
var _flavor_backing: PanelContainer
var _subtitle: Label
var _stat_label: Label
var _top_vignette: ColorRect
var _bottom_bar: Panel
var _restart_button: Button
var _ui_dim_overlay: ColorRect
var _fade_overlay: ColorRect


func _ready() -> void:
	_bind_nodes()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

	if _restart_button != null:
		_restart_button.pressed.connect(_on_restart_pressed)
		_restart_button.modulate.a = 0.0
		_restart_button.disabled = true
	if _title != null:
		_title.modulate.a = 0.0
	if _flavor_backing != null:
		_flavor_backing.modulate.a = 0.0
	if _top_vignette != null:
		_top_vignette.modulate.a = 0.0
	if _bottom_bar != null:
		_bottom_bar.modulate.a = 0.0
	if _ui_dim_overlay != null:
		_ui_dim_overlay.color = Color(0, 0, 0, dim_overlay_alpha)
		_ui_dim_overlay.modulate.a = 0.0
	if _fade_overlay != null:
		_fade_overlay.color = Color(0, 0, 0, 1.0)
	if _world != null and _world.has_method("stop"):
		_world.stop()


func _bind_nodes() -> void:
	_viewport = get_node_or_null("ViewportContainer/SubViewport") as SubViewport
	_world = get_node_or_null("ViewportContainer/SubViewport/DefeatWorld3D") as Node3D
	_title = get_node_or_null("TitleLabel") as Label
	_flavor_backing = get_node_or_null("FlavorBacking") as PanelContainer
	_subtitle = get_node_or_null("FlavorBacking/FlavorVBox/SubtitleLabel") as Label
	_stat_label = get_node_or_null("FlavorBacking/FlavorVBox/StatLabel") as Label
	_top_vignette = get_node_or_null("TopVignette") as ColorRect
	_bottom_bar = get_node_or_null("BottomBar") as Panel
	_restart_button = get_node_or_null("BottomBar/RestartButton") as Button
	_ui_dim_overlay = get_node_or_null("UiDimOverlay") as ColorRect
	_fade_overlay = get_node_or_null("FadeOverlay") as ColorRect

	if _world == null:
		_world = _spawn_defeat_world()


func _spawn_defeat_world() -> Node3D:
	if _viewport == null:
		_viewport = get_node_or_null("ViewportContainer/SubViewport") as SubViewport
	if _viewport == null:
		push_error("LoseScreen: SubViewport missing — rebuild scenes/ui/lose_screen.tscn")
		return null

	var existing := _viewport.get_node_or_null("DefeatWorld3D") as Node3D
	if existing != null:
		return existing

	var packed: PackedScene = DEFEAT_WORLD_SCENE
	if packed == null:
		push_error("LoseScreen: failed to preload defeat_world_3d.tscn")
		return null

	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		push_error("LoseScreen: defeat_world_3d.tscn root must be Node3D")
		return null

	instance.name = "DefeatWorld3D"
	_viewport.add_child(instance)
	return instance


func play_defeat(wave_reached: int = 0) -> void:
	if _world == null:
		_world = _spawn_defeat_world()

	_active = true
	_time = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.size = Vector2i(1280, 720)

	if _world != null and _world.has_method("play"):
		_world.play()

	if _stat_label != null:
		if wave_reached > 0:
			_stat_label.text = "Fell on Wave %d" % wave_reached
		else:
			_stat_label.text = ""

	if _restart_button != null:
		_restart_button.modulate.a = 0.0
		_restart_button.disabled = true
	if _title != null:
		_title.modulate.a = 0.0
	if _flavor_backing != null:
		_flavor_backing.modulate.a = 0.0
	if _top_vignette != null:
		_top_vignette.modulate.a = 0.0
	if _bottom_bar != null:
		_bottom_bar.modulate.a = 0.0
	if _ui_dim_overlay != null:
		_ui_dim_overlay.color = Color(0, 0, 0, dim_overlay_alpha)
		_ui_dim_overlay.modulate.a = 0.0
	if _fade_overlay != null:
		_fade_overlay.color = Color(0, 0, 0, 1.0)


func _on_restart_pressed() -> void:
	restart_requested.emit()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	var fade := clampf(_time / fade_duration, 0.0, 1.0)

	if _fade_overlay != null:
		_fade_overlay.color = Color(0, 0, 0, 1.0 - fade)

	if _ui_dim_overlay != null:
		_ui_dim_overlay.modulate.a = clampf(fade / 0.35, 0.0, 1.0)

	if _top_vignette != null:
		_top_vignette.modulate.a = clampf(fade / 0.4, 0.0, 1.0)

	if _title != null:
		_title.modulate.a = clampf((fade - 0.15) / 0.5, 0.0, 1.0)
	if _flavor_backing != null:
		_flavor_backing.modulate.a = clampf((fade - 0.28) / 0.5, 0.0, 1.0)
	if _bottom_bar != null:
		_bottom_bar.modulate.a = clampf((fade - 0.45) / 0.55, 0.0, 1.0)
	if _restart_button != null and _time >= restart_delay:
		var btn_fade := clampf((_time - restart_delay) / 0.6, 0.0, 1.0)
		_restart_button.modulate.a = btn_fade
		_restart_button.disabled = btn_fade < 0.5
