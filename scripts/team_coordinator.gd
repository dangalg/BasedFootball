class_name FootballTeamCoordinator
extends RefCounted

var rng := RandomNumberGenerator.new()
var remaining := 0.0
var chasers: Dictionary = {}
var roles: Dictionary = {}
var possession_team := -1
var possession_age := 10.0
var assignment_signature := ""

func _init() -> void:
	rng.randomize()

func reset() -> void:
	remaining=0
	chasers.clear()
	roles.clear()
	possession_team=-1
	possession_age=10
	assignment_signature=""

func update(players: Array[FootballPlayer], ball: FootballBall, controlled: FootballPlayer, delta: float) -> void:
	possession_age+=delta
	remaining-=delta
	var signature: String=ball.last_touch_id
	var recipients: Dictionary={}
	var precontact_owners: Dictionary={}
	var waiting_receivers: Dictionary={}
	var waiting_points: Dictionary={}
	for player in players:
		if player.sent_off or player.ragdoll!=null or player.hop_active:
			continue
		var accepted: bool=player.action_kind in ["kick","kick_prepare"] and not player.action_has_hit
		var plan:=FootballAI.preparation_for(player)
		if not accepted and plan.is_empty():
			continue
		# Reservation changes team intentions, not possession physics. A real
		# interception or a ball escaping beyond reach releases it immediately.
		if ball.last_touch_id!=player.player_id or not player.reach_ball(ball,1.8):
			continue
		precontact_owners[player.team]=player
		var receiver_id: String=player.accepted_receiver_id if accepted else ""
		var point: Vector3=player.accepted_receive_point
		if not accepted:
			var planned: FootballPlayer=plan.get("receiver")
			if is_instance_valid(planned):
				receiver_id=planned.player_id
				point=plan.get("receive_point",planned.global_position)
		signature+="/prepare/"+player.player_id+"/"+str(player.accepted_action_id)+"/"+receiver_id
		for teammate in players:
			if teammate.player_id==receiver_id and teammate.team==player.team and not teammate.sent_off and teammate.upright_ready():
				waiting_receivers[player.team]=teammate
				waiting_points[teammate.player_id]=point if point.is_finite() else teammate.global_position
				break
	for player in players:
		if player.incoming_pass_remaining<=0:
			continue
		if player.sent_off or not player.upright_ready() or ball.last_touch_id!=player.incoming_pass_from:
			player.incoming_pass_remaining=0
			continue
		recipients[player.team]=player
		signature+="/"+player.player_id
	# Contact, interception and a new delivery change jobs immediately. Spatial
	# support decisions retain their human reaction cadence between events.
	if remaining>0 and signature==assignment_signature:
		return
	assignment_signature=signature
	remaining=rng.randf_range(.16,.24)
	var holder: FootballPlayer
	for player in players:
		if precontact_owners.get(player.team)==player:
			holder=player
			continue
		if player.sent_off or not player.upright_ready():
			continue
		# A pass travelling beside its kicker is a free ball, not possession
		# reassigned to that capsule. Control follows actual foot-touch state.
		var preparing: bool=player.retrieval_positioning and player.reach_ball(ball,1.3) and ball.linear_velocity.length()<1.5
		if not recipients.has(player.team) and ball.last_touch_id==player.player_id and (player.controlling_ball() or preparing):
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
		var recipient: FootballPlayer=recipients.get(team)
		var precontact_owner: FootballPlayer=precontact_owners.get(team)
		var waiting: FootballPlayer=waiting_receivers.get(team)
		var best:=INF
		for player in squad:
			if not player.upright_ready():
				continue
			var cost:=player.global_position.distance_to(ball.global_position)/player.pace
			if player.player_id==chasers.get(team,""):
				cost-=.18
			if player==controlled and holder!=player and player.intent.length_squared()<.01:
				cost+=1.5
			if holder==player:
				cost-=4
			if cost<best:
				best=cost
				chaser=player
		# A delivery owns its one receiver job until real cushioning contact,
		# interception, loss of eligibility or assignment expiry.
		if recipient!=null:
			chaser=recipient
		elif precontact_owner!=null:
			chaser=precontact_owner
		if chaser==null:
			continue
		chasers[team]=chaser.player_id
		var attacking: bool = (holder!=null and holder.team==team) or recipient!=null or (holder==null and ball.last_touch_team==team and possession_team==team and possession_age<.8)
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
		var mark_index:=0
		for player in squad:
			player.tactical_chaser_id=chaser.player_id
			player.tactical_own_possession=attacking
			if player==waiting and player!=recipient:
				# An accepted or committed preparation pass gives its recipient an
				# opening/waiting job. It must not charge the still-owned ball.
				player.tactical_role="pass_wait"
				player.tactical_target=waiting_points[player.player_id]
			elif player==chaser:
				player.tactical_role="receive" if player==recipient else "carry" if attacking else "press"
				player.tactical_target=FootballAI._intercept(player,ball)
				if player==recipient:
					player.tactical_target=FootballAI.receive_target(player,ball)
				elif attacking and holder==player:
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
					var threat:=threats[mini(mark_index,threats.size()-1)]
					mark_index+=1
					player.tactical_target=threat.global_position+(own_goal-threat.global_position).normalized()*1.1
					if threat.global_position.distance_to(own_goal)>carrier_point.distance_to(own_goal):
						# Screen the passing lane near its receiver, not beside the carrier.
						player.tactical_target=threat.global_position.lerp(carrier_point,.18)+(own_goal-threat.global_position).normalized()*1.1
				else:
					player.tactical_target=own_goal.lerp(ball.global_position,.45)+Vector3(0,0,(support_index*2-1)*2)
				support_index+=1
			if player!=chaser and player!=waiting:
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
	if player.support_requested>0:
		home=carrier.global_position+Vector3(-attack*2.5,0,-3.0 if slot==0 else 3.0)
	elif player.run_requested>0:
		home=carrier.global_position+Vector3(attack*6,0,-4.0 if slot==0 else 4.0)
	for advance in [-2.0,0.0,2.0]:
		for lateral in [-2.0,0.0,2.0]:
			var candidate:=home+Vector3(attack*advance,0,lateral)
			candidate.x=clampf(candidate.x,-16,16)
			candidate.z=clampf(candidate.z,-10,10)
			var clearance:=FootballAI.lane_clearance(carrier.global_position,candidate,players,player.team)
			var score:=minf(clearance,4)*2-maxf(0,1.2-clearance)*6
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
	# Keep a useful open run instead of flipping between equivalent samples at
	# every decision. This changes intent only; no positions are enforced.
	if player.tactical_role in ["run","support"]:
		var previous:=player.tactical_target
		if previous.distance_to(home)<3.2 and FootballAI.lane_clearance(carrier.global_position,previous,players,player.team)>1.2:
			var previous_score:=minf(FootballAI.lane_clearance(carrier.global_position,previous,players,player.team),4)*2-previous.distance_to(player.global_position)*.12
			for other in players:
				if other==player or other==carrier or other.sent_off:
					continue
				var gap:=previous.distance_to(other.global_position)
				previous_score-=maxf(0,3.5-gap)*(2 if other.team==player.team else 1)
				previous_score+=minf(gap,4)*.2 if other.team!=player.team else 0
			if previous_score>=best-.65:
				chosen=previous
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
