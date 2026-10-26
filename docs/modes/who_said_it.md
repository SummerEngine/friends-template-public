# WHO SAID IT? (`who_said_it`)

A line shows; everybody runs to the pad of whoever says it. For groups that know each other's catchphrases. 2-10 players
(on one machine the two local players). Pick it with `"mode": "who_said_it"` in the cast (`docs/modes.md`).

Files: `demo/modes/who_said_it/rules.gd` (what counts), `demo/modes/who_said_it/view.gd` (what players see),
`tools/modes/who_said_it_check.gd` (the headless check).

## The yard

Every character of the round has a pad on the open yard floor, in a ring around the middle of the yard (an ellipse wider than deep,
as big as the number of pads needs): the lobby circles' paint in the character's colour, the name painted on the pad's inner edge.
On the outer edge of each pad stands a statue of that character on a white plinth with a band in its colour: the character in its
cast look (`players[i].look`), frozen in its emote, with a name tag over it. The statues are solid; the paint is not.

The ring keeps clear of the trampoline, the swings, the slide, the ball pit, the furniture, the walls and the team's floor word for
every player count (the check measures it). Neighbouring pads stand at least 3.2 m apart, so standing on one is never ambiguous: a
player is on a pad within 1.2 m of its middle and stays on it up to 1.45 m (a jump on the pad keeps the player on it).

Everybody starts each race on the start ring in the middle (1.3 m around it, facing north). The spots turn one place every round, so
nobody keeps the nearest one.

## A game

| Beat | Seconds | What happens |
|---|---|---|
| Get ready | 3 (round 1), then 1 | Everybody on the start ring. HUD: GET READY (round 1 also explains the game) |
| The race | 4.5 | The line shows big on the HUD and in a speech bubble over the middle of the ring; everybody runs to a pad. The timer counts down |
| The reveal | 2.5 | The right pad lights up, the others fade; its statue plays its character's emote and the line hangs over it (with the character's voice clip when the cast has one); +3 / +1 rise over the scorers |

Ten rounds, about 82 seconds; then the results page. The players walk, jump, shove, grab and throw each other and the yard's props
as everywhere in the yard: shoving somebody off the right pad before the round closes is part of the game.

## Scoring

- The first player who steps onto the right pad after the line shows: **3 points**.
- Everybody else on the right pad when the round closes: **1 point**.
- Only where a player stands when the round closes counts: stepping off resets the arrival. A player who already stood on the right
  pad when the line showed scores 1 at most; the 3 go to the first who arrives after it showed.
- Results: `<NAME> WINS`; a tie of two or three `TIE: A & B` / `TIE: A, B & C`; more `<n>-WAY TIE`; `NO WINNER` when nobody scored.
  The line under it is every score, best first. A player who left cannot win.

## The lines

- The catchphrases (`players[i].catchphrase`) of the characters in this round, shuffled and dealt again until ten rounds are filled,
  never the same line twice in a row. A character without a catchphrase has no line of its own (its pad is still there).
- A player's own line counts like any other: they run to their own pad.
- Two characters with the same catchphrase (letter case aside): one line, both pads are right.
- Fewer than two characters with a catchphrase: the round's catchphrase (if any) plus the cast's words (`words.delivered`, `break`,
  `fall`, `pop`, `zap`, `burnt`; the template's words where the cast has none) and eggs (`eggs`) fill the rounds. Each word and egg is
  given to a character in turn (round-robin, from a random one), and the HUD asks it as "Who would say: <line>?" (no extra question
  mark after a line that already ends in `?`, `!` or `.`). The same text twice counts once.
- Lines keep their case on the speech bubbles. The HUD's big word is in capitals; a line too wide for it goes on the sentence under it.

## Cast slots it reads

| Field | Where it shows |
|---|---|
| `players[i].name` | the pad's floor name, the statue's name tag, the scoreboard, the reveal, the results |
| `players[i].color` | the pad's paint, the plinth's band, the name tag's type |
| `players[i].look` | the statue (`CharacterLook.defaults_for_seat`: the cast look, not a player's wardrobe look) |
| `players[i].catchphrase` | the lines (up to 60 characters) |
| `players[i].emote` | the statue's frozen pose and its move at the reveal; `point` without one |
| `voice/member_<n>.ogg` and its variants | one of them at the reveal of that character's catchphrase |
| `words.*`, `eggs` | the filler lines (only with fewer than two catchphrases in the round) |

## Controls

Shown in the HUD note: WASD move, Space jump, F grab (the second player on one keyboard: IJKL, M, N). Run onto the pad of whoever says
it; shove by running into somebody. The mode does not use the action button (Z / X).

## Limits

- 2-10 players online; two on one machine. Seats beyond the cast list play the default seat look and have no line.
- A player who leaves online: greyed on the scoreboard, never sent anywhere again, cannot win; their pad stays and their lines still
  come up (the answer is their pad).
- The state the view gets is a few hundred bytes: phase, round, seconds left, the line (only while it shows), the answer (only at the
  reveal), who scored, the scores and who left.
