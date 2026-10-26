extends RefCounted
## Formats the authority's match state (`state.match`, see authority/main.gd _match_state) into the
## models OnlineScreens draws. Pure presentation: no rules. Shared by the online client and the
## offline test lab (test_lab/).
const WalkInLobby = preload("res://network/walk_in_lobby.gd")
const TeamCast = preload("res://style/team_cast.gd")
const TouchControls = preload("res://client/touch_controls.gd")

## The device the prompts speak to: "touch" (a phone or the touch overlay), "pad" (a gamepad is connected and was used last), else "keyboard".
static func input_kind(tree: SceneTree) -> String:
	if TouchControls.touch_hints(tree): return "touch"
	if TouchControls.last_device == "pad" and not Input.get_connected_joypads().is_empty(): return "pad"
	return "keyboard"

## What the lobby says while everybody stands on one circle: PLAY is a key on a keyboard, Y on a pad and a button on a phone (docs/walk-in-lobby.md).
static func play_prompt(input: String) -> String:
	match input:
		"touch": return "Tap PLAY to start"
		"pad": return "Press Y to start"
	return "Press Enter to start"

static func seat_color(seat: int) -> Color:
	return TeamCast.player_color(seat)

## The walk-in lobby (docs/walk-in-lobby.md) for the HUD and the pads: members with the pad they
## stand on, the countdown, one short hint, and per pad who stands on it. `solo` (the offline
## lab) shows only this player: its partner seat is a test fixture, not a person.
static func lobby_model(match_info: Dictionary, seat_count: int, my_seat: int, solo := false, input := "keyboard") -> Dictionary:
	var names: Array = match_info.get("names", [])
	var zones: Array = match_info.get("zones", [])
	var joined_mask := int(match_info.get("joined", 0))
	var ready_mask := int(match_info.get("ready", joined_mask)) # a seat is "ready" once its client is in the world; a state without the mask counts every joined seat
	var members := []
	var loading := [] ## names of joined seats whose client is still loading
	for seat in seat_count:
		if (joined_mask >> seat) & 1 == 0: continue
		if solo and seat != my_seat: continue
		if (ready_mask >> seat) & 1 == 0 and seat != my_seat:
			loading.append(str(names[seat]) if seat < names.size() and str(names[seat]) != "" else "Partner")
			continue
		var zone := str(zones[seat]) if seat < zones.size() else ""
		members.append({"seat": seat, "name": str(names[seat]) if seat < names.size() else "", "zone": zone, "on_pad": zone != "", "me": seat == my_seat, "color": seat_color(seat)})
	var me := {}
	var partner := {}
	for member: Dictionary in members:
		if member.me: me = member
	# The hint names one other player: the first who does not stand where this player stands (2 to 10 players).
	for member: Dictionary in members:
		if member.me: continue
		if partner.is_empty() or (partner.zone == str(me.get("zone", "")) and member.zone != str(me.get("zone", ""))): partner = member
	var start_in := float(match_info.get("start_in", -1.0))
	var pick := str(match_info.get("pick", ""))
	var ready_pad := str(match_info.get("ready_pad", ""))
	var hint := ""
	if not solo and start_in < 0.0:
		var partner_name := str(partner.get("name", "")) if str(partner.get("name", "")) != "" else "Partner"
		if not loading.is_empty(): hint = "%s is loading..." % loading[0]
		elif partner.is_empty(): hint = "Waiting for your partner..."
		elif str(me.get("zone", "")) != "" and partner.zone != me.zone: hint = "Waiting for %s" % partner_name
		elif partner.zone != "" and partner.zone != str(me.get("zone", "")): hint = "%s is on %s" % [partner_name, WalkInLobby.title(partner.zone).capitalize()]
	var can_play := start_in < 0.0 and ready_pad != "" and str(me.get("zone", "")) == ready_pad # everybody is on it: PLAY starts the countdown
	if can_play: hint = play_prompt(input)
	var pads := []
	for entry: Dictionary in WalkInLobby.shown_pads():
		var on: Array = members.filter(func(member: Dictionary) -> bool: return member.zone == entry.course)
		pads.append({"course": entry.course, "title": entry.title, "subtitle": entry.subtitle, "occupants": on, "counting": pick == entry.course and start_in >= 0.0, "start_in": start_in if pick == entry.course else -1.0})
	return {"seat_count": seat_count, "joined": members.size(), "solo": solo, "hint": hint, "start_in": start_in, "pick": pick, "pick_title": WalkInLobby.title(pick), "ready_pad": ready_pad, "can_play": can_play, "input": input,
		"members": [] if solo else members, "lamps": members, "pads": pads}

static func results_model(match_info: Dictionary, my_seat: int) -> Dictionary:
	var rows := []
	var choices: Array = match_info.get("choices", [])
	for row: Dictionary in match_info.get("rows", []):
		var seat := int(row.seat)
		var choice := str(choices[seat]) if seat < choices.size() and str(choices[seat]) != "" else "pending"
		rows.append({"seat": seat, "name": str(row.name), "color": seat_color(seat), "me": seat == my_seat, "time": float(row.time), "panes_intact": int(row.panes_intact), "breaks": int(row.breaks), "arrived": bool(row.arrived), "choice": choice,
			"rank": int(row.get("rank", 0)), "points": int(row.get("points", 0))})
	var remaining := 0
	for row: Dictionary in rows:
		if row.choice in ["pending", "again"]: remaining += 1
	return {"round": int(match_info.get("round", 0)), "headline": str(match_info.get("headline", "")), "sub": str(match_info.get("sub", "")), "choose_in": float(match_info.get("choose_in", 0.0)), "remaining": remaining, "rows": rows,
		"course": str(match_info.get("round_course", "")), "reason": str(match_info.get("reason", "")), "time_limit": float(match_info.get("time_limit", -1.0)),
		"run": match_info.get("run", {})}
