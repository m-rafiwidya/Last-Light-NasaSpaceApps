extends AudioStreamPlayer3D

## Procedural electric motor whir, driven by the robot's DC motor.
##
## - Pitch follows motor speed (fraction of the motor's no-load speed).
## - Loudness follows speed plus load, so it is silent when parked with no input,
##   rises as the robot moves, and hums while straining against a stall.
## - Load (|torque| / stall torque) brightens the sound: more upper harmonics and
##   more controller (PWM) whine, as a loaded motor does.
## - A gear whine at a non-integer multiple of the motor tone and a little low
##   passed noise (bearings, wheels) make it sound mechanical instead of a
##   plain synth tone.
## Parameters are smoothed and ramped per sample, so changes don't click.

## Motor tone at standstill / at the motor's no-load speed (Hz)
@export var min_frequency: float = 70.0
@export var max_frequency: float = 650.0
## Gear whine frequency as a multiple of the motor tone (non-integer = inharmonic)
@export var gear_whine_ratio: float = 2.7
## Controller (PWM) whine frequency range (Hz), low speed to full speed
@export var controller_whine_min: float = 2200.0
@export var controller_whine_max: float = 3000.0
## Overall output level (0..1)
@export_range(0.0, 1.0) var volume: float = 0.5
## How quickly the sound follows the motor (1/s). Higher is snappier.
@export var response_rate: float = 12.0

var robot: Robot
var playback: AudioStreamGeneratorPlayback
var sample_hz: float

# Oscillator phases, 0..1
var motor_phase: float = 0.0
var gear_phase: float = 0.0
var controller_phase: float = 0.0
var noise_state: float = 0.0

# Smoothed parameters, ramped per sample inside each batch
var speed_fraction: float = 0.0
var load_fraction: float = 0.0
var loudness: float = 0.0


func _ready() -> void:
	robot = get_parent() as Robot
	sample_hz = (stream as AudioStreamGenerator).mix_rate
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	if robot == null or playback == null:
		return
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return

	var no_load_speed: float = maxf(robot.engine.no_load_speed, 0.001)
	var stall_torque: float = maxf(robot.engine.stall_torque, 0.001)
	var target_speed: float = clampf(absf(robot.motor_angular_velocity) / no_load_speed, 0.0, 1.0)
	var target_load: float = clampf(absf(robot.motor_torque) / stall_torque, 0.0, 1.0)
	# Silent when parked with no input; speed dominates, load keeps a stalled motor audible
	var target_loudness: float = clampf(target_speed * 2.5 + target_load * 0.6, 0.0, 1.0)

	var blend: float = 1.0 - exp(-response_rate * delta)
	var next_speed: float = lerpf(speed_fraction, target_speed, blend)
	var next_load: float = lerpf(load_fraction, target_load, blend)
	var next_loudness: float = lerpf(loudness, target_loudness, blend)

	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i in frames:
		var t: float = float(i + 1) / float(frames)
		var s: float = lerpf(speed_fraction, next_speed, t)
		var l: float = lerpf(load_fraction, next_load, t)
		var gain: float = lerpf(loudness, next_loudness, t)

		var motor_hz: float = lerpf(min_frequency, max_frequency, s)
		motor_phase = fmod(motor_phase + motor_hz / sample_hz, 1.0)
		gear_phase = fmod(gear_phase + motor_hz * gear_whine_ratio / sample_hz, 1.0)
		controller_phase = fmod(
			controller_phase + lerpf(controller_whine_min, controller_whine_max, s) / sample_hz, 1.0
		)

		var a: float = motor_phase * TAU
		var g: float = gear_phase * TAU
		var motor_tone: float = (
			sin(a)
			+ 0.45 * sin(2.0 * a)
			+ (0.15 + 0.35 * l) * sin(3.0 * a)
			+ 0.3 * l * sin(5.0 * a)
		)
		var gear_whine: float = 0.3 * sin(g) + 0.12 * sin(2.0 * g)
		var controller_whine: float = 0.06 * (0.25 + 0.75 * l) * sin(controller_phase * TAU)

		noise_state += (randf_range(-1.0, 1.0) - noise_state) * 0.15
		var rumble: float = noise_state * 0.35 * s

		var sample: float = tanh((motor_tone + gear_whine + controller_whine + rumble) * 0.6)
		sample *= gain * volume
		buffer[i] = Vector2(sample, sample)

	playback.push_buffer(buffer)
	speed_fraction = next_speed
	load_fraction = next_load
	loudness = next_loudness
