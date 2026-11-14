class_name UIScreen

extends CanvasLayer

## Base class for full-screen UI managed by UIManager. Subclasses implement
## fade_in() / fade_out() and can use the helpers below for consistent animation.

const FADE_DURATION: float = 0.5
## Width of the reference viewport; menu sub-screens slide in from +-this
const SLIDE_DISTANCE: float = 1920.0


func fade_in():
	pass


func fade_out():
	pass


## Tween used by all UI animation: ease in/out cubic, ignores Engine.time_scale and
## keeps running while the tree is paused.
func create_ui_tween() -> Tween:
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


## Slides a sub-screen to x = `x` (0 = on screen, +-SLIDE_DISTANCE = off screen).
func slide_to(node: Control, x: float) -> void:
	create_ui_tween().tween_property(node, "position", Vector2(x, 0.0), FADE_DURATION)
