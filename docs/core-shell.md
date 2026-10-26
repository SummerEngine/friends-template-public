# Core shell

The simulation shell `demo/game/game_run.gd` (roles local / authority / replica), the owner/remote adapters
and the snapshot wire (v12). For the big picture first: `docs/multiplayer.md`.

## Module map

| File | Role |
|---|---|
| `game/game_run.gd` | The shell. One `network_role` switch: `local`, `authority`, `replica`. Builds `world`, the level world, couriers, painting; steps a tick; level/phase logic; snapshot capture/apply. |
| `game/visual_track.gd` | Where a courier is DRAWN between two 60 Hz ticks: the last two tick positions and the physics interpolation fraction (`GameRun.visual_position(slot)`); the rigs and every follow camera use it, so the courier does not step ahead of or behind the camera at 120 Hz. |
| `game/game_input.gd` | Device sampling for the local role (keyboard, 1-2 pads, one-keyboard test mode): move, look, jump edges, roll axis, height axis, options, restart. |
| `game/split_views.gd` | Two half-screen views of the one world (local role, two humans). |
| `network/owner_courier.gd` | Replica: the owner's own courier. Seeds from the authority baseline, steps `CourierMotion` at 60 Hz, captures the owner pose. Surface: (`configure/reset_from_authority/observe_shared/jump_edge/physics_step/teleport/capture_pose/dispose`). |
| `network/remote_courier.gd` | Replica: smooths the other player's relayed poses (arrival-clock mapping, short back time, bounded extrapolation). `reset(epoch)`, `receive(pose, arrival)`, `sample(now, current)`. |
| `network/owner_pose_wire.gd` | Owner pose wire (fixed 248 B, magic `GWPS`, version 2). |
| `network/input_wire.gd` | Input wire (magic `GWIN`, version 3). |
| `network/game.gd` | Stream ids `gw.*`, composition, `pack_snapshot/unpack_snapshot` (wire v12), input validation. |
| `network/snapshot_metadata_wire.gd` | Mask-coded shared root fields of the snapshot. |
| `network/match_controller.gd`, `authority/main.gd` | Match rules and SDK transport of the hosted authority. |
| `client/main.gd` (+ `local_level_flow.gd`, `presentation_entry.gd`, `local_presentation.gd`) | Online client and the local app. |

External modules the shell integrates: `courier/courier_motion.gd`, `courier/courier_rig.gd`, `courier/courier_anchor.gd` (CourierSmith),
`game/painting.gd`, `game/painting_shards.gd`, `game/follow_camera.gd`, `game/game_audio.gd` (PaintingCam), `levels/level_world.gd` (LevelRuntime).

## Roles

* **authority**: rigless. No courier rigs, no camera, no visuals, no CourierMotion. Each `actors[slot]` is a plain `CharacterBody3D`
  without shapes that only carries the last accepted owner pose. The painting is derived from the two accepted owner anchors
  (`painting.anchor_a/b`). Per tick: advance the hazard clock (`LevelWorld.advance`), apply the pending owner poses, sum the roll/height
  inputs, step the painting (break query), test kill / goal zones with `LevelWorld.zone_at` on the owner poses, run the break flow
  (1.5 s card, respawn after 6.5 s), the round clock.
* **replica** (online client): the owner runs its own courier (`OwnerCourier` around `CourierMotion`, stepped by `client/main.gd` before the
  shell's own tick); the other player is `RemoteCourier`-smoothed; both couriers are drawn with `CourierRig`; the painting is derived
  locally from the two rig anchors and corrected from the snapshot (roll/height lerp, hard snap when the error exceeds 1.5 m, snapshot
  transform while no anchor exists yet). Hazards run from their own clock slewed to `hazard_t`.
* **local**: everything on one machine: two courier bodies stepped by the shell from `GameInput`, painting, camera(s), level flow by
  `client/local_level_flow.gd`.

## Public surface (what other files may read; all roles unless stated)

`network_role`, `carrier_count` (the seats: 10 online, 2 local), `play_mode` (`carry` | `balloon`), `team` (game/team_play.gd), `world`, `level_world`, `actors[slot]` (CharacterBody3D), `rigs[slot]` (CourierRig, `null` on the authority),
`painting`, `shards`, `audio`, `camera` / `local_views` / `touch` (client roles), `local_presentation` (local), `round_mode` (`lobby` | `level`),
`course_plan` (`CourseSection.plan`), `playing`, `won`, `reset_count` (epoch), `frame`, `elapsed_seconds`, `breaks`, `breaks_by_slot`,
`failure_kind` (`""` | `break` | `death`), `death_ui_visible`, `break_elapsed`, `break_event`, `holding_states`, `height` (painting lift, m),
`slot_active`, `lobby_center`.

Methods: `configure_phase(mode, active)`, `set_course_plan(plan)`, `restart_delivery()`, `set_slot_active(slot, on)`, `is_slot_active(slot)`,
`partner_actor(slot)`, `lobby_spot(slot)`, `floor_at(pos)`, `set_local_seat(slot)`, `set_slot_tint(slot, palette_index)`,
`set_camera_input_enabled(on)`, `set_local_input_enabled(on)`, `configure_local_input_mode(mode)`, `configure_local_split_screen(on)`,
`apply_camera_settings(values)`, `collect_owner_input() -> Dictionary` (replica: the owner's input command), `owner_step(command, enabled, dt)`,
`capture_network_state() -> Dictionary`, `apply_network_state(state, dt)`, `queue_authority_owner_pose(slot, pose) -> bool`,
`freeze_authority_owner_pose(slot)`, `clear_authority_owner_pose(slot)`, `set_player_input(slot, command)`, `is_network_ready()`,
`finish_local_loading()`, signal `load_progress(fraction, label)`, `load_yield`, `load_background`, `load_slicer`.

## Owner pose wire (`network/owner_pose_wire.gd`, 248 bytes)

Keys: `version, seq, reset_epoch, local_tick, time, transform, velocity, grounded, floor_normal, yaw, acceleration, anchor, flop`.
`anchor` is the point the painting hangs from (`CourierRig.anchor()` of the owner's rig; the authority has no rig). Encoding:
doubles, canonical encoding checked on decode, magic `GWPS` and version 2. `flop` (int 0..255, byte 161) is the time left of the dash flop in 1/100 s (`CourierMotion.flop_left`; always 0 unless the mode has the `dash_flop` option, which the show does not):
the rig of every other player lies the courier down from it; decode rejects a non-canonical encoding (bytes 162..167 stay zero).

## Snapshot wire (`Game.pack_snapshot` / `unpack_snapshot`)

Transport: `var_to_bytes(dict).compress(DEFLATE)` in `{"b": bytes}`, <= 32768 B, `wire_version = 12` (`Game.WIRE_VERSION`). The balloon and contact fields are under "Balloon mode" below.

Per player (`players[slot]`, `0` for an empty slot): `[position: Vector3, flags: int, acceleration: Vector3]`, plus `yaw: float` as a fourth
element while `baseline` is true (burst after a reset epoch, join or resync). `flags`: bit0 = holding the painting. Unpacked to
`{position, velocity = ZERO, acceleration, holding, movement = {yaw}}` (`movement` only with a baseline).

Shared root fields (`snapshot_metadata_wire.gd`, mask coded): `tick, painting (Transform3D), roll, height, level, playing, broken, hit, won,
resets, failure_kind, death_ui_visible, break_elapsed, break_event, holding, elapsed_seconds, breaks, audio_events {death}, hazard_t,
players_joined, server_elapsed, input_sequences, waiting_for_partner, settlement_state`.

Outside the mask: `players`, `fragments` (PaintingCam's compact shard state: any Variant of ints/floats/PackedByteArray), `round_mode`, `course`,
`baseline`, `owner_grants`, `match`, match mode keys (`mode_version`, `match_queue`, `seat_count`), `wire_version`.

## Commands (`gw.command`)

`join`, `baseline_resync`, `choose`, `end_run`, `restart`, `leave`. Roll and height are input axes, not commands.

## Input wire (`gw.input`)

`move, seq, jump_seq, jump, restart, height, roll, facing` + optional extras (`menu`, `owner_pose`, `item_seq`: the ITEM press counter of the show's items, `docs/items.md`; `game.gd valid_input` checks it). `roll`/`height` are axes in [-1, 1];
the shell applies `ROLL_SPEED` (120 deg/s, limit 80 deg) and `HEIGHT_SPEED` (2.25 m/s, limit 0.5 m). Seat 1 mirrors the roll sign.

## Level flow in the shell

`set_course_plan(plan)` stores the plan (`plan.level` = level index, `-1` lobby); `configure_phase(mode, active)` is a new epoch:
`LevelWorld.set_active_level`, clock 0, couriers on `LevelWorld.start_pose(level)` (or the yard spots), painting reset, timers reset.
A broken painting or a kill zone respawns the same way (epoch + 1, the level clock restarts, the run clock keeps running).
Goal: either courier in `zone_at(level, pos) == "goal"` with the painting intact sets `won` (the match controller / local flow then starts
the next level). Kill: any courier in a `"kill"` zone breaks the painting (`failure_kind = "death"`).

## Details

* Round mode is `"lobby"` or `"level"`. `holding` is derived from flags. Players unpack to `{position, velocity = ZERO, acceleration, holding, movement = {yaw}}` (yaw only on baseline snapshots). `audio_events` carries `{death}` only.
* Clock: the level world is advanced by `advance(dt)` while playing (authority and local); the replica calls `correct_clock(hazard_t)` once per new snapshot tick and `set_clock` on a baseline epoch.
* `effects_at(k, who, feet)` returns `{v, override_xy, override_z, id}` or `{}`.
* Further files: `game/game_input.gd` (keyboard/pad sampling), `game/load_slicer.gd` (frame-sliced loading), `game/split_views.gd` (client-only split-screen viewports), `network/owner_courier.gd` and `network/remote_courier.gd` (replica owner stepping, remote pose interpolation), `network/resync_limit.gd`.
* Shell extras used by the client: `hud_state()`, `prime_local_input()`, `set_peer_hidden()`, `connected_pads()`, `started_moving`.
* Checks: `tools/core_shell_check.gd` (authority fixture + replica loopback), `tools/levels_flow_check.gd`, `tools/staged_load_check.gd`.

## Menus and settings (client)

* `client/menus.gd`: pause menu and Settings sheet (tabs Display, Gameplay, Audio; the controls are taught by the round's key hints in client/hud.gd, there is no controls page). Signals `back_to_main`, `restart_requested`, `end_run_requested`, `pause_changed(open)`, `setting_changed(key, value)`. `show_pause(in_game)`, `hide_pause()`, `probe()`.
* `client/settings.gd`: values, definitions (`DEFINITIONS`), apply and save to `user://settings.cfg` (section `values`, plain keys). Static `ensure_music_bus()`, `apply_saved_audio()`; music bus `GW_Music`.
* `client/main_menu.gd`: the title page over the comic skin; action keys `Play`, `Settings`, `Invite`, `Quit`; `action_button(key)`.
* `client/blur.gdshader`: soft blur behind the pause sheet. `tools/menu_shots_check.gd` takes frames of every page.

## Balloon mode and players touching players (`game/team_play.gd`)

* **Mode.** The match controller (and the local flow) pick the play mode when a round starts: `CourseSection.play_mode_for(players)`, 2 = `carry`,
  3 or more = `balloon`; the dev switch `--balloon` / `FRIENDS_BALLOON=1` forces balloon. It rides in the plan (`plan.play_mode`) and the
  snapshot (`play_mode`). The run draws from `CourseSection.pool_levels(play_mode)` (level `"modes"`). Online seats: one queue `lobby_10`
  (2 to 10 players, `Game.MAX_PLAYERS`); a balloon round goes on when a player leaves or disconnects while two remain.
* **Balloon** (authority, local): `BalloonSim` stepped after the couriers with their capsules; world mask 1 | 16. Pops: the sim's floor test, a
  "hit" block or hazard (layer 8) touching it, a kill volume or the void (`point_zone`). A pop: `failure_kind = "pop"`, `breaks` + 1 (the level's
  pops), the POP! card at once, a new epoch after `BalloonSim.RESPAWN_SECONDS`: the team on a ring around the last checkpoint passed
  (`LevelWorld.checkpoint_at`, `team_start`) or the start pad, the balloon hanging over it until somebody touches it (`hover`). The goal:
  the balloon inside the goal volume sets `won`. A courier in a kill volume respawns alone (the balloon flies on).
* **Replica:** draws the authority's balloon, moved on between snapshots by the same sim without players and without pops; the drawn copy
  (`team.view`) eases toward it. The camera keeps the balloon in view.
* **Contact:** shoves run on every owner for its own courier against the couriers it draws (local: all), grabs only on the authority, in the
  lobby yard and in balloon rounds (carriers hold the glass), from GRAB / JUMP press counters in the input (`grab_seq`, `jump_seq`). Held couriers ride `HOLD_HEIGHT` above their
  holder on every machine. Throws, drops and escapes reach the owner as a cumulative kick per slot; a personal respawn as a count and a point.
  In a tile stage round (`PlayerContact.stage`, set by `team_play.gd` from `run.stage_round()`) couriers are solid for each other on every machine (replica bodies get the courier layer,
  `game_run.gd` `_sync_courier_bodies`) and the shove is a symmetric two-way bump (`STAGE_BUMP`); no new messages: docs/party-show.md "The stage camera and feel".
* **Props:** loose props in the lobby yard (`lobby_space.gd` LOOSE_PROPS: boxes, balls, cones; `players/prop_sim.gd`), stepped by the
  authority (and the local game) after the contact. GRAB with nobody in reach picks up the nearest prop in front, it rides at the holder's
  chest, GRAB again throws it; a holder who is grabbed or hit by a flying prop drops it; walking into one on the floor kicks it along. Clients
  draw them (`players/prop_look.gd`), a carried one in its holder's hands as drawn. Lab first: `balloon/balloon_lab.tscn`, `tools/contact_check.gd`.
* **Slap:** in balloon rounds a GRAB press is a slap when the balloon is within `BalloonSim.SLAP_REACH` and no free player stands in front
  (`team.split_grabs`, on the owner: it swings its arm at once and sends `slap_seq`). The authority keeps a 0.6 s cooldown per player and, `SLAP_HIT_TIME`
  (0.1 s, the rig's) after the press, lifts the balloon (`BalloonSim.slap`: up to 6 m/s, 3.5 m/s along the facing) when it is still in reach (plus
  0.75 m of slack). Every other client swings the slapper's arm from the `slaps` counter (`rig.slap(side)`, guarded by `has_method`).
* **Wires.** The snapshot also carries `play_mode`, `scorch` (per slot: zaps and burns so far, kind of the last; game/team_play.gd), and in balloon rounds `balloon` (PackedFloat32Array: `BalloonSim.snapshot()` + hover, checkpoint,
  bumps), `contact` (per slot: held_by, kick xyz, respawns, respawn point xyz; also in the lobby) and `slaps` (per slot: slaps so far, hand); in the lobby
  `props` (per prop: position, velocity, held_by). Input wire `GWIN` version 3 has
  `grab_seq` and `slap_seq`. Match mode
  version 4. The relay of owner poses thins with the players in the World (`Game.relay_every`: 60/30/20 Hz); observers widen their back time.
* **Checks:** `tools/balloon_round_check.gd` (authority, four scripted players, and a replica), `tools/balloon_check.gd`, `tools/contact_check.gd`,
  `tools/levels_flow_check.gd -- --balloon` (local role).
