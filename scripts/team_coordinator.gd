class_name FootballTeamCoordinator
extends RefCounted

var rng := RandomNumberGenerator.new()
var remaining := 0.0
var chasers: Dictionary = {}
var roles: Dictionary = {}
var possession_team := -1
var possession_age := 10.0

func _init() -> void:
	rng.randomize()

func update(players: Array[FootballPlayer], ball: FootballBall, controlled: FootballPlayer, delta: float) -> void:
	possession_age+=delta
	remaining-=delta
	if remaining>0:
		return
	remaining=rng.randf_range(.16,.24)
	var holder: FootballPlayer
	var closest:=1.15
	for player in players:
		if player.sent_off or not player.upright_ready():
			continue
		var gap:=player.global_position.distance_to(ball.global_position)
		if gap<closest:
			closest=gap
			holder=player
	if holder!=null:
		possession_team=holder.team
		possession_age=0
	for team in range(2):
		var squad: Array[FootballPlayer]=[]
		var threats: Array[FootballPlayer]=[]
		for player in players:
			if player.sent_off:
				continue
			if player.team==team:
				squad.append(player)
			elif player!=holder:
				threats.append(player)
		if squad.is_empty():
			continue
		var attack:=1.0 if team==0 else -1.0
		var own_goal:=Vector3(-attack*17.7,0,0)
		var chaser: FootballPlayer
		var best:=INF
		for player in squad:
			if not player.upright_ready():
				continue
			var cost:=player.global_position.distance_to(ball.global_position)/player.pace
			if player.player_id==chasers.get(team,""):
				cost-=.18
			if player==controlled and holder!=player and player.intent.length_squared()<.01:
				cost+=1.5
			if player.incoming_pass_remaining>0 and ball.last_touch_id==player.incoming_pass_from:
				cost-=3
			if holder==player:
				cost-=4
			if cost<best:
				best=cost
				chaser=player
		if chaser==null:
			continue
		chasers[team]=chaser.player_id
		var attacking: bool = holder!=null and holder.team==team or chaser.incoming_pass_remaining>0 and ball.last_touch_team==team or holder==null and possession_team==team and possession_age<.8
		threats.sort_custom(func(a: FootballPlayer,b: FootballPlayer): return a.global_position.distance_squared_to(own_goal)<b.global_position.distance_squared_to(own_goal))
		# Pick the covering player by suitability, retaining that job when costs are
		# close. Array order must not decide who abandons an opponent to chase.
		var cover: FootballPlayer
		var cover_cost:=INF
		for candidate in squad:
			if candidate==chaser:
				continue
			var cost:=candidate.global_position.distance_to(own_goal)
			if candidate.role=="Anchor":
				cost-=3
			if candidate==controlled and candidate.intent.length_squared()<.01:
				cost+=3
			if roles.get(candidate.player_id,"")=="cover":
				cost-=2.0
			if cost<cover_cost:
				cover_cost=cost
				cover=candidate
		var support_index:=0
		for player in squad:
			player.tactical_chaser_id=chaser.player_id
			player.tactical_own_possession=attacking
			if player==chaser:
				player.tactical_role="receive" if player.incoming_pass_remaining>0 else "carry" if attacking else "press"
				player.tactical_target=FootballAI._intercept(player,ball)
				if attacking and player.incoming_pass_remaining<=0:
					player.tactical_target=_carry_route(player,players,attack)
				elif holder!=null and holder.team!=team:
					player.tactical_target=holder.global_position+(own_goal-holder.global_position).normalized()*.9
			elif attacking:
				player.tactical_role="run" if player.role=="Runner" else "support"
				player.tactical_target=_open_space(player,chaser,players,attack,0 if player.role=="Runner" else 1)
				support_index+=1
			else:
				player.tactical_role="cover" if player==cover else "mark"
				var carrier_point: Vector3 = holder.global_position if holder!=null else ball.global_position
				var depth:=carrier_point.distance_to(own_goal)
				if player==cover:
					var distance:=clampf(depth*.4,4.8,7.0)
					player.tactical_target=carrier_point+(own_goal-carrier_point).normalized()*distance
					player.tactical_target.z+=-1.5 if carrier_point.z>0 else 1.5
				elif not threats.is_empty():
					var threat:=threats[0]
					player.tactical_target=threat.global_position+(own_goal-threat.global_position).normalized()*1.1
					if threat.global_position.distance_to(own_goal)>carrier_point.distance_to(own_goal):
						# Screen the passing lane near its receiver, not beside the carrier.
						player.tactical_target=threat.global_position.lerp(carrier_point,.18)+(own_goal-threat.global_position).normalized()*1.1
				else:
					player.tactical_target=own_goal.lerp(ball.global_position,.45)+Vector3(0,0,(support_index*2-1)*2)
				support_index+=1
			if player!=chaser:
				# Tactical spacing changes intent only. Players can still collide,
				# be displaced or converge briefly while reacting to a turnover.
				var gap:=player.tactical_target-ball.global_position
				gap.y=0
				var spacing:=3.2 if ball.global_position.distance_to(own_goal)<5 else 4.5
				if gap.length()<spacing:
					var away: Vector3 = (own_goal-ball.global_position).normalized() if player==cover and not attacking else Vector3(0,0,-1 if player.shirt_number%2==0 else 1)
					if gap.length()>.5:
						away=gap.normalized()
					player.tactical_target=ball.global_position+away*spacing
			roles[player.player_id]=player.tactical_role
			var edge_x:=17.55 if player==chaser else 17.4
			var edge_z:=11.55 if player==chaser else 11.3
			player.tactical_target.x=clampf(player.tactical_target.x,-edge_x,edge_x)
			player.tactical_target.z=clampf(player.tactical_target.z,-edge_z,edge_z)

func _open_space(player: FootballPlayer, carrier: FootballPlayer, players: Array[FootballPlayer], attack: float, slot: int) -> Vector3:
	var best:=-INF
	var chosen:=player.global_position
	var home:=role_area(player,carrier.global_position)
	for advance in [-2.0,0.0,2.0]:
		for lateral in [-2.0,0.0,2.0]:
			var candidate:=home+Vector3(attack*advance,0,lateral)
			candidate.x=clampf(candidate.x,-16,16)
			candidate.z=clampf(candidate.z,-10,10)
			var score:=FootballAI.lane_clearance(carrier.global_position,candidate,players,player.team)*2
			for other in players:
				if other==player or other==carrier or other.sent_off:
					continue
				var gap:=candidate.distance_to(other.global_position)
				score-=maxf(0,3.5-gap)*(2 if other.team==player.team else 1)
				score+=minf(gap,4)*.2 if other.team!=player.team else 0
			score-=candidate.distance_to(player.global_position)*.12
			score+=rng.randf_range(-.1,.1)
			if score>best:
				best=score
				chosen=candidate
	return chosen

static func role_area(player: FootballPlayer, ball_position: Vector3) -> Vector3:
	var attack:=1.0 if player.team==0 else -1.0
	var progress:=ball_position.x*attack
	var side: float = -1 if ball_position.z>=0 else 1
	if player.role=="Anchor":
		return Vector3(attack*clampf(progress-6,-14,4),0,clampf(ball_position.z*.35,-4,4))
	if player.role=="Creator":
		return Vector3(attack*clampf(progress-1,-10,10),0,clampf(ball_position.z*.35-side*4,-8,8))
	return Vector3(attack*clampf(progress+4,-5,15),0,clampf(ball_position.z*.25+side*5,-9,9))

func _carry_route(player: FootballPlayer, players: Array[FootballPlayer], attack: float) -> Vector3:
	var best:=-INF
	var chosen:=player.global_position+Vector3(attack*5,0,0)
	for lateral in [-2.5,0.0,2.5]:
		var candidate:=player.global_position+Vector3(attack*4,0,lateral)
		candidate.z=clampf(candidate.z,-10.5,10.5)
		var score:=FootballAI.lane_clearance(player.global_position,candidate,players,player.team)*2-absf(candidate.z)*.1
		if score>best:
			best=score
			chosen=candidate
	return chosen
