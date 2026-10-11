class_name FootballSound
extends Node

var kick_stream: AudioStreamWAV
var goal_stream: AudioStreamWAV
var whistle_stream: AudioStreamWAV

func _ready() -> void:
	kick_stream = _tone(0.1, 105, 0.4, true)
	goal_stream = _tone(0.55, 440, 0.13, false)
	whistle_stream = _tone(0.2, 1700, 0.08, false)

func _tone(duration: float, frequency: float, amplitude: float, thump: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(duration * stream.mix_rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var time := float(i) / stream.mix_rate
		var envelope := pow(1.0 - float(i) / count, 3.0 if thump else 0.8)
		var wave := sin(time * frequency * TAU) + sin(time * frequency * 1.5 * TAU) * 0.3
		var sample := int(clampf(wave * amplitude * envelope, -1, 1) * 32767)
		data.encode_s16(i * 2, sample)
	stream.data = data
	return stream

func play_event(kind: String) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = goal_stream if kind == "goal" else (whistle_stream if kind == "whistle" else kick_stream)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
