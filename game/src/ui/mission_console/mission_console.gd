extends UIScreen

const FADE_DURATION: float = 0.5

var fade_tween: Tween = null


func _ready() -> void:
	$Square.modulate.a = 0.0
	$Square/Close.pressed.connect(_on_close_pressed)
	hide()


func _on_close_pressed():
	# The screen stays clickable while fading out, so only react in this state.
	if GameState.state == GameState.State.MISSION_CONSOLE:
		GameState.change_state_to(GameState.State.IN_GAME)


func fade_in():
	show()
	_fade_to(1.0)


func fade_out():
	if not visible:
		return
	_fade_to(0.0).tween_callback(hide)


func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.set_ignore_time_scale(true)
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.tween_property($Square, "modulate:a", alpha, FADE_DURATION)
	return fade_tween
