extends Node


signal dialog_played(dialog)
signal dialog_ended(dialog)


var audio_players: Dictionary
var timers: Dictionary


func _ready() -> void:
	SceneLoader.level_unloaded.connect(_on_scene_loader_level_unloaded)


func _on_scene_loader_level_unloaded(_level_name):
	for instance_id in timers.keys():
		var timer = timers[instance_id]
		if timer and not timer.is_queued_for_deletion():
			dialog_ended.emit(instance_from_id(instance_id))
			timer.stop()
			timer.queue_free()
		timers.erase(instance_id)


func play_dialog_sequence(dialog_sequence: DialogSequence):
	for dialog in dialog_sequence.dialogs:
		play_dialog(dialog)
		await dialog_ended # Might change level here
		await get_tree().create_timer(0.2).timeout # Might change level here


func play_dialog(dialog: Dialog):
	if timers.has(dialog.get_instance_id()):
		# For some reason timer is already playing, so skip
		return
	
	var character_per_minute = 1000.0
	var character_per_second = character_per_minute / 60.0
	var timer = Timer.new()
	timer.wait_time = dialog.subtitle.length() / character_per_second
	timer.timeout.connect(_on_dialog_finished.bind(dialog))
	get_tree().current_scene.add_child(timer)
	timer.start()
	
	timers[dialog.get_instance_id()] = timer
	dialog_played.emit(dialog)


func _on_dialog_finished(dialog: Dialog):
	print("Dialog ended")
	dialog_ended.emit(dialog)
	var timer = timers[dialog.get_instance_id()]
	timer.queue_free()
	timers.erase(dialog.get_instance_id())
