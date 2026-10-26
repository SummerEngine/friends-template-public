# Multiplayer in this template

The game is online multiplayer out of the box (2 to 10 players, hosted by Summer Games) and you can change almost anything and keep
it that way. This page is only the high-level map of this project. How to build things with Summer multiplayer is in the docs and
the `multiplayer` skill (links at the end): start there for the how-to.

## How this game is wired

It follows the standard Summer multiplayer model (the `multiplayer` skill, "The picture" and "How data moves"):

| Summer concept | In this project |
|---|---|
| The **authority** runs the rules, one per match | `demo/authority/`, `demo/network/match_controller.gd`, each mode's `demo/modes/<id>/rules.gd` |
| **Owner-written State**: each player moves their own character, the authority checks each pose | `demo/courier/courier_motion.gd`, `demo/network/owner_pose_wire.gd` |
| **Authority-written State**: what everyone sees (players, the painting, the balloon, props, a mode's score and round) | the snapshot in `demo/network/game.gd`, a mode's `state()` |
| **Commands**: a player asks (use an item, an action) and the authority decides | the input wire, `demo/network/input_wire.gd` |
| The **Composition**: every stream both sides load | `demo/network/game.gd` |
| World, queue, player counts | `demo/world.json`, `demo/summer.build.json` |

One script runs every role (`demo/game/game_run.gd`: one keyboard, the authority and each online player), and moving hazards follow
the shared level clock, so they need no messages.

## How much work a change is

**Works online with nothing extra:** the cast (names, colours, pictures, words, music, which game), the whole look (characters, world,
menus, HUD, effects, sound), levels and hazards, and a mode's rules in `rules.gd`.

**A small extra step:**
- a new minigame or show round: copy a mode folder; its `state()` reaches every player automatically (`docs/modes.md`);
- a new button or action: add it to the input and let the authority accept it (the show's items do this: `docs/items.md`);
- faster or bigger movement: it runs on the player's machine, so it stays snappy; raise the authority's pose limits in `game_run.gd` if moves get much longer;
- more or fewer players: the queue in `demo/summer.build.json` and the mode's `min`/`max` in `demo/modes/modes.json`.

**Bigger, very doable:** new shared physics objects that everyone sees in the same place (the balloon and the lobby props are worked
examples to copy), or a different network model.

**Testing:** one keyboard for quick tries, then several players on one computer with Summer's Local Play (`multiplayer-testing`).

## Docs and skills

- [docs.summerengine.com](https://docs.summerengine.com), especially [Make a multiplayer game](https://docs.summerengine.com/build/multiplayer)
- The `multiplayer` skill (start here), then `multiplayer-state`, `multiplayer-movement`, `multiplayer-testing`, `multiplayer-publish`,
  and services such as `summer-parties` and `summer-matchmaking`: loaded by your agent through the Summer MCP, also readable at
  [github.com/SummerEngine/summer](https://github.com/SummerEngine/summer/tree/main/library/skills)
- This project's internals, when you need them: `docs/core-shell.md` (roles and wires), `docs/modes.md`, `docs/items.md`
