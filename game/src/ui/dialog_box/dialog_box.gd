extends Control


func _ready() -> void:
	print("spawned")


func set_text(text: String):
	$MarginContainer/RichTextLabel.text = text


func fade_in():
	#scale = Vector2(1.0, 0.0)
	self.modulate = Color.TRANSPARENT
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)


func fade_out():
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(0.2)
	tween.tween_property(self, "modulate", Color.TRANSPARENT, 0.1)
	tween.tween_callback(queue_free)
