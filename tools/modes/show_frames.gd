extends SceneTree
## Brand frames of the show's three levels with a free camera: the start gate and arch, the obstacle boxes, a mid-course view, the hot
## floor, the climb, the crown. The project's own demo/cast is what you see (copy a brand sample into demo/cast of a project clone first),
## so run it once per brand. Offscreen binary only, never windowed, about 10 s per run:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s "$PWD/tools/modes/show_frames.gd" -- --shots=<dir> [--prefix=tw_] [--only=name,name]
## Positions are relative to the level's origin (-Z is forward along the course). Prints SHOW_FRAMES lines.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const WalkInMarkers := preload("res://client/walk_in_markers.gd")
const FollowCamera := preload("res://game/follow_camera.gd")

## [name, level (0-based), eye, look-at, level clock, couriers at these spots (relative, may be empty), optional step tiles of the shot]
## The step tiles of LAST TILE STANDING (level index 14) are a dictionary: "trail": [[from, to, step clock at `from`, m/s], ...] = a runner's footsteps,
## stepping the tile under it every 0.25 m; "air": [courier numbers] = those couriers are falling (not grounded, velocity down); "clear": [[floor y, radius m, step clock], ...] = every tile of that floor within the radius
## of the level's middle stepped at that clock; "fit": players = the round's start steps for that many players (outer tiles gone); "arcs": [[floor y, radius m, start degrees,
## sweep degrees, step clock at the start, m/s], ...] = a runner on a circle around the level's middle (a trail of any length without listing its legs).
const SHOTS := [
	["r1_start_gate", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 0.0, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	["r1_start_open", 13, Vector3(0.0, 2.6, 3.4), Vector3(0.0, 3.0, -10.0), 5.0, [Vector3(-1.2, 0.0, -2.0), Vector3(1.2, 0.0, -3.0)]],
	["r1_obstacles", 13, Vector3(0.0, 4.5, -14.0), Vector3(0.0, 1.0, -27.0), 0.0, []],
	["r1_midrace", 13, Vector3(0.0, 6.0, -38.0), Vector3(0.0, 2.5, -62.0), 3.0, [Vector3(-2.0, 0.0, -49.0), Vector3(1.5, 0.0, -53.0)]],
	["r1_finish", 13, Vector3(0.0, 4.5, -68.0), Vector3(0.0, 3.5, -83.0), 0.0, []],
	["r3_start_gate", 15, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.5, -10.0), 0.0, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0)]],
	["r3_climb", 15, Vector3(-4.0, 14.0, 6.0), Vector3(14.0, 10.0, -22.0), 3.0, []],
	["r3_summit", 15, Vector3(12.0, 35.0, -28.0), Vector3(12.0, 32.5, -42.0), 0.0, []],
	["p17_doors", 16, Vector3(0.0, 2.4, -18.0), Vector3(0.0, 1.8, -28.0), 5.0, [Vector3(-1.5, 0.0, -21.0), Vector3(1.5, 0.0, -22.0)]],
	["p17_burst_bonk", 16, Vector3(-1.2, 1.9, -23.6), Vector3(-1.6, 1.4, -28.0), 5.0, [Vector3(-3.0, 0.0, -28.05), Vector3(0.0, 0.0, -27.55), Vector3(3.0, 0.0, -27.55)]],
	["p17_finish", 16, Vector3(0.0, 3.0, -100.0), Vector3(0.0, 0.5, -126.0), 5.0, []],
	["p20_doors", 19, Vector3(0.0, 2.6, -24.0), Vector3(0.0, 1.8, -34.0), 5.0, [Vector3(1.5, 0.0, -27.0)]],
	["b19_pads", 18, Vector3(0.0, 2.4, 3.4), Vector3(0.0, 2.5, -20.0), 5.0, [Vector3(-1.2, 0.0, -7.0), Vector3(1.2, 0.0, -9.0)]],
	["b19_flight", 18, Vector3(6.0, 3.5, -12.0), Vector3(0.0, 3.0, -25.0), 5.0, [Vector3(0.0, 3.4, -20.0), Vector3(0.0, 0.1, -11.0)]],
	["b19_halls", 18, Vector3(0.0, 3.0, -46.0), Vector3(0.0, 4.5, -62.0), 7.0, [Vector3(0.0, 0.1, -52.0)]],
	["b19_gauntlet", 18, Vector3(0.0, 5.0, -118.0), Vector3(0.0, 1.0, -136.0), 8.0, [Vector3(-1.5, 0.0, -125.0), Vector3(2.0, 0.0, -132.0)]],
	["m18_grid", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 7.0, [Vector3(-3.0, 0.0, -3.0), Vector3(3.0, 0.0, 3.0), Vector3(0.0, 0.0, 3.0)]],
	["m18_drop", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 11.0, []],
	["t15_arena", 14, Vector3(0.0, 24.0, 38.0), Vector3(0.0, -3.0, 0.0), 4.0, [Vector3(-1.2, 0.05, 0.0), Vector3(1.2, 0.05, 0.0), Vector3(0.0, 0.05, -1.2)], {}],
	["t15_layers", 14, Vector3(-34.0, 13.0, 31.0), Vector3(0.0, -4.0, 0.0), 14.0, [Vector3(5.0, -3.95, 2.165), Vector3(-6.25, 0.05, 2.165)],
		{"clear": [[0.0, 6.5, 5.0], [-4.0, 3.5, 5.0]], "trail": [[Vector3(-8.75, 0.0, -6.25), Vector3(-6.25, 0.0, 6.25), 10.0, 3.4], [Vector3(6.25, -4.0, -6.25), Vector3(1.25, -4.0, 3.75), 12.0, 3.4]]}],
	["t15_trail", 14, Vector3(-9.0, 8.5, 12.0), Vector3(-1.0, -1.0, -1.0), 13.5, [Vector3(-0.5, 0.05, 4.5), Vector3(4.0, 0.05, 2.0)],
		{"trail": [[Vector3(-6.25, 0.0, -6.25), Vector3(-1.25, 0.0, -1.25), 8.4, 3.4], [Vector3(-1.25, 0.0, -1.25), Vector3(-0.5, 0.0, 4.5), 9.9, 3.4], [Vector3(6.25, 0.0, -3.75), Vector3(4.0, 0.0, 2.0), 11.4, 3.4]]}],
	["t15_fall", 14, Vector3(-3.0, -2.2, 15.0), Vector3(-1.5, -1.2, 0.0), 13.0, [Vector3(-1.5, -2.0, 0.0), Vector3(2.0, -3.95, 2.0), Vector3(-4.5, 0.05, 3.5)],
		{"clear": [[0.0, 6.5, 4.5]], "trail": [[Vector3(-6.25, 0.0, -2.0), Vector3(-4.5, 0.0, 3.5), 11.0, 3.4]], "air": [0]}],
	# the hex floors (327 hexagons: 127, 127, 73): ten players on the start ring; a round under way (six runners on circles, two of them falling); the same on a phone
	["t15_big", 14, Vector3(-30.0, 9.0, 26.0), Vector3(0.0, -3.5, 0.0), 4.0, [Vector3(-1.75, 0.05, 0.0), Vector3(-1.42, 0.05, -1.03), Vector3(-0.54, 0.05, -1.66), Vector3(0.54, 0.05, -1.66), Vector3(1.42, 0.05, -1.03), Vector3(1.75, 0.05, 0.0), Vector3(1.42, 0.05, 1.03), Vector3(0.54, 0.05, 1.66), Vector3(-0.54, 0.05, 1.66), Vector3(-1.42, 0.05, 1.03)], {}],
	["t15_bigplay", 14, Vector3(-21.0, 12.0, 23.0), Vector3(0.0, -3.0, 0.0), 9.0, [Vector3(-1.66, 0.05, 3.08), Vector3(-6.0, 0.05, -0.24), Vector3(-4.92, 0.05, -6.93), Vector3(9.66, 0.05, 5.26), Vector3(-10.66, 0.05, 8.28), Vector3(6.35, -3.95, -3.98), Vector3(-2.68, -1.5, -2.25), Vector3(1.75, -2.5, -3.03)],
		{"arcs": [[0.0, 3.5, 200.0, 278.0, 4.0, 3.4], [0.0, 6.0, 20.0, 162.0, 4.0, 3.4], [0.0, 8.5, 120.0, 115.0, 4.0, 3.4], [0.0, 11.0, 300.0, 89.0, 4.0, 3.4], [0.0, 13.5, 70.0, 72.0, 4.0, 3.4], [-4.0, 7.5, 250.0, 78.0, 6.0, 3.4]], "air": [6, 7]}],
	["t15_phone", 14, Vector3(-16.0, 12.0, 21.0), Vector3(0.0, -3.0, 0.0), 9.0, [Vector3(-1.66, 0.05, 3.08), Vector3(-6.0, 0.05, -0.24), Vector3(-4.92, 0.05, -6.93), Vector3(9.66, 0.05, 5.26), Vector3(-10.66, 0.05, 8.28), Vector3(6.35, -3.95, -3.98), Vector3(-2.68, -1.5, -2.25), Vector3(1.75, -2.5, -3.03)],
		{"arcs": [[0.0, 3.5, 200.0, 278.0, 4.0, 3.4], [0.0, 6.0, 20.0, 162.0, 4.0, 3.4], [0.0, 8.5, 120.0, 115.0, 4.0, 3.4], [0.0, 11.0, 300.0, 89.0, 4.0, 3.4], [0.0, 13.5, 70.0, 72.0, 4.0, 3.4], [-4.0, 7.5, 250.0, 78.0, 6.0, 3.4]], "air": [6, 7]}],
	# brand close-ups: a logo tile and rival tiles of LAST TILE STANDING, the crown's plate, an obstacle box, a banner strip
	["t15_logotile", 14, Vector3(-1.25, 2.3, 2.4), Vector3(-1.25, 0.0, -0.6), 4.0, [], {}],
	["t15_rivals", 14, Vector3(-2.0, 3.6, 9.5), Vector3(-4.0, 0.0, 5.0), 4.0, [], {}],
	["r3_crown_plate", 15, Vector3(12.0, 32.15, -39.3), Vector3(12.0, 32.1, -41.0), 0.0, []],
	["r3_cakebox", 15, Vector3(-2.8, 6.6, -20.3), Vector3(-5.2, 5.4, -24.5), 0.0, []],
	["r3_banner", 15, Vector3(0.0, 6.5, -18.0), Vector3(0.0, 7.0, -25.25), 0.0, []],
	["t15_chase", 14, Vector3(-2.2, 4.4, 8.4), Vector3(-2.0, -0.6, -3.0), 11.7, [Vector3(-2.0, 0.05, -3.0)],
		{"trail": [[Vector3(-1.0, 0.0, 9.0), Vector3(-2.0, 0.0, -3.0), 8.0, 3.4]]}],
	["m18_finale", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 52.0, []],
	# poster doors (levels/poster_doors.gd): the 7th element's "burst" / "bump" are [from, to] feet a courier is observed moving between (a burst through a logo poster,
	# a bump on a problem poster), "after" the frames the look runs afterwards; POSTER RUSH (level index 16): row 1 (z -28) has the torn logo poster at x=-3 and problem
	# posters elsewhere, row 2 (z -44) the open logo poster at x=1.25, row 3 (z -60) a sliding one (at rest at x=-2.5 for the first second of the level clock)
	["p17_tear", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 9}],
	["p17_slide", 16, Vector3(-2.5, 2.3, -52.0), Vector3(-2.5, 1.8, -60.0), 0.5, []],
	["p17_bump", 16, Vector3(-1.3, 1.9, -22.4), Vector3(0.0, 1.7, -28.0), 5.0, [Vector3(0.0, 0.0, -27.5)], {"bump": [[Vector3(0.0, 0.0, -27.2), Vector3(0.0, 0.0, -27.52)]], "after": -2}],
	["p17_torn_row", 16, Vector3(0.0, 2.5, -15.0), Vector3(0.0, 1.8, -28.0), 5.0, []],
	# survival has no safe ground (docs/party-show.md "Survival"): the start of PICTURE MATCH (the start pad under the ring, the tiles around it) and of LAST TILE STANDING
	# (the hexagons alone), and CROWN CLIMB's first lift with a courier on it and one walking off onto the platform
	["s60_match_start", 17, Vector3(0.0, 3.6, -9.5), Vector3(0.0, -0.4, 1.5), 4.5, [Vector3(-1.75, 0.0, 0.0), Vector3(0.875, -0.25, -1.516), Vector3(0.875, -0.25, 1.516)]],
	["s61_tiles_start", 14, Vector3(0.0, 9.0, 26.0), Vector3(0.0, -2.0, -1.0), 4.5, [Vector3(-1.2, 0.05, 0.0), Vector3(1.2, 0.05, 0.0), Vector3(0.0, 0.05, -1.2)], {}],
	["s62_lift_section", 15, Vector3(12.5, 14.5, -11.0), Vector3(22.0, 10.0, -22.5), 3.2, [Vector3(20.0, 11.0, -21.6), Vector3(23.4, 11.0, -23.6)]],
	# SHOVE RING (level index 21, the floor shrinks at clock 18 / 32 / 46 / 58 = play 14 / 28 / 42 / 54) and ROLLING ROAD (level index 22: crossing balls, lanes, cannons, the bridge)
	["sr_full", 21, Vector3(0.0, 13.0, 19.5), Vector3(0.0, -1.0, 0.0), 4.0, [Vector3(-1.75, 0.05, 0.0), Vector3(1.75, 0.05, 0.0), Vector3(-0.875, 0.05, 1.516), Vector3(0.875, 0.05, 1.516), Vector3(-0.875, 0.05, -1.516), Vector3(0.875, 0.05, -1.516), Vector3(-5.0, -0.2, 1.5), Vector3(4.5, -0.2, -2.5), Vector3(8.0, -0.45, 3.0), Vector3(-7.5, -0.45, -4.0), Vector3(10.0, -0.7, -3.0), Vector3(-9.5, -0.7, 5.0)]],
	["sr_shrunk", 21, Vector3(0.0, 11.0, 17.5), Vector3(0.0, -1.0, 0.0), 21.0, [Vector3(-1.75, 0.05, 0.0), Vector3(1.75, 0.05, 0.0), Vector3(-0.875, 0.05, 1.516), Vector3(0.875, 0.05, -1.516), Vector3(-5.0, -0.2, 1.5), Vector3(7.5, -0.45, -3.0)]],
	["rr_cross", 22, Vector3(0.0, 5.5, -3.0), Vector3(0.0, 1.6, -17.0), 8.7, [Vector3(-2.0, 0.0, -8.5), Vector3(2.0, 0.0, -9.5)]],
	["rr_lanes", 22, Vector3(0.0, 4.8, -23.0), Vector3(0.0, 1.4, -38.0), 0.2, [Vector3(-1.2, 0.0, -26.0), Vector3(2.5, 0.0, -31.0)]],
	["rr_cannons", 22, Vector3(2.0, 4.0, -50.0), Vector3(-3.0, 1.8, -58.5), 0.9, [Vector3(1.0, 0.0, -54.0)]],
	["rr_bridge", 22, Vector3(0.0, 6.5, -67.0), Vector3(0.0, 0.0, -80.0), 20.0, [Vector3(3.5, 0.0, -73.0)]],
	["rr_garages", 22, Vector3(0.0, 16.0, -9.0), Vector3(0.0, 0.0, -19.0), 8.7, [Vector3(0.0, 0.0, -9.5)]],
	# ROLLING ROAD ball life (level index 22): nothing pops in or out in view. A crossing ball (cross_1, z -13.5, period 7, phase 3, level clock t = m - 3 + 7k for the ball's own time m: it is on the road for m 0..3.75 s of each 7 s)
	# comes out of the left garage's wall slot (10.4 hidden inside, 10.7 half out, 11.0 out), rolls, and goes into the right garage's slot (7.75 touching, 8.1 half in, 8.4 gone)
	["rr_cross_in0", 22, Vector3(0.0, 2.5, -13.5), Vector3(-11.0, 1.75, -13.5), 10.4, []],
	["rr_cross_in1", 22, Vector3(0.0, 2.5, -13.5), Vector3(-11.0, 1.75, -13.5), 10.7, []],
	["rr_cross_in2", 22, Vector3(0.0, 2.5, -13.5), Vector3(-11.0, 1.75, -13.5), 11.0, []],
	["rr_cross_mid", 22, Vector3(0.0, 2.5, -4.0), Vector3(0.0, 1.75, -13.5), 5.5, []],
	["rr_cross_out0", 22, Vector3(0.0, 2.5, -13.5), Vector3(11.0, 1.75, -13.5), 7.75, []],
	["rr_cross_out1", 22, Vector3(0.0, 2.5, -13.5), Vector3(11.0, 1.75, -13.5), 8.1, []],
	["rr_cross_out2", 22, Vector3(0.0, 2.5, -13.5), Vector3(11.0, 1.75, -13.5), 8.4, []],
	# a lane ball (lane_2, x 0, z -49 to -33, phase 1.25, period 5.5, level clock 9.75 + 5.5k is its time 0): rises out of the floor hole (9.35, 9.55), is up at 9.75 and rolls, is at the far end at 12.05 and sinks (12.3, 12.5)
	["rr_lane_in0", 22, Vector3(0.0, 3.5, -40.0), Vector3(0.0, 0.5, -49.0), 9.35, []],
	["rr_lane_in1", 22, Vector3(0.0, 3.5, -40.0), Vector3(0.0, 0.5, -49.0), 9.55, []],
	["rr_lane_in2", 22, Vector3(0.0, 3.5, -40.0), Vector3(0.0, 0.5, -49.0), 9.75, []],
	["rr_lane_mid", 22, Vector3(0.0, 3.5, -27.0), Vector3(0.0, 1.0, -41.0), 10.95, []],
	["rr_lane_out0", 22, Vector3(0.0, 3.5, -26.0), Vector3(0.0, 0.5, -33.0), 12.05, []],
	["rr_lane_out1", 22, Vector3(0.0, 3.5, -26.0), Vector3(0.0, 0.5, -33.0), 12.3, []],
	["rr_lane_out2", 22, Vector3(0.0, 3.5, -26.0), Vector3(0.0, 0.5, -33.0), 12.5, []],
	# one shot of cannon_1 (x -7.25, y 6, z -58.5, period 4, phase 2.25; level clock 5.75 + s): in the barrel (5.75), the flash and the ball coming out (5.87), clear of the muzzle with the puff and the recoil (6.1),
	# the arc (6.35), the first landing at x -1.65 (6.77), the bounces (7.15, 7.65), the roll (8.15), at the far wall's slot (9.02), half in (9.3), gone (9.55)
	["rr_shot_0", 22, Vector3(-2.0, 3.0, -50.0), Vector3(-6.5, 5.5, -58.5), 5.75, []],
	["rr_shot_1", 22, Vector3(-2.0, 3.0, -50.0), Vector3(-6.5, 5.5, -58.5), 5.87, []],
	["rr_shot_2", 22, Vector3(-2.0, 3.0, -50.0), Vector3(-6.5, 5.5, -58.5), 6.1, []],
	["rr_shot_arc", 22, Vector3(4.0, 4.0, -49.0), Vector3(-3.0, 3.0, -58.5), 6.35, []],
	["rr_shot_land", 22, Vector3(4.0, 4.0, -49.0), Vector3(-1.0, 0.8, -58.5), 6.77, []],
	["rr_shot_bounce", 22, Vector3(4.0, 4.0, -49.0), Vector3(1.0, 1.0, -58.5), 7.65, []],
	["rr_shot_roll", 22, Vector3(-4.0, 3.5, -52.0), Vector3(5.0, 0.8, -58.5), 8.15, []],
	["rr_shot_wall0", 22, Vector3(-4.0, 3.5, -52.0), Vector3(8.0, 0.8, -58.5), 9.02, []],
	["rr_shot_wall1", 22, Vector3(-4.0, 3.5, -52.0), Vector3(8.0, 0.8, -58.5), 9.3, []],
	["rr_shot_wall2", 22, Vector3(-4.0, 3.5, -52.0), Vector3(8.0, 0.8, -58.5), 9.55, []],
	# SPIN BARS (level index 20): the pedestal start (clock 5), the bars over the stepped floor with couriers, a courier thrown by the slow bar's tip
	["sb_start", 20, Vector3(0.0, 5.0, 11.5), Vector3(0.0, 0.8, 0.0), 5.0, [Vector3(-1.75, 1.0, 0.0), Vector3(1.75, 1.0, 0.0), Vector3(-0.875, 1.0, 1.516), Vector3(0.875, 1.0, 1.516), Vector3(-0.875, 1.0, -1.516), Vector3(0.875, 1.0, -1.516)]],
	["sb_full", 20, Vector3(0.0, 12.5, 16.5), Vector3(0.0, -0.5, 0.5), 12.5, [Vector3(-4.0, -0.2, 3.5), Vector3(4.5, -0.2, 1.5), Vector3(1.5, 0.05, 2.5), Vector3(-1.0, 0.05, -2.0), Vector3(6.5, -0.45, 4.5), Vector3(-7.0, -0.45, 1.0), Vector3(2.5, 0.05, -4.0)]],
	["sb_bonk", 20, Vector3(-1.0, 3.4, 11.5), Vector3(3.2, 0.6, 3.8), 12.5, [Vector3(4.3, 1.5, 4.7), Vector3(-2.5, -0.2, 6.0), Vector3(-3.5, 0.05, 1.0)], {"air": [0]}],
	# nothing vanishes into nowhere (docs/party-show.md "The look"). A blink platform falls away and climbs back: CIRCUIT BREAKER's gap_1 (level index 13, z -39, on 3 / off 3 / warn 1: solid 0..3,
	# the shake from 2, it falls 3.0 to 3.4 (0.19 m at 3.1, 0.75 at 3.2, 1.7 at 3.3, 3.0 m from 3.4 on), hangs 3 m under its place until 5.5, climbs back 5.5 to 6.0 and is solid again)
	["vn_gap_solid", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 2.9, []],
	["vn_gap_fall1", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 3.1, []],
	["vn_gap_fall2", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 3.2, []],
	["vn_gap_fall3", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 3.3, []],
	["vn_gap_hang", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 4.5, []],
	["vn_gap_rise1", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 5.7, []],
	["vn_gap_rise2", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 5.85, []],
	["vn_gap_back", 13, Vector3(4.0, 3.0, -32.0), Vector3(0.0, -1.2, -39.0), 6.1, []],
	# the start gate (id gate, z -4.75, 17 x 4 x 0.5, on 4, warn 1) shakes 3..4, then sinks into the floor (accelerating, 0.09 m at 4.05, 0.4 m at 4.1, 1.5 m at 4.2, 3.4 m at 4.3, 6 m at 4.4) and falls on, out of sight
	["vn_gate_shake", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 3.7, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	["vn_gate_sink1", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 4.1, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	["vn_gate_sink2", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 4.2, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	["vn_gate_sink3", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 4.3, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	["vn_gate_gone", 13, Vector3(0.0, 2.2, 3.4), Vector3(0.0, 3.2, -8.0), 4.6, [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-3.0, 0.0, 0.8)]],
	# PICTURE MATCH (level index 17): cue 1 ends at 10.0 (its other tiles fall: shake from 9, a tile 0.19 m down at 10.1, 0.75 m at 10.2, 1.7 m at 10.3, out of reach at 10.4), the next picture's tiles come up
	# into place just before it stands at 12.0 (a swoosh from far under: 15 m at 11.0, 2.4 m at 11.6, 0.35 m at 11.85); the late cues end at 43.5 and 52.5, half a second long: gone fast
	["vn_pm_shake", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 9.6, []],
	["vn_pm_drop1", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 10.1, []],
	["vn_pm_drop2", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 10.25, []],
	["vn_pm_drop3", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 10.4, []],
	["vn_pm_drop4", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 10.7, []],
	["vn_pm_rise1", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 11.0, []],
	["vn_pm_rise2", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 11.6, []],
	["vn_pm_rise3", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 11.85, []],
	["vn_pm_late0", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 43.4, []],
	["vn_pm_late1", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 43.6, []],
	["vn_pm_late2", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 43.75, []],
	["vn_pm_late3", 17, Vector3(0.0, 12.0, 14.5), Vector3(0.0, 0.0, -1.0), 43.9, []],
	# the logo poster (level index 16, row 2: the open one at x 1.25, z -44): torn at 0, the scrap hangs and swings until 1.4 s, rolls up into the top edge 1.4 to 1.7, a new poster rolls down out of it 1.7 to 2.2
	# ("after" frames + 4 = frames of the look after the tear: 60 frames = 1 s)
	["vn_poster_hang", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 56}],
	["vn_poster_up1", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 86}],
	["vn_poster_up2", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 92}],
	["vn_poster_up3", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 98}],
	["vn_poster_down1", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 104}],
	["vn_poster_down2", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 114}],
	["vn_poster_down3", 16, Vector3(3.8, 1.9, -38.0), Vector3(1.25, 1.7, -44.0), 5.0, [Vector3(1.25, 0.0, -44.15)], {"burst": [[Vector3(1.25, 0.0, -43.6), Vector3(1.25, 0.0, -44.15)]], "after": 124}],
	# LAST TILE STANDING (level index 14): the first floor's tiles within 6 m of the middle stepped at clock 4: the rivals go at 4.25, the plain ones at 4.75; a tile tumbles under the arena and rests 49 m down (it falls through the floors below)
	["vn_tile_a", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 4.35, [], {"clear": [[0.0, 6.0, 4.0]]}],
	["vn_tile_b", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 4.5, [], {"clear": [[0.0, 6.0, 4.0]]}],
	["vn_tile_c", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 4.85, [], {"clear": [[0.0, 6.0, 4.0]]}],
	["vn_tile_d", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 5.3, [], {"clear": [[0.0, 6.0, 4.0]]}],
	["vn_tile_e", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 6.0, [], {"clear": [[0.0, 6.0, 4.0]]}],
	["vn_tile_f", 14, Vector3(0.0, 10.0, 16.0), Vector3(0.0, -2.0, 0.0), 8.0, [], {"clear": [[0.0, 6.0, 4.0]]}],
]

## Puts the step tiles of a shot in place (see SHOTS): everything stands unless the shot says otherwise.
func tiles_for(level: int, spec: Dictionary) -> void:
	var count: int = world.tile_count(level)
	var steps: PackedByteArray = world.tile_start(level, int(spec.fit)) if spec.has("fit") else PackedByteArray()
	if steps.is_empty(): steps.resize(count)
	world.set_tile_steps(level, PackedByteArray(), true)
	var origin: Vector3 = world.level_origin(level)
	var data: Dictionary = world._levels[level].data.tiles
	var tiles = world._levels[level].tiles # levels/step_tiles.gd
	var unit: float = 0.25
	for entry: Array in spec.get("clear", []):
		for index in count:
			var p: Vector3 = data.tiles[index].p
			if absf(p.y - float(entry[0])) < 0.01 and Vector2(p.x, p.z).length() <= float(entry[1]) + 0.01 and steps[index] != 255: steps[index] = roundi(float(entry[2]) / unit)
	for arc: Array in spec.get("arcs", []): # [floor y, radius, start degrees, sweep degrees, step clock at the start, m/s]
		var length := float(arc[1]) * deg_to_rad(absf(float(arc[3])))
		var at := 0.0
		while at <= length:
			var angle := deg_to_rad(float(arc[2]) + float(arc[3]) * at / maxf(length, 0.01))
			var feet := Vector3(cos(angle) * float(arc[1]), float(arc[0]), sin(angle) * float(arc[1]))
			var stamp := roundi((float(arc[4]) + at / float(arc[5])) / unit)
			for index: int in tiles.tiles_at(feet, 0.0):
				if steps[index] == 0: steps[index] = stamp
			at += 0.25
	for run_spec: Array in spec.get("trail", []):
		var from: Vector3 = run_spec[0]
		var to: Vector3 = run_spec[1]
		var length := from.distance_to(to)
		var at := 0.0
		while at <= length:
			var feet: Vector3 = from.lerp(to, at / maxf(length, 0.01))
			var stamp := roundi((float(run_spec[2]) + at / float(run_spec[3])) / unit)
			for index: int in tiles.tiles_at(feet, 0.0): # the hexagon(s) under the runner's feet
				if steps[index] == 0: steps[index] = stamp
			at += 0.25
	world.set_tile_steps(level, steps, true)

## What WalkInMarkers.build asks the game for: the floor under a point (the yard is flat).
class FloorAt extends RefCounted:
	func floor_at(point: Vector3) -> Vector3: return point

var shots := ""
var prefix := ""
var only: PackedStringArray = []
var custom: Array = [] ## --shot=<name>:<level 0-based>:<eye x,y,z>:<look x,y,z>:<clock>[:<courier x,y,z>;...] (level-local metres), any number
var tour := 0 ## --tour=<n>: the show's shoulder camera (the real FollowCamera) with a player at n spots along the route of every show level (`--tourlevel=<file number>` for one), shot names tp<level>_<i>
var tour_level := 0
var tour_at: Array = [] ## --tp=<name>:<level 0-based>:<feet x,y,z>:<yaw degrees, 0 = towards -Z>[:<clock>] (level-local), any number: one spot of the shoulder camera
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--shot="): custom.append(_custom_shot(argument.trim_prefix("--shot=")))
		if argument.begins_with("--tour="): tour = int(argument.trim_prefix("--tour="))
		if argument.begins_with("--tourlevel="): tour_level = int(argument.trim_prefix("--tourlevel="))
		if argument.begins_with("--tp="):
			var parts := argument.trim_prefix("--tp=").split(":")
			tour_at.append([parts[0], int(parts[1]), _vector(parts[2]), float(parts[3]), float(parts[4]) if parts.size() > 4 else 5.0])
	create_timer(100.0).timeout.connect(func() -> void:
		print("SHOW_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

static func _vector(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2])) if parts.size() == 3 else Vector3.ZERO

static func _custom_shot(text: String) -> Array:
	var parts := text.split(":")
	var spots: Array = []
	if parts.size() > 5 and parts[5] != "":
		for spot in parts[5].split(";"): spots.append(_vector(spot))
	return [parts[0], int(parts[1]), _vector(parts[2]), _vector(parts[3]), float(parts[4]), spots]

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func run() -> void:
	if shots == "":
		print("SHOW_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 4000.0 # as the game camera
	holder.add_child(camera)
	camera.current = true
	var done := 0
	var active := -1
	var tour_only := (tour > 0 or not tour_at.is_empty()) and only.is_empty() ## a tour alone: no other shots
	if tour_only: pass
	elif only.is_empty() or "lobby" in only or "lobby_circle" in only or "shirt" in only or only.has("lobby_wall_n") or only.has("lobby_wall_w") or only.has("lobby_wall_e"): done += await lobby_shots()
	for shot: Array in SHOTS + custom:
		if tour_only or (not only.is_empty() and not str(shot[0]) in only): continue
		var level: int = shot[1]
		if level != active:
			active = level
			world.set_active_level(level)
		world.set_clock(float(shot[4]))
		world.reset_effects() # the poster doors whole again, whatever the shot before did to them
		var origin: Vector3 = world.level_origin(level)
		if world.tile_count(level) > 0: tiles_for(level, shot[6] if shot.size() > 6 else {})
		var pegs: Array = []
		var seat := 0
		var air: Array = (shot[6] as Dictionary).get("air", []) if shot.size() > 6 else []
		for spot: Vector3 in shot[5]:
			var rig: Node3D = CharRig.new() # the character the game plays with (animal and bean heads, never a human courier)
			holder.add_child(rig)
			rig.setup(seat, {})
			rig.global_position = origin + spot
			var motion := {"velocity": Vector3(0.0, -9.0, 0.0) if air.has(seat) else Vector3.ZERO, "grounded": not air.has(seat), "yaw": 0.0, "carrying": false}
			rig.snap(motion)
			for i in 3: rig.update(1.0 / 60.0, motion)
			pegs.append(rig)
			seat += 1
		camera.global_position = origin + (shot[2] as Vector3)
		camera.look_at(origin + (shot[3] as Vector3), Vector3.UP)
		var doors: Dictionary = shot[6] if shot.size() > 6 and shot[6] is Dictionary else {}
		var who := 20
		for kind: String in ["burst", "bump"]:
			for pair: Array in doors.get(kind, []):
				world.observe_doors(level, who, origin + (pair[0] as Vector3)) # the first sample only remembers where the courier was
				world.observe_doors(level, who, origin + (pair[1] as Vector3))
				who += 1
		await frames(maxi(1, 4 + int(doors.get("after", 0))))
		RenderingServer.force_draw(false)
		var file := "%s/%s%s.png" % [shots, prefix, shot[0]]
		print("SHOW_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK)
		for rig: Node in pegs: rig.queue_free()
		done += 1
	done += await tour_shots()
	print("SHOW_FRAMES ok=", done > 0)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)

## The show's shoulder view (game/follow_camera.gd, as the game plays it) with the player's character at spots of the levels: the route (--tour) and --tp spots.
func tour_shots() -> int:
	var spots: Array = tour_at.duplicate()
	if tour > 0:
		for k in world.level_count():
			if not ("show" in world.modes(k)) or (tour_level > 0 and k + 1 != tour_level): continue
			var route: PackedVector3Array = world.route(k)
			var origin: Vector3 = world.level_origin(k)
			var total: float = world.route_length(k)
			for i in tour:
				var along := total * (float(i) + 0.5) / float(tour)
				var walked := 0.0
				for j in route.size() - 1:
					var leg := route[j].distance_to(route[j + 1])
					if walked + leg >= along or j == route.size() - 2:
						var direction := (route[j + 1] - route[j]).normalized()
						var feet := route[j] + direction * clampf(along - walked, 0.0, leg) - origin
						spots.append(["tp%d_%d" % [k + 1, i + 1], k, feet, rad_to_deg(atan2(-direction.x, -direction.z)), 5.0])
						break
					walked += leg
	var made := 0
	var follow := FollowCamera.new()
	follow.configure(camera)
	follow.set_first_person(false)
	follow.set_shoulder_view(true)
	var active := -1
	for spot: Array in spots:
		if not only.is_empty() and not str(spot[0]) in only: continue
		var level: int = spot[1]
		if level != active:
			active = level
			world.set_active_level(level)
		world.set_clock(float(spot[4]))
		if world.tile_count(level) > 0: tiles_for(level, {})
		var origin: Vector3 = world.level_origin(level)
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(0, {})
		rig.global_position = origin + (spot[2] as Vector3)
		var yaw := deg_to_rad(float(spot[3]))
		var motion := {"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false}
		rig.snap(motion)
		for i in 3: rig.update(1.0 / 60.0, motion)
		follow.reset_lag()
		follow.own_body(rig, 0)
		for i in 30:
			follow.update(1.0 / 60.0, rig.global_position + Vector3(0.0, 1.0, 0.0), yaw, follow.default_pitch())
			await physics_frame
		world.ghost_tiles(level, camera.global_position.y, rig.global_position.y) # as game_run.gd _ghost_tiles does each frame: the floors over the camera are not drawn
		await frames(2)
		RenderingServer.force_draw(false)
		var file := "%s/%s%s.png" % [shots, prefix, spot[0]]
		print("SHOW_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK, " camera ", (camera.global_position - origin).snapped(Vector3.ONE * 0.1), " ghosted floors ", (world._levels[level].tiles.ghosted if world.tile_count(level) > 0 else PackedInt32Array()))
		rig.queue_free()
		follow.clear_bodies()
		made += 1
	return made

## [eye, look-at] of the shoulder camera (game/follow_camera.gd: arm 5.4 m, pitch -13 degrees, the view centre 1.35 m over the focus) behind a player standing at `feet`.
func shoulder_view(feet: Vector3) -> Array:
	var eye := feet + Vector3(0.0, 3.4, 5.3)
	return [eye, eye + Vector3(0.0, -sin(deg_to_rad(13.0)), -cos(deg_to_rad(13.0))) * 8.0]

## The lobby yard: the whole yard from above the entrance, and the circle THE SHOW with two couriers on it.
func lobby_shots() -> int:
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	LobbySpace.ensure(holder, "local")
	world.set_active_level(-1)
	LobbySpace.sync(holder, "local", true)
	var course := WalkInLobby.shown_course()
	var centre := WalkInLobby.center(course)
	var markers := WalkInMarkers.new() # the circle and its signboard, as the game draws them
	holder.add_child(markers)
	markers.build(FloorAt.new())
	markers.set_shown(true)
	var round_pads: Array = []
	for entry: Dictionary in WalkInLobby.shown_pads(): # THE SHOW and a circle per round (the round circles' occupant: a courier on KEEP THE LOGO's)
		var stood := [{"seat": 0, "color": TeamCast.player_color(0)}, {"seat": 1, "color": TeamCast.player_color(1)}] if str(entry.course) == course else []
		round_pads.append({"course": entry.course, "counting": false, "occupants": stood})
	markers.present({"pads": round_pads, "lamps": [{"seat": 0}, {"seat": 1}]}, centre)
	var logo_at := WalkInLobby.center("r29") - centre
	var room := WalkInLobby.interior_rect()
	var views := [
		["lobby_circle", centre + Vector3(0.0, 2.3, 4.6), centre + Vector3(0.0, 1.5, -2.0), [Vector3(-0.8, 0.0, 0.0), Vector3(0.8, 0.0, 0.2)]],
		["lobby_yard", WalkInLobby.ORIGIN + Vector3(0.0, 15.0, 12.5), WalkInLobby.ORIGIN + Vector3(0.0, 0.0, -4.0), []],
		# the round circles: from where the players come in (the yard's middle) and from the front row's side; a courier on KEEP THE LOGO's circle
		["lobby_rounds", WalkInLobby.ORIGIN + Vector3(0.0, 3.2, 8.0), WalkInLobby.ORIGIN + Vector3(0.0, 0.9, -4.6), [Vector3(-0.8, 0.0, 0.0), Vector3(0.8, 0.0, 0.2)]],
		["lobby_rounds_low", WalkInLobby.ORIGIN + Vector3(0.0, 1.9, 3.2), WalkInLobby.ORIGIN + Vector3(0.0, 1.5, -5.0), [Vector3(-0.8, 0.0, 0.0), logo_at + Vector3(0.5, 0.0, 0.8)]],
		["lobby_pick", WalkInLobby.center("r29") + Vector3(0.0, 2.1, 4.2), WalkInLobby.center("r29") + Vector3(0.0, 1.3, -1.5), [logo_at + Vector3(-0.5, 0.0, 0.0), logo_at + Vector3(0.6, 0.0, 0.2)]],
		# the lobby as the shoulder camera sees it (about 5.3 m behind the player and 3.5 m up, pitched down 13 degrees): from a spawn seat, standing on THE SHOW's circle
		# and on a rear circle (a courier at the player's spot and one beside it)
		["lobby_cam_spawn"] + shoulder_view(WalkInLobby.spawn(0)) + [[WalkInLobby.spawn(0) - centre, WalkInLobby.spawn(1) - centre]],
		["lobby_cam_show"] + shoulder_view(centre) + [[Vector3.ZERO, Vector3(1.4, 0.0, 0.9)]],
		["lobby_cam_rear"] + shoulder_view(WalkInLobby.center("r27")) + [[WalkInLobby.center("r27") - centre, WalkInLobby.center("r28") - centre]],
		# the four stage rounds' circles (A left of THE SHOW, B right of it) and the outermost circles of both rows, as the shoulder camera sees them
		["lobby_cam_stage_a"] + shoulder_view(WalkInLobby.center("r25")) + [[WalkInLobby.center("r25") - centre, WalkInLobby.center("r26") - centre]],
		["lobby_cam_stage_b"] + shoulder_view(WalkInLobby.center("r28")) + [[WalkInLobby.center("r28") - centre, WalkInLobby.center("r27") - centre]],
		["lobby_cam_front_west"] + shoulder_view(WalkInLobby.center("r29")) + [[WalkInLobby.center("r29") - centre, WalkInLobby.center("r30") - centre]],
		["lobby_cam_front_east"] + shoulder_view(WalkInLobby.center("r32")) + [[WalkInLobby.center("r32") - centre, WalkInLobby.center("r31") - centre]],
		# the two newest races (ROOFTOP RUN and FERRY CROSSING, side by side in the middle of the front row)
		["lobby_cam_race_new"] + shoulder_view(WalkInLobby.center("r30")) + [[WalkInLobby.center("r30") - centre, WalkInLobby.center("r29") - centre]],
		# the walls with the cast's pictures (eye and look-at are yard-local), the shirt print from the front (the courier turned round)
		["lobby_wall_n", WalkInLobby.ORIGIN + Vector3(0.0, 1.7, room.position.y + 5.4), WalkInLobby.ORIGIN + Vector3(0.0, 2.0, room.position.y + 0.15), []],
		["lobby_wall_w", WalkInLobby.ORIGIN + Vector3(room.position.x + 2.6, 1.7, -5.0), WalkInLobby.ORIGIN + Vector3(room.position.x + 0.15, 1.9, -5.0), []],
		["lobby_wall_e", WalkInLobby.ORIGIN + Vector3(room.end.x - 3.1, 1.7, -1.5), WalkInLobby.ORIGIN + Vector3(room.end.x - 0.15, 1.9, -1.5), []],
		["shirt", centre + Vector3(0.0, 1.2, 1.3), centre + Vector3(0.0, 1.2, 0.0), [Vector3(0.0, 0.0, 0.0)], PI, true],
	]
	var made := 0
	for view: Array in views:
		if not only.is_empty() and not str(view[0]) in only and not "lobby" in only: continue
		var pegs: Array = []
		var seat := 0
		for spot: Vector3 in view[3]:
			var rig: Node3D = CharRig.new() # the player character (the one the game plays with: an animal or bean head, never a person)
			holder.add_child(rig)
			rig.setup(seat, {})
			rig.global_position = centre + spot
			var stand := {"velocity": Vector3.ZERO, "grounded": true, "yaw": float(view[4]) if view.size() > 4 else 0.0, "carrying": false}
			rig.snap(stand)
			for i in 3: rig.update(1.0 / 60.0, stand)
			pegs.append(rig)
			seat += 1
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP)
		await frames(4)
		RenderingServer.force_draw(false)
		var file := "%s/%s%s.png" % [shots, prefix, view[0]]
		print("SHOW_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK)
		for rig: Node in pegs: rig.queue_free()
		made += 1
	markers.queue_free()
	LobbySpace.sync(holder, "local", false)
	return made
