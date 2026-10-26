# HOT POTATO (`hot_potato`)

Pass the team's thing on before it pops. 2-10 players (on one machine: the two local players). Pick it when the group likes it
loud and silly.

Files: `demo/modes/hot_potato/rules.gd` (shared: the authority and the local game), `demo/modes/hot_potato/view.gd` (client),
check `tools/modes/hot_potato_check.gd`.

## What it is

One of the yard's loose props (`players/prop_sim.gd`, `lobby_space.gd` LOOSE_PROPS) becomes the potato. Players pick it up and throw
it with the game's own GRAB, like any prop: GRAB with empty hands picks up the nearest prop in front, GRAB again throws it. A hidden
fuse runs. When it pops, whoever holds the potato loses a life; when nobody holds it, the player nearest to it does. Everybody has
3 lives. A player with no lives left is out. The last player with lives wins.

## Round flow

| Phase | How long | What happens |
|---|---|---|
| live | the fuse: 10-20 s at first (`host.rng`), the range x 0.92 after every pop, never under 8 s | the potato is in play; the HUD shows who has it, never the time; the potato throbs faster as the fuse burns down. GO! for the first second |
| pop | 1.6 s | POP! and who it zapped; the cast's zap word over that player; the potato bursts. A player whose last life it was is sent to a side wall of the yard (`host.send_to`) |
| count | 3 s | "3, 2, 1": the potato waits on a random open spot of the yard (away from the players still in when it can); nobody can pick it up yet |
| over | 3 s | "<WINNER> WINS", then the results page |

During the fuse a player who is out cannot hold the potato: if they grab it, it goes back where it lay. A potato thrown out of the yard
lands on a new open spot. A player who leaves online (`drop`) is out at once; a potato in their hands drops where it is.

## Scoring and results

The scores are the lives (the HUD board shows them; players out are greyed). Results: headline `<WINNER> WINS`, sub line everybody else
by place, the last one out first (`2nd THEO  ·  3rd IDA  ·  4th MAYA`). A round that ends early (a player left) ranks the players still
in by their lives.

## Cast slots it reads

| Slot | Field | How |
|---|---|---|
| Players | `players[].name`, `.color`, `.look` | the characters, the HUD names ("MAYA HAS IT"), the lives board |
| Painting (2 players) | `object.kind`, `object.picture`, `object.fit` | the potato is the team's carried thing (`style/carry_item.gd`): the painting (or the pane) standing up, turned to the camera, about 1.1 m across |
| Floating thing (3+ players) | `balloon.shape`, `balloon.picture` | the potato is the team's balloon look (`balloon/balloon_look.gd`) at 0.84 m, its print on the front; a `balloon` shape is drawn as a `ball` (no string on the floor) |
| Logo | `brand.logo` | the print on either one when the cast has no own picture |
| Words | `words.pop`, `words.zap` | POP! in the HUD on a pop, the zap word over the zapped player |

## Controls

Move and jump as usual. GRAB (F; the second keyboard player N; pad X) picks the potato up, GRAB again throws it. The mode's action
button (Z / X) does nothing here. The HUD note says: "WASD move · Space jumps · F grabs and throws · Don't hold it when it pops".

## State (`match.minigame`)

`phase`, `potato` (prop index), `kind`, `holder` (-1 none), `heat` (0-1, how far the fuse burned: the throb only), `go`, `count`,
`lives`, `out` (slots in the order they went out), `pops`, `zapped`, `zapped_out`, `pop_at`, `at`, `winner`. Under 1 KB with ten players.

## Limits

- 2-10 players; with 2 it is one against one. A full game with ten players takes six to seven minutes (at least 27 pops).
- The potato is one of the yard's six props, picked per round; the others stay ordinary props.
- The rules never read the view: who holds it is the yard's prop state (`props().held_by`), where everybody stands is `host.position`.
