class_name FootballReferee
extends RefCounted

var game: Node3D
var actor: FootballPlayer
var rng := RandomNumberGenerator.new()
var focus := Vector3.ZERO
var attention_remaining := 0.0
var clock := 0.0
var warnings: Dictionary = {}
var last_incident: Dictionary = {}
var return_delay: Dictionary = {}
var last_distance: Dictionary = {}
var yellow: Dictionary = {}
var fouls: Dictionary = {}
var boundary: Node3D
var card: MeshInstance3D
var gesture_remaining := 0.0
var gesture_target: FootballPlayer
var mark_state := ""
var mark_spot := Vector3.ZERO
var mark_angle := 0.0
var mark_progress := 0.0
var drawn_progress := 0.0
var advantage: Dictionary = {}
var current_restart_id := -1

func begin_restart(id: int) -> void:
	current_restart_id=id
	return_delay.clear()
	last_distance.clear()
	# Positional warnings belong to this incident; card history belongs to match.
	warnings.clear()
	gesture_target=null
	gesture_remaining=0

func build(match_node: Node3D) -> void:
	game = match_node
	rng.randomize()
	actor = FootballPlayer.new()
	actor.team = -1
	actor.player_id = "referee"
	actor.player_name = "REFEREE"
	actor.shirt_number = 0
	actor.mass = 74
	actor.pace = 6.3
	game.add_child(actor)
	actor.global_position = Vector3(0,.06,5)
	boundary = Node3D.new()
	boundary.name = "RefereeGroundMark"
	game.add_child(boundary)
	card = FootballArt.box(actor.visual_controller.right_elbow, Vector3(.08,.115,.012), Vector3(0,-.29,0), FootballArt.material(Color("f4dc34")))
	card.hide()

func sees(point: Vector3, excluded_players: Array = []) -> bool:
	if actor.ragdoll != null:
		return false
	var eye := actor.visual_controller.head_pivot.global_position + Vector3.UP * .13
	var offset := point + Vector3.UP - eye
	var facing := -actor.visual_controller.head_pivot.global_basis.z
	if offset.length() > 19 or facing.normalized().dot(offset.normalized()) < .5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(eye, point + Vector3.UP, 1 | 8)
	var excluded: Array[RID] = [actor.get_rid(), game.ball.get_rid()]
	for player in excluded_players:
		excluded.append(player.get_rid())
		if player.ragdoll != null:
			for body in player.ragdoll.bodies:
				excluded.append(body.get_rid())
	ray.exclude = excluded
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func tick(delta: float) -> void:
	clock += delta
	if not advantage.is_empty():
		if game.goal_flow.active:
			advantage.clear()
		elif clock > float(advantage.deadline):
			game._record("advantage_realised",null)
			advantage.clear()
		elif not _team_can_play(int(advantage.team)):
			game.goal_flow.begin_free_kick(game,int(advantage.team),advantage.spot)
			advantage.clear()
	gesture_remaining = maxf(0, gesture_remaining - delta)
	attention_remaining -= delta
	if attention_remaining <= 0:
		attention_remaining = rng.randf_range(.65,1.5)
		focus = game.ball.global_position
		if rng.randf() < .25:
			focus = game.players[rng.randi_range(0,game.players.size()-1)].global_position
	var destination: Vector3 = observation_target()
	if mark_state != "":
		destination = _mark_tick(delta)
	if game.goal_flow.active and game.goal_flow.state in ["kickoff_prepare","ready","kickoff_pending"]:
		_enforce_returns(delta)
		if mark_state == "" and gesture_target != null and gesture_remaining > 0:
			destination = gesture_target.global_position + Vector3(0,0,2.5)
	if gesture_remaining > 0 and is_instance_valid(gesture_target):
		focus = gesture_target.global_position
	actor.intent = (destination - actor.global_position) * Vector3(1,0,1)
	var stop_distance := .2 if mark_state != "" else 1.5
	actor.intent = actor.intent.normalized() * minf(actor.intent.length()*1.3,.3 if mark_state=="drawing" else .85) if actor.intent.length() > stop_distance else Vector3.ZERO
	if mark_state=="" and not game.goal_flow.active:
		for player in game.players:
			var away: Vector3 = (actor.global_position-player.global_position)*Vector3(1,0,1)
			if away.length()>.05 and away.length()<2:
				actor.intent+=away.normalized()*(2-away.length())
		actor.intent=actor.intent.limit_length(1)
	actor.aim = ((focus - actor.global_position) * Vector3(1,0,1)).normalized()
	actor.emotion = "ref_card" if card.visible else "ref_warn" if gesture_remaining > 0 else ""
	if mark_state == "drawing":
		actor.emotion = "ref_draw"
	if gesture_remaining <= 0:
		card.hide()
		gesture_target = null
	_tick_sendoffs()

func observation_target() -> Vector3:
	var chosen:=actor.global_position
	var best:=-INF
	for x in [-4.0,0.0,4.0]:
		for z in [-7.0,7.0]:
			var candidate: Vector3 = game.ball.global_position+Vector3(x,0,z)
			candidate.x=clampf(candidate.x,-16,16)
			candidate.z=clampf(candidate.z,-10.5,10.5)
			var score: float = -candidate.distance_to(actor.global_position)*.2
			for player in game.players:
				if player.sent_off:
					continue
				score-=maxf(0,3-candidate.distance_to(player.global_position))*4
				var goal:=Vector3(18 if player.team==0 else -18,0,0)
				var segment: Vector3 = goal-player.global_position
				var along: float = (candidate-player.global_position).dot(segment)/maxf(.01,segment.length_squared())
				if along>0 and along<1:
					score-=maxf(0,2.5-candidate.distance_to(player.global_position+segment*along))*6
				for teammate in game.players:
					if teammate==player or teammate.team!=player.team:
						continue
					segment=teammate.global_position-player.global_position
					along=(candidate-player.global_position).dot(segment)/maxf(.01,segment.length_squared())
					if along>0 and along<1:
						score-=maxf(0,1.8-candidate.distance_to(player.global_position+segment*along))*3
			if score>best:
				best=score
				chosen=candidate
	return chosen

func observe(kind: String, detail: Dictionary, offender: FootballPlayer) -> void:
	if offender.sent_off or kind not in ["push_contact","grab_contact","slide_body_contact"]:
		return
	var victim: FootballPlayer = null
	for player in game.players:
		if player.player_id == detail.get("victim",""):
			victim = player
	if victim == null and detail.get("victim","") == "referee":
		victim = actor
	if victim == null:
		return
	var point := (offender.global_position + victim.global_position) * .5
	if not sees(point, [offender,victim]):
		game._record("unseen_contact", offender, {"contact":kind})
		return
	if clock - float(last_incident.get(offender.player_id,-10)) < 1:
		return
	last_incident[offender.player_id] = clock
	var grade := FootballRules.contact_grade(kind,detail)
	if grade == "legal":
		return
	if grade == "careless" and not game.goal_flow.active and _team_can_play(victim.team):
		advantage = {"team":victim.team,"spot":point,"deadline":clock+3}
		game.hud.flash("ADVANTAGE — PLAY ON",2)
		game._record("advantage",offender)
		return
	if grade == "excessive":
		_show_card(offender, true, "dangerous contact")
	elif grade == "reckless":
		_show_card(offender, false, "reckless or repeated foul")
	else:
		var recent: Array = fouls.get(offender.player_id,[]).filter(func(t): return clock-float(t)<30)
		recent.append(clock)
		fouls[offender.player_id] = recent
		if recent.size() >= 3:
			_show_card(offender,false,"persistent fouls")
			fouls[offender.player_id] = []
		else:
			_warn(offender,"foul",point)
	if not game.goal_flow.active and victim != actor:
		game.goal_flow.begin_free_kick(game, victim.team, point)

func _team_can_play(team: int) -> bool:
	var friendly := INF
	var opposing := INF
	for player in game.players:
		if player.sent_off or not player.upright_ready():
			continue
		var distance: float = player.global_position.distance_to(game.ball.global_position)
		if player.team == team:
			friendly = minf(friendly,distance)
		else:
			opposing = minf(opposing,distance)
	return friendly < 1.5 and friendly < opposing

func _warn(player: FootballPlayer, reason: String, mark: Vector3) -> void:
	warnings[player.player_id] = reason
	gesture_target = player
	gesture_remaining = 3
	focus = player.global_position
	game.hud.flash("%s — WARNING: %s" % [player.player_name,reason.to_upper()],3)
	game.sound.play_event("whistle")
	game._record("referee_warning",player,{"reason":reason})

func start_marking(spot: Vector3, team: int) -> void:
	for child in boundary.get_children():
		child.queue_free()
	mark_spot = spot
	var preferred := Vector3(18 if team == 0 else -18,0,0)-spot
	var best := INF
	for i in range(64):
		var angle := i*TAU/64
		var valid := true
		for edge in [-.13,.13]:
			var point := spot+Vector3(cos(angle+edge),0,sin(angle+edge))*FootballRules.RESTART_DISTANCE
			valid = valid and absf(point.x)<17.6 and absf(point.z)<11
		if valid:
			var direction := Vector3(cos(angle),0,sin(angle))
			var cost := 1-direction.dot(preferred.normalized())
			if cost < best:
				best = cost
				mark_angle = angle
	mark_progress = 0
	drawn_progress = 0
	mark_state = "walking"

func _mark_point(progress: float) -> Vector3:
	var angle := mark_angle-.12+progress*.24
	return mark_spot+Vector3(cos(angle),0,sin(angle))*FootballRules.RESTART_DISTANCE

func _mark_tick(delta: float) -> Vector3:
	var destination := _mark_point(mark_progress)
	if mark_state == "walking" and actor.global_position.distance_to(destination) < .55:
		mark_state = "drawing"
		game._record("referee_draw_start",null)
	if mark_state == "drawing" and actor.global_position.distance_to(destination) < .55 and actor.visual_controller.right_boot.global_position.distance_to(destination+Vector3.UP*.075) < .4:
		mark_progress = minf(1,mark_progress+delta*.45)
		var next := _mark_point(mark_progress)
		if mark_progress-drawn_progress >= .02 or mark_progress >= 1:
			FootballArt.line(boundary,_mark_point(drawn_progress)+Vector3.UP*.03,next+Vector3.UP*.03,.065,FootballArt.material(Color("e5d9b5")))
			drawn_progress = mark_progress
		destination = next
		if mark_progress >= 1:
			mark_state = "stepping_away"
	if mark_state == "stepping_away":
		destination = _mark_point(1)+(_mark_point(1)-mark_spot).normalized()*1.1
		if absf(destination.x)>17.6 or absf(destination.z)>11:
			destination = _mark_point(1)-(_mark_point(1)-mark_spot).normalized()*1.1
		if actor.global_position.distance_to(destination) < .4:
			mark_state = ""
			game._record("referee_draw_complete",null)
	return destination

func _show_card(player: FootballPlayer, red: bool, reason: String) -> void:
	if player.sent_off:
		return
	if not red:
		yellow[player.player_id] = int(yellow.get(player.player_id,0)) + 1
		red = yellow[player.player_id] >= 2
	card.material_override = FootballArt.material(Color("ed473e") if red else Color("f4dc34"))
	card.show()
	gesture_target = player
	gesture_remaining = 3
	focus = player.global_position
	warnings[player.player_id] = reason
	game.sound.play_event("whistle")
	game.hud.flash("%s — %s" % [player.player_name,"RED CARD / SENT OFF" if red else "YELLOW CARD"],3)
	game._record("red_card" if red else "yellow_card",player,{"reason":reason})
	if red:
		player.sent_off = true
		player.buffered_remaining = 0
		player.dribble_active = false
		player.grab_held = false
		player.emotion = "sad"
		player.selected = false
		if game.controlled == player:
			for i in range(3):
				if not game.players[i].sent_off:
					game._select(i)
					break
		if game.players.filter(func(p: FootballPlayer): return p.team == player.team and not p.sent_off).is_empty():
			game._finish_match()
			game.hud.flash("MATCH ABANDONED — NO PLAYERS LEFT",5)

func _enforce_returns(delta: float) -> void:
	for player in game.players:
		if player.sent_off or player==game.goal_flow.runner:
			continue
		var reason: String = game.goal_flow.position_reason(player)
		var target: Vector3 = game.goal_flow.targets[player.player_id]
		# Forgive progress toward any legal position, not an AI formation slot.
		var own: float=-1 if player.team==0 else 1
		var distance: float=maxf(0,-player.global_position.x*own) if reason=="return to your half" else maxf(0,FootballRules.RESTART_DISTANCE-Vector2(player.global_position.x-game.goal_flow.restart_spot.x,player.global_position.z-game.goal_flow.restart_spot.z).length())
		var previous := float(last_distance.get(player.player_id,distance))
		last_distance[player.player_id] = distance
		var waiting := float(return_delay.get(player.player_id,0))
		if reason == "" or previous - distance > delta * .35 or player.ragdoll != null:
			return_delay[player.player_id] = 0
			continue
		waiting += delta
		return_delay[player.player_id] = waiting
		if waiting < 6:
			continue
		# Approach the player before warning; turning away or an obstruction
		# really can hide the next breach. There is no retrospective card.
		gesture_target = player
		gesture_remaining = maxf(gesture_remaining,.2)
		focus = player.global_position
		if actor.global_position.distance_to(player.global_position) > 4 or not sees(player.global_position,[player]):
			continue
		if warnings.get(player.player_id,"") != reason:
			_warn(player,reason,target)
		else:
			if not last_incident.has(player.player_id) or clock-float(last_incident[player.player_id]) > 10:
				_show_card(player,false,"deliberately delaying the restart")
				last_incident[player.player_id] = clock
		warnings[player.player_id] = reason
		return_delay[player.player_id] = 0 # A fresh, visible breach must persist.

func _tick_sendoffs() -> void:
	for player in game.players:
		if not player.sent_off or player.freeze:
			continue
		var side := -1.0 if player.team == 0 else 1.0
		var target := Vector3(0,.06,side * 14.5)
		var offset: Vector3 = (target - player.global_position) * Vector3(1,0,1)
		player.intent = offset.normalized() * .65
		player.aim = player.intent.normalized()
		if absf(player.global_position.z) > 10.6 and absf(player.global_position.z) < 11.8 and player.hop():
			player.apply_central_impulse(Vector3.UP * player.mass * 1.5)
		if absf(player.global_position.z) > 13.5 and player.global_position.y < .12:
			player.intent = Vector3.ZERO
			player.freeze = true
			player.hide()
			game._record("left_field",player)

func reset() -> void:
	advantage.clear()
	mark_state = ""
	gesture_remaining = 0
	gesture_target = null
	actor.intent = Vector3.ZERO
	actor.global_position = Vector3(0,.06,5)
	warnings.clear()
	yellow.clear()
	fouls.clear()
	return_delay.clear()
	last_distance.clear()
	last_incident.clear()
	card.hide()
	for child in boundary.get_children():
		child.queue_free()
	for player in game.players:
		player.sent_off = false
		player.freeze = false
		player.show()
