class_name FootballSound
extends Node

var kick_stream: AudioStreamWAV
var goal_stream: AudioStreamWAV
var whistle_stream: AudioStreamWAV
var contact_streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var voice_index := 0
var last_touch_sound := -1.0

func _ready() -> void:
	kick_stream = _tone(0.1, 105, 0.4, true)
	goal_stream = _tone(0.55, 440, 0.13, false)
	whistle_stream = _tone(0.2, 1700, 0.08, false)
	contact_streams = {"touch": _tone(0.055, 160, 0.22, true), "pass": _tone(0.075, 125, 0.45, true), "through": _tone(0.085, 115, 0.5, true), "shot": _tone(0.12, 90, 0.65, true), "power": _tone(0.17, 65, 0.75, true), "finesse": _tone(0.1, 150, 0.5, true), "outside": _tone(0.1, 170, 0.5, true), "lob": _tone(0.095, 180, 0.4, true), "chip": _tone(0.07, 210, 0.3, true)}
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)

func play_contact(kind: String, strength: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if kind == "touch" and now - last_touch_sound < 0.09:
		return
	if kind == "touch":
		last_touch_sound = now
	var voice := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	voice.stop()
	voice.stream = contact_streams.get(kind, kick_stream)
	voice.volume_db = lerpf(-12, 0, strength)
	voice.pitch_scale = lerpf(1.12, 0.92, strength)
	voice.play()

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
