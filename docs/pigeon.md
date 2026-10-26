# GHOST PIGEON (experiment)

A player who is out of a tile round (levels 25-28: the courier lands on the ground floor) or who has finished a race (levels 29-32: it crossed the goal) is not parked in the spectator camera: it becomes a **pigeon**, a small
low-poly bird that flies over the arena and annoys the players still running. It is a switch, `demo/modes/show/shared/pigeon/pigeon.json`.

| | |
|---|---|
| **Fly** | WASD / left stick: the horizontal direction on screen (the shoulder camera follows the bird); **Space** / A: up; **Shift**, **C**, **Ctrl** / B or RB: down. A ceiling and bounds keep it in the arena (a race: the route's box +16 m and 22 m up; a tile round: the stage's ground rectangle, up to 12 m over the top floor). Speed 8 m/s, climb 5 m/s. |
| **COO** | **F** (the grab key; X on a pad). A loud synthesized coo for everybody (3D, from the bird), a bubble and a ring on every screen, and a small **screen shake** on the screen of every *living* player within 5 m. Cooldown 3 s. |
| **DROP** | **E** (the item key; LB on a pad). A white drop falls from the bird. On a living player (a hit test around its head) it **splats**: a white blob with drips over that player's own screen for 1.5 s (it covers part of the view, the middle stays readable), a white blob on its head for the others; on the floor it leaves a decal. Cooldown 6 s. One splat on a player at a time, and none for 2 s after the last ended (`victim_rest`). Since Show 10 a DROP also needs the show's event gate (`modes/show/shared/event_gate.gd`: one interrupting event at a time, 15 s apart, shared with the manager, the eggplant and the clock's boost/soar): while another event runs, or within 15 s of the last one, nothing is let go and the DROP pill's bar shows the wait. The COO is not gated. |
| **Fairness** | A pigeon never pushes, kills, freezes or slows anybody; the shake and the splat are screen effects only. Nothing the pigeon does counts in a round's result. |
| **Phone** | While a bird, the buttons read UP / DOWN / COO, and the round DROP button replaces ITEM (`client/touch_controls.gd set_pigeon`). |
| **Bots, AFK** | A bird nobody flies for `wander_after` 5 s **wanders on its own** and coos now and then (any input takes the controls back). This is what an eliminated scripted bot or a player who put the phone down does. |
| **Alone** | The solo player becomes a bird too, 1.2 s after it finishes or falls, and flies through the end of the round (the done phase), so it can be seen. |

## Rules (authority, `demo/modes/show/shared/pigeon/pigeon_rules.gd`)

* One `PigeonRules` per `ShowRules` (`rules.pigeons`). `rules.gd` calls: `begin_round(kind, level, watchers)` after the round's freeze (birds are cleared; players already out of the show, `watchers`, start the round as birds at the centre of the
  box), `spawn(slot, courier_position)` from `_retire`, `tick(dt, armed)` at the end of `tick()` (armed in `play` and `done`), `drop()` on a round's drop, `clear()` at the podium and `state()` merged into the show's state.
* **A race finisher is retired** `FALL_SHOW` 1.2 s after it crossed the goal when the experiment is on (`_cross`, `_retire_pending`); `across` is counted with the active field, so the round's end is unchanged (a race still
  ends when everybody has crossed, or 30 s after the first in a points show). A racer who falls into a kill volume goes back to its checkpoint and is NOT a bird.
* **Birds are the authority's.** It integrates every bird with `pigeon_sim.gd step` from the owner's input (the `move` world direction and `height`, which the owner's machine fills from JUMP / DASH held when `pigeon_focus` is set,
  `game_run.gd collect_owner_input`). COO is the existing `grab_seq` counter, DROP the existing `item_seq` counter: no new network protocol, no new input key.
* The owner's client **predicts** its own bird with the same step (snap at 4 m, ease while idle, ignore up to 3 m of drift while steering); the solo/local role uses the authoritative bird. Everybody else interpolates `vel`.
* **Show state** `pigeon` (only while the experiment is on, a few hundred bytes): `b` birds `[slot, x, y, z, yaw, vx, vy, vz, coo_n, drop_n, coo_cd, drop_cd, auto, hits]` (`hits` is a bitmask of the living slots the last
  coo reached; `coo_n` and `drop_n` count, clients play the sound when they change), `d` falling drops `[x, y, z]`, `s` the splats `[victim, left, from]`, `l` the last landings `[seq, x, y, z, victim]` (victim -1: the floor).

## Switch, texts, tuning

* `pigeon.json`: `"on": true` is the switch; `rounds` `{race, survival, final}` turn it off per round kind (`final` is the kind of the show's last round). A cast turns it off with `show.pigeon.off: true`.
* **Texts** (`texts` in pigeon.json, the template's neutral ones): banner `YOU ARE A PIGEON`, coo `COO!`, splat `SPLAT!`, `line` `{user} IS A PIGEON NOW`, `drop_line` `{user} DROPPED ONE ON {victim}`. The Summer cast
  (`summer-show-cast` `show.pigeon`) says `REASSIGNED TO PIGEON OPS`, `COO.EXE`, `MERGE CONFLICT!`, `{user} JOINED PIGEON OPS`, `{user} PUSHED TO PROD ON {victim}`. Limits: banner 30, coo 16, splat 16, lines 48 characters
  (`style/team_cast.gd show_pigeon`, `tools/cast_check.py` `pigeon()`).
* **Tuning** (`tuning` in pigeon.json with min / max / default; a cast's `show.pigeon.tuning` overrides within the range): `speed` 8, `climb` 5, `coo_cooldown` 3, `coo_range` 5, `drop_cooldown` 6, `splat_time` 1.5, `victim_rest` 2, `wander_after` 5.

## Looks (all ours, from code)

`pigeon_mesh.gd`: grey-blue body with a pale belly and a white rump, round head, orange eye, beak, flapping wings, banded tail, a **collar in the player's colour** (who it is) and a small gold halo; 1.4 times a real pigeon so
the shoulder camera can see it. `pigeon_view.gd` draws the birds, the coo bubble and ring, the drops, the floor decals, the head blob, the shake (`camera.h_offset / v_offset`) and the own camera (`GameRun.pigeon_focus`,
`_place_camera`); `splat_overlay.gd` the splat; `pigeon_hud.gd` the COO / DROP pills; `pigeon_audio.gd` the synthesized coo and splat. Own small materials; nothing of the show's look, sky or lighting is touched.

## Checks

* `tools/modes/items_harness.gd --scenario=pigeon --show-level=31 --show-level=25` (`tools/modes/items/pigeon_scenario.gd`): authority + two replicas, the race and then a tile round: the finisher becomes a bird, flies on its
  input inside the bounds, the coo reaches the near player (shake) and not the far one, cooldowns, a drop splats the player under it, a second bird cannot stack a splat, nobody is pushed or hurt, an unflown bird wanders and coos,
  the fall on the tile round, the bird over the arena, its drop on a player on the tiles.
* `tools/modes/show_bot_check.gd --solo` plays a whole solo show with the experiment on (bots, the solo bird).
* `python3 tools/cast_check.py` checks `show.pigeon`; the usual `show_check`, `clean_scan`.
