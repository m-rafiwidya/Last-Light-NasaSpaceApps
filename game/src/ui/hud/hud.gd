extends UIScreen

var fade_tween: Tween = null


func _ready() -> void:
	add_child(BoundaryHint.new(false))
	InputBindings.events.changed.connect(_update_hint)
	_update_hint()
	hide()


## The controls line, with the keys as bound now (InputBindings)
func _update_hint() -> void:
	var key := InputBindings.action_text
	$MarginContainer/Hint.text = (
		"%s: move   %s: sprint   %s: jump   %s: crouch   Mouse: look\n" % [
			InputBindings.keys_text([&"move_forward", &"move_left", &"move_backward", &"move_right"]),
			key.call(&"move_sprint"), key.call(&"move_jump"), key.call(&"move_crouch")]
		+ "%s: use / pick up / drop   %s: throw   %s: helmet light   %s: pause" % [
			key.call(&"interact_use"), key.call(&"interact_primary"), key.call(&"lights"), key.call(&"ui_cancel")])


func _process(_delta: float) -> void:
	if is_instance_valid(GameState.player):
		var player: Player = GameState.player
		var target: Object = player.looking_at_object
		var is_looking_at_interact_trigger: bool = is_interactive(target)
		$MarginContainer/CenterContainer/TextureRect.visible = !player.hide_crosshair and not is_looking_at_interact_trigger
		$MarginContainer/CenterContainer/TextureRect2.visible = !player.hide_crosshair and is_looking_at_interact_trigger
		%PartTooltip.show_for(target if not player.hide_crosshair else null, true, target != null and target == player.held_object)
	else:
		%PartTooltip.hide()


## True when E does something with `target`: a prop, or a trigger (not an empty socket's)
static func is_interactive(target: Object) -> bool:
	if target is RigidBody3D:
		# A rover only where the level lets the player lift one (RoverLevel.player_lifts_rovers)
		return not (target is Robot and is_instance_valid(GameState.player) and not GameState.player.player_lifts_rovers)
	if target is InteractTrigger:
		var socket := (target as Node).get_parent() as HotswapSocket
		return socket == null or socket.part != null
	return false


func fade_in():
	show()
	_fade_to(1.0)


func fade_out():
	if visible:
		_fade_to(0.0).tween_callback(hide)


# Kills the previous fade so a quick fade_out -> fade_in can't hide the HUD afterwards
func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property($CanvasModulate, "color", Color(1.0, 1.0, 1.0, alpha), FADE_DURATION)
	return fade_tween
