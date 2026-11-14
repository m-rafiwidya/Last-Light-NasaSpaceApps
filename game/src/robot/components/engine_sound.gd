extends AudioStreamPlayer3D

## Procedural electric motor whir, driven by the robot's DC motor.
##
## - Pitch follows motor speed (fraction of the motor's no-load speed).
## - Loudness follows speed plus load, so it is silent when parked with no input,
##   rises as the robot moves, and hums while straining against a stall.
## - Load (|torque| / stall torque) brightens the sound: more upper harmonics and
##   more controller (PWM) hum, as a loaded motor does.
## - A gear whine at a non-integer multiple of the motor tone and a little low
##   passed noise (bearings, wheels) make it sound mechanical instead of a
##   plain synth tone.
## - Deep Space style (game/music/CLAUDE.md): dark and soft, heard through the rover's
##   structure. A two-pole lowpass after the saturation (opening a little with speed and load)
##   keeps everything under about 1.5 kHz; nothing whines high.
## Parameters are smoothed and ramped per sample, so changes don't click.
## Plays on the SFX bus; Sfx counts it among the loops (the main layer while driven).

## Motor tone at standstill / at the motor's no-load speed (Hz)
@export var min_frequency: float = 70.0
@export var max_frequency: float = 420.0
## Gear whine frequency as a multiple of the motor tone (non-integer = inharmonic)
@export var gear_whine_ratio: float = 2.7
## Controller (PWM) hum frequency range (Hz), low speed to full speed
@export var controller_whine_min: float = 520.0
@export var controller_whine_max: float = 780.0
## Lowpass cutoff (Hz) at standstill / at full speed and load
@export var lowpass_min: float = 700.0
@export var lowpass_max: float = 1400.0
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
var lowpass_1: float = 0.0
var lowpass_2: float = 0.0

# Smoothed parameters, ramped per sample inside each batch
var speed_fraction: float = 0.0
var load_fraction: float = 0.0
var loudness: float = 0.0


func _ready() -> void:
	robot = get_parent() as Robot
	if AudioServer.get_bus_index(&"SFX") >= 0:
		bus = &"SFX"
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

	# Two one-pole lowpasses in series, cutoff ramped across the batch
	var cutoff_now: float = lerpf(lowpass_min, lowpass_max, clampf(speed_fraction * 0.7 + load_fraction * 0.5, 0.0, 1.0))
	var cutoff_next: float = lerpf(lowpass_min, lowpass_max, clampf(next_speed * 0.7 + next_load * 0.5, 0.0, 1.0))

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
			+ 0.4 * sin(2.0 * a)
			+ (0.1 + 0.25 * l) * sin(3.0 * a)
			+ 0.12 * l * sin(5.0 * a)
		)
		var gear_whine: float = 0.2 * sin(g)
		var controller_whine: float = 0.04 * (0.25 + 0.75 * l) * sin(controller_phase * TAU)

		noise_state += (randf_range(-1.0, 1.0) - noise_state) * 0.15
		var rumble: float = noise_state * 0.35 * s

		var sample: float = tanh((motor_tone + gear_whine + controller_whine + rumble) * 0.6)
		var k: float = 1.0 - exp(-TAU * lerpf(cutoff_now, cutoff_next, t) / sample_hz)
		lowpass_1 += (sample - lowpass_1) * k
		lowpass_2 += (lowpass_1 - lowpass_2) * k
		sample = lowpass_2 * gain * volume
		buffer[i] = Vector2(sample, sample)

	playback.push_buffer(buffer)
	speed_fraction = next_speed
	load_fraction = next_load
	loudness = next_loudness
