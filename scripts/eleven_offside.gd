class_name ElevenOffside
extends RefCounted

const LEVEL_MARGIN := 0.05


static func line(players: Array[FootballPlayer], team: int, attack: float, ball_x: float) -> float:
	var last := -INF
	var second_last := -INF
	for opponent in players:
		if opponent.team == team:
			continue
		# Use player centers and count every opponent, including the keeper and fallen players.
		var depth := _depth(opponent.global_position.x, attack)
		if depth >= last:
			second_last = last
			last = depth
		elif depth > second_last:
			second_last = depth
	return maxf(0.0, maxf(_depth(ball_x, attack), second_last))


static func beyond(player: FootballPlayer, attack: float, line_depth: float) -> bool:
	return _depth(player.global_position.x, attack) > line_depth + LEVEL_MARGIN


static func _depth(x: float, attack: float) -> float:
	return clampf(x * attack, -ElevenPitch.HALF_LENGTH, ElevenPitch.HALF_LENGTH)
