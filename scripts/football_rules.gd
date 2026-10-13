class_name FootballRules
extends RefCounted

const CENTRE_RADIUS := 3.0
const PENALTY_RADIUS := 6.0
const RESTART_DISTANCE := 3.0

static func illegal_position(position: Vector3, team: int, taking_team: int, taker: bool, kind: String, spot: Vector3) -> String:
	if taker:
		return ""
	var own_side := -1.0 if team == 0 else 1.0
	if kind == "kickoff" and position.x * own_side < -.1:
		return "return to your half"
	var distance := Vector2(position.x-spot.x,position.z-spot.z).length()
	if team != taking_team and distance < RESTART_DISTANCE - .05:
		if kind != "kickoff" and position.x * own_side >= 17.8 and absf(position.z) < 2.2:
			return "" # Defenders may stand on their goal line between the posts.
		return "respect the 3 m distance"
	return ""

static func contact_grade(kind: String, detail: Dictionary) -> String:
	if detail.get("violent",false) or (detail.get("studs_up",false) and float(detail.get("speed",0)) > 4):
		return "excessive"
	if detail.get("dangerous_height",false) or detail.get("from_behind",false) and float(detail.get("speed",0)) > 4:
		return "reckless"
	if kind == "slide_body_contact" and detail.get("ball_first",false) and not detail.get("studs_up",false):
		return "legal"
	return "careless"
