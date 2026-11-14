extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$DialogTrigger.interacted.connect(_on_dialog_trigger_interacted)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_dialog_trigger_interacted(player: Player):
	var test_dialog_sequence := DialogSequence.new()
	test_dialog_sequence.dialogs.append(Dialog.new())
	test_dialog_sequence.dialogs[0].subtitle = "This is a test of the current dialog system."
	test_dialog_sequence.dialogs.append(Dialog.new())
	test_dialog_sequence.dialogs[1].subtitle = "Major overhaul of this system might be on the horizon."
	# TODO: Optionally include an audiostream
	#test_dialog.audio_stream = ResourceLoader.load("res://res/sounds/test_narration.wav")
	DialogServer.play_dialog_sequence(test_dialog_sequence)
