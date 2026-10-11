class_name FootballSquad
extends RefCounted

const SAVE_PATH := "user://squad.json"
var entries: Array = []
var completed_matches: int = 0
var save_path: String = SAVE_PATH
var last_error: String = ""

func load_squad(is_acceptance: bool = false) -> void:
	# Acceptance has an isolated save; never modifies the user's squad.
	if is_acceptance:
		save_path = "user://acceptance_squad.json"
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/squad.json"))
	entries = definition["players"].duplicate(true)
	for entry in entries:
		entry["xp"] = 0
	if not is_acceptance and FileAccess.file_exists(save_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if saved is Dictionary and saved.get("version") == 1:
			completed_matches = int(saved.get("matches", 0))
			for entry in entries:
				entry["xp"] = maxi(0, int(saved.get("xp", {}).get(entry["id"], 0)))

func apply_to(player: FootballPlayer, index: int) -> void:
	var entry: Dictionary = entries[index]
	player.player_id = entry["id"]
	player.player_name = entry["name"]
	player.shirt_number = int(entry["number"])
	player.role = entry["role"]
	player.mass = float(entry["mass"])
	player.pace = float(entry["pace"])
	player.experience = int(entry["xp"])
	# Bounded growth: +12% touch/stamina, +6% mass; pace never inflates.
	var development := minf(float(player.experience) / 1200.0, 1.0)
	player.touch_skill = float(entry["touch"]) * (1.0 + development * 0.12)
	player.stamina_trait = float(entry["stamina"]) * (1.0 + development * 0.12)
	player.balance_skill = float(entry.get("balance", 1.0)) * (1.0 + development * 0.06)
	player.agility_skill = float(entry.get("agility", 1.0)) * (1.0 + development * 0.06)
	player.mass *= 1.0 + development * 0.06

func finish(players: Array[FootballPlayer]) -> String:
	var report := ""
	for player in players:
		if player.team != 0:
			continue
		# Reward participation, not spamming kicks or exploiting the score.
		var earned := int(minf(player.active_seconds, 180.0) / 6.0)
		for entry in entries:
			if entry["id"] == player.player_id:
				entry["xp"] = int(entry["xp"]) + earned
				var growth := minf(float(entry["xp"]) / 1200.0, 1.0)
				report += "%s   +%d XP   •   Touch +%.1f%%   Stamina +%.1f%%   Balance +%.1f%%\n" % [player.player_name, earned, growth * 12, growth * 12, growth * 6]
	completed_matches += 1
	var xp := {}
	for entry in entries:
		xp[entry["id"]] = entry["xp"]
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Could not write squad save."
		return report + last_error
	file.store_string(JSON.stringify({"version": 1, "matches": completed_matches, "xp": xp}, "\t"))
	file.close()
	var result := DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if result != OK:
		last_error = "Could not replace squad save: %s" % error_string(result)
	return report + last_error
