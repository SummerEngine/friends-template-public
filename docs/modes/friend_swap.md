# FRIEND SWAP (`mode: "friend_swap"`)

Everyone plays as someone else, then everyone guesses who is who. For a group that knows each other well: 3-10 players online,
the two local players on one machine (they simply swap). The rules are `demo/modes/friend_swap/rules.gd`, the look
`demo/modes/friend_swap/view.gd`, the check `tools/modes/friend_swap_check.gd`. The framework around it: `docs/modes.md`.

## The round

1. **The swap.** Every player gets another player's character: that cast member's look, name tag and catchphrase. Nobody keeps
   their own (a random derangement drawn from the round's random numbers). The HUD says who you are: "YOU ARE MAYA" big for the
   first 5 s, then "PLAY AS MAYA" with the timer. Your own tag stays hidden online; on one machine both tags show.
2. **Free play, 60 s.** The yard as always: walk, jump, shove, grab and throw. The action button (the lift keys Z / X) makes your
   character say its catchphrase in a speech bubble, with one of its voice clips and its emote. At most one line every 2 s.
3. **The votes, one character at a time** (in a shuffled order, about 8 s each). Everyone is sent back to a ring round the yard
   centre. One pad per player appears on a wider ring, each with a board showing that player's **real** name, in a shuffled order.
   The HUD asks "WHO IS PLAYING THEO?" and an accent ring marks the character. Everyone runs to the pad of the person they think
   plays it; the player playing it does not vote (and may stand anywhere to mislead). Where your feet are when the time runs out
   is your vote; no pad, no guess.
4. **The reveal** (3.5 s): "IT WAS IDA!". That character turns back into its real player (look and tag), the right pad lights up,
   the HUD says how many guessed right. Then the next character.
5. **The end**, after the last reveal: the results page says "<WINNER> WINS" (a tie names everyone in it, five or more is
   "A 5-WAY TIE") over the score line.

## Scoring

| At each vote's close | Points |
|---|---|
| A voter on the pad of the player playing the character | +1 for the voter |
| A voter on any other pad | +1 for the player playing the character (good acting) |
| A voter on no pad | nothing |

The scoreboard shows on the right from the first close on.

## Slots it reads

| Cast field | Used for |
|---|---|
| `players[i].name` | the name tags, the "YOU ARE" line, the vote question, the pad boards, the results |
| `players[i].color`, `skin`, `hair`, `look` | the character look a player borrows (`CharacterLook.defaults_for_seat`); the pad colour of that player |
| `players[i].catchphrase` | the line the character says; without one: "It's me, <Name>!" |
| `players[i].emote` | the emote with the line (a catalog emote: dance, sit, yes, no, point, think, cry); else "yes" |
| `voice/member_<n>.ogg` (+ `_1..3`) | one clip at random with the line |
| `mode` | `"friend_swap"` picks this mode (one game, one mode: `AGENTS.md`) |

A seat beyond the cast is "PLAYER n" with the seat's default look. Words and pictures of other slots stay as the yard has them.

## Controls (taught in the HUD note)

Online: WASD move, SPACE jump, F grab, Z / X say your line. On one machine the second player uses I J K L, M, N and H / Y.

## Limits and edge cases

- 3 players minimum online (`demo/modes/modes.json`); a two-player local game plays with the two local players.
- A player who leaves votes no more and has no pad in the later votes; the character they played is skipped. If they leave
  during the vote on their own character, that vote stops at once and the next one starts. The round plays on while two or more
  are left (online it ends when fewer than three are).
- The pads stand 5.6 m from the yard centre, clear of the playground, the furniture and the walls for any count from 2 to 10 (the
  check sweeps every count and turn). They are paint and a board on posts: nothing collides, the rules read only the feet.
- Every look goes back to the real one when the round ends, also when a player's own look reached the client during the round.
- A swapped character plays no idle emote while it stands still (that emote is its real player's and would give them away).
- Timing: 60 s of play plus 11.5 s per character (about 3 minutes with ten players).
