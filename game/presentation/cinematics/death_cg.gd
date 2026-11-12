class_name DeathCG
extends DeathStage
## Cause-specific school horror, staged at eye level rather than below the player.
## The persistent source chooses the shot; gameplay rules and saves are untouched.

static var CAUSES: Array = DeathSceneCatalog.SCENES.keys()
static var LENGTH: Dictionary = DeathSceneCatalog.lengths()
var shots: DeathShots
var _skip_layer: CanvasLayer
var _skip_button: Button
var _skip_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _owns_mouse := false

static func has(cause: String) -> bool:
	return DeathSceneCatalog.SCENES.has(cause)

static func duration(cause: String, fallback: float) -> float:
	return float(LENGTH.get(cause, fallback))

static func resolve(source: String, effect: String) -> String:
	return DeathSceneCatalog.resolve(source, effect)

static func title(cause: String) -> String:
	return DeathSceneCatalog.title(cause)

func begin_live(cause: String, player: PlayerController, world: Node3D, ui: GameUI, duration: float, reduced: bool = false) -> void:
	begin(cause,player,world,ui,duration,reduced,null,true)

func _build_scene() -> void:
	if live_scene and DeathSceneCatalog.uses_live_world(fx):
		shots = DeathInPlace.new(self)
		shots.build()
		return
	match fx:
		"crowd": CrowdDeath.build(self)
		"void": MazeDeath.build_lost(self)
		"abyss": MazeDeath.build_fall(self)
		_:
			shots = DeathShots.new(self)
			shots.build()

func _present_scene(time: float) -> void:
	match fx:
		"crowd": CrowdDeath.update(self,time)
		"void": MazeDeath.update_lost(self,time)
		"abyss": MazeDeath.update_fall(self,time)
		_:
			if shots != null: shots.present(clampf(time / maxf(.1,dur),0,1))
	if is_instance_valid(_skip_button):
		_skip_button.visible = time >= .6

## Offered only during a live death, never over the archive's return/preview controls.
func offer_skip(callback: Callable) -> void:
	if not on or is_instance_valid(_skip_layer): return
	_skip_mouse_mode = Input.mouse_mode
	_owns_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skip_layer = CanvasLayer.new()
	_skip_layer.layer = 18
	add_child(_skip_layer)
	_skip_button = Button.new()
	_skip_button.theme = GameUI.BASE_THEME
	_skip_button.text = "跳过演出"
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.position = Vector2(-178,-72)
	_skip_button.size = Vector2(150,48)
	_skip_button.visible = k >= .6
	_skip_button.pressed.connect(func() -> void:
		if on and k >= .6 and callback.is_valid(): callback.call())
	_skip_layer.add_child(_skip_button)

func _restore() -> void:
	if shots != null: shots.restore()
	super._restore()
	if _owns_mouse:
		Input.mouse_mode = _skip_mouse_mode
		_owns_mouse = false
	if is_instance_valid(_skip_layer):
		_skip_layer.hide()
		_skip_layer.queue_free()
	_skip_layer = null
	_skip_button = null
	shots = null
