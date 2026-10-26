# SHOVE-OFF (`shove_off`)

Shove each other off a shrinking floor; the last one standing wins. 2-10 players (on one machine: the two local players). Pick it when
the group likes rough play.

Files: `demo/modes/shove_off/rules.gd` (shared: the authority and the local game), `demo/modes/shove_off/view.gd` (client),
check `tools/modes/shove_off_check.gd`.

## What it is

A raised floor of 6 x 6 square tiles (1.25 m each, 7.5 m across) stands in the open middle of the yard, between two strands of
lights and clear of the playground, its top 1.5 m over the yard floor. The view builds it on every client as real collision on the
yard's floor layer: everybody's own courier stands on it, walks off its edges and falls through the tiles that drop. 1.5 m is out of
reach from below: a courier jumps 1.44 m and the game's contact reaches 1.45 m up, so a player on the yard floor can neither climb
back on nor shove the ones still up there.

Players shove with the game's own contact: walking into someone pushes them, GRAB lifts a player and GRAB again throws them. The
rules never use the floor's geometry. They decide from `host.position` alone: a player whose feet are more than 0.8 m below the top is
off, and so is one who hangs over no standing tile for 1.5 s without falling (a courier that stopped moving; a tile carries a player
0.35 m past its edge, as far as a courier can stand).

## Round flow

| Phase | How long | What happens |
|---|---|---|
| count | 3 s | everybody still in the game is sent onto a ring 2 m around the floor's centre, facing in (`host.send_to`; the ring turns by `host.rng` every round). "3, 2, 1". Somebody shoved off now goes back to their spot |
| play | until one is left | SHOVE! for the first second. 2 s later the tiles start to fall: each shakes 1 s (red, with the crack of the levels' vanishing blocks), then drops to the yard floor and is gone. The outer ring goes first, then the next ring, then the middle four, each ring in a random order (`host.rng`). The gap between two tiles starts at 1.4 s and shrinks by 7 % per tile down to 0.35 s: the whole floor is gone 23.6 s after SHOVE! |
| card | 3.5 s | "<NAME> WINS THE ROUND", or "NOBODY WINS THE ROUND" when the last ones fell in the same tick. The floor stops falling; then the tiles come back and the next round counts in |
| over | | after the card of the deciding round: the results page |

A player who is off is out for the round: the cast's fall word pops over them, and 1 s later (the fall shows) they are sent to the
watch row on the yard floor 3 m north of the tiles, facing them. An out player who comes within 0.6 m of the floor again (the
trampoline is close) is sent back to the row. A player who leaves online (`drop`) is out for the rest of the game; the round plays on
while two or more are left in it.

## Scoring and results

One round win for the last one standing. The first to 2 round wins wins the game; after 5 rounds at the most, the most round wins wins.
The scores are the round wins (the HUD board shows them; players out this round, and players who left, are greyed). Results: headline
`<WINNER> WINS`, sub line the round wins (`MAYA 2  ·  IDA 1  ·  THEO 0`). Two or more level after five rounds: `IT'S A TIE`; nobody won a
round: `NOBODY WINS`. A game that ends early (a player left) goes by the round wins so far; the only one left in the game wins.

## Cast slots it reads

| Slot | Field | How |
|---|---|---|
| Players | `players[].name`, `.color`, `.look` | the characters, the HUD names ("MAYA WINS THE ROUND"), the round wins board |
| Player emote | `players[].emote` | the round's winner plays it during the card (else `dance`) |
| Obstacle signs | `obstacles[i].label`, `.color` | the labels lie on the first tiles to fall, in order (up to five), in Archivo lettering like the level signs. The tile is sign yellow, or the obstacle's colour when it has one; the lettering is ink, or white on a dark colour. The picture is not used |
| Brand colours | `brand.colors` | the tiles are a checker of white and the team's wall colour (`TeamCast.wall_hue()`, a brand colour clear of red, orange and yellow), else teal; red stays the warning of a tile about to drop |
| Words | `words.fall` | the word over a player who falls off |

## Controls

Move and jump as usual. Walk into a player to shove them. GRAB (F; the second keyboard player N; pad X) lifts a player in front,
GRAB again throws them; jump presses wriggle free. The mode's action button (Z / X) does nothing here. The HUD note says: "Walk into
players to shove them. F grabs and throws  ·  WASD move · Space jumps".

## HUD

Title `SHOVE-OFF  ·  ROUND n`. Big word: 3, 2, 1, then SHOVE!, then who won the round. Line: the goal during the count, the time to
the next round on the card, "You fell. Watch the rest of the round" for an online player who is out. No timer.

## State (`match.minigame`)

`phase` (`count`, `play`, `card`, `over`), `round`, `t` (s into the phase), `tiles` (per tile, row by row: 0 up, 1 shaking, 2 gone),
`marked` (the five tiles that fall first, in order: the labelled ones), `wins`, `out` (this round, in the order they fell), `gone`,
`winner` (the round's, -1 none), `champion` (-1 none). Under 1 KB with ten players. The floor's numbers (grid, tile, height, centre)
are constants of `rules.gd` that the view reads.

## Limits

- 2-10 players; with two it is one against one. A round takes 10-30 s with its count and card; a game of 2 to 5 rounds under three
  minutes.
- The floor covers part of the yard's spawn rows and three of its props; the props stay ordinary props (the out players can play with
  them).
- A courier that stops moving online (a dropped connection) goes out 1.5 s after its tile drops; a player on that same last tile who
  really falls is out after 0.3 s and loses that round to it.
