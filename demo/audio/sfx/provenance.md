# FRIENDS sound effects

Every sound here was generated for this project with the ElevenLabs sound-generation API (`POST /v1/sound-generation`, model
`eleven_text_to_sound_v2`, 48 kHz PCM). No recording of any other game is included. The contract that the game reads is `mix.json`
(`friends.sfx-mix.v2`, read by `game/game_audio.gd`).

## Files

- `jump-soft.wav`: 2026-10-18, one take, 48 kHz mono PCM16, 300 ms. SHA-256 `31367b8d2773a4150f17b0232d98ee184dad66eacd7582c574728001cad122ad`.
- `sfx-atlas.wav`: 2026-10-19, 48 kHz mono PCM16, all other one-shots in one file (one file keeps the hosted graph small). SHA-256
  `2d50772be3a8f8921d286de0e9c412f5156f1625cfb42aead9a11a19a251a048`. `mix.json` addresses a region as
  `res://audio/sfx/sfx-atlas.wav#<start frame>+<frames>`; `game/game_audio.gd` cuts it. Regions were trimmed, faded and scalar-gained
  only (no EQ, compressor or limiter); loudness is matched per slot with a peak cap.

## What each slot is (prompts are the generation prompts, shortened)

| Slot | Prompt idea | Takes generated |
|---|---|---|
| 8 footsteps | single quiet footstep, rubber sole on concrete / wooden plank / carrying a box, dry, one step | 134 takes over three rounds for footsteps, checkpoint and bounce; 8 picked |
| death | comical sad splash and descending bubbly gloop, one-shot | 1 picked |
| push | soft padded body bump, plush impact | 1 picked |
| bounce | springboard boing, rubbery, quick pitch rise and fall | 1 picked |
| checkpoint | double beep, two quick marimba plucks, second note higher | 1 picked |
| easter | sparkly collectible chime, rising bell glissando | 1 picked |
| timer crack | slow creaking and cracking of a plank under weight | 1 picked |
| timer broken | sharp snap of a wooden board and a short clatter | 1 picked |
| glass break | a large glass bottle shattering on concrete, tinkling shards | 1 picked |
| painting break | not generated: the glass break with the plank snap of "timer broken" mixed under it (−3 dB), 1.464 s, levelled as one sound | mixed from the two slots |

Selection used loudness, length, spectrum and onset measurements only; nobody has listened to these in a human approval pass.
The generation scripts and the raw takes are not part of this tree (they stay in the project's local lab folder).

## Menu pet (`pet-happy.wav`, `pet-sad.wav`, `pet-pet.wav`)

2026-10-19, generated through the Summer asset tools (ElevenLabs sound generation, `eleven_text_to_sound_v2`, 44.1 kHz stereo),
two takes per sound; one picked per sound by onset and loudness measurements. Mixed down to 48 kHz mono PCM16, trimmed at the end,
5 ms fade-in and 60 ms fade-out, one scalar gain to -18 LUFS (peaks under -3.9 dBFS). Played by `pet/menu_pet.gd` (one-shots by
pet state, at -6 dB). Nobody has listened to these in a human approval pass either.

| File | Prompt | Length | SHA-256 |
|---|---|---|---|
| `pet-happy.wav` | tiny cute puppy, two short excited happy barks, high pitched and friendly, dry close recording | 0.82 s | `35b02b1857da07738319d2c35f6aaa1ed23d9c11e101c6f7db76dd8ba1fd3935` |
| `pet-sad.wav` | a small cute puppy giving one short soft sad whimper, gentle and brief, dry close recording | 0.96 s | `0bcf6f7c27c32617cdbb68cd38a0eac747243976af88102832d5d8b3abb614c9` |
| `pet-pet.wav` | a small cute puppy making a soft contented sigh and a little happy pant while being petted, dry close recording | 1.42 s | `f1a18f354fbc959443d045cf31dc0f3bd6d2dd0f35b127177606e162bdee8c36` |

## The full sound pass (2026-10-20, `*.ogg`)

Generated for this project through the Summer asset tools (`summer_assets_generate_audio`, ElevenLabs sound generation
`eleven_text_to_sound_v2`, 44.1 kHz stereo WAV), one take per prompt (two extra single takes for the shove and the landing when a
"four separate ..." take held only one usable hit). No recording, sample or sound of any other game is included or imitated; the
prompts describe generic cartoon sounds. Processing (`friends-logs/audio/tools/process.py`, outside the tree): mixed down to 48 kHz
mono, silence trimmed, 3 ms fade-in and a 30-300 ms fade-out, one scalar gain to -16 LUFS (pet -18, hazard loops -20/-22) with the
sample peak capped at -1.5 dBFS (short transients stay under the target), Ogg Vorbis `oggenc -q 4`. Loops (`*-hum`, `ball-roll`) blend
their last 0.4 s into the first (raised cosine). Variants of one sound (`bump-1..3`, `shove-1..3`, `land-1..3`) were split at the
silences of one take or come from separate takes. Selection and levels used measurements only; nobody has listened to these in a
human approval pass. `mix.json` names them under `events` (variants, gain, pitch range, radius) and `loops`.

| File | Prompt | Length | LUFS / peak dBFS | SHA-256 |
|---|---|---|---|---|
| `ball-roll.ogg` | a heavy wooden ball rolling on a hard floor, steady low rumble, constant level, seamless loop | 1.55 s loop | -20.4 / -1.5 | `46975aa24043e16316c8c0147884000bb2e8fd3beec9aff360c25c56e4eabc7a` |
| `balloon-respawn.ogg` | a big balloon quickly inflating with a stretchy rubber squeak and a happy little pop-in sparkle at the end, short, dry | 0.97 s | -16.0 / -2.9 | `466febdb6b402d5d069523dc38ba8357df9d3fdf74aea50519cd295912165dde` |
| `bump-1.ogg` | four separate light bonks of a big soft rubber balloon being bumped by a head, a hollow rubbery boing each (three usable bonks, split at the silences) | 0.29 s | -19.5 / -1.5 | `6a53f27f7ab5d003968d6dd225cb6517528432563bfd4375d5ee27e524e08b7e` |
| `bump-2.ogg` | four separate light bonks of a big soft rubber balloon being bumped by a head, a hollow rubbery boing each (three usable bonks, split at the silences) | 0.37 s | -18.5 / -1.5 | `fadc3e3a9bd4bdf66c9382f0acc071f3925eeb1df2b2e4f3b682b189ba513d2a` |
| `bump-3.ogg` | four separate light bonks of a big soft rubber balloon being bumped by a head, a hollow rubbery boing each (three usable bonks, split at the silences) | 0.40 s | -17.5 / -1.5 | `69499f616a72a5e21c13521dbbc9bfb92fbd92d280e38d101383accf0c8eaa98` |
| `burn.ogg` | cartoon burn, a character touches fire, a quick sizzle hiss with a little comic poof of smoke, short, dry | 0.76 s | -16.1 / -1.5 | `4e479165b9c59daf8ab4f4bc705b66b009ebb92f0648d2fdeeda637c277fda0f` |
| `countdown.ogg` | a single clean countdown beep for a party game, a round bright marimba-like electronic tone, short, dry | 0.38 s | -18.2 / -1.5 | `ef550b95ad89d5d87a8963bc10844a1c890d0fe7716f83c02ba9bd77786a9579` |
| `crusher.ogg` | heavy metal crusher press slams down onto a steel floor, a deep punchy thunk with a short metallic clank, short, dry | 0.66 s | -21.9 / -1.5 | `0b4319604a48348c0c3783b931dbd8f4d882b7d24a47ae1af3254fdaacab10e9` |
| `escape.ogg` | cartoon wriggle free, a quick rubbery squirm squeak ending in a bouncy pop, a character escapes a hold, short, dry | 0.68 s | -15.7 / -3.2 | `937e5b44be0953263903cd4e5c4e10605f949343169b49aec8b6e71d5e6724a5` |
| `fall.ogg` | cartoon fall, a descending slide whistle as a character falls off a ledge, comic, short, dry | 0.96 s | -16.0 / -5.1 | `7943323c0100dd25981639f34f7b85a7919ce7b235d8eeb15f5ec8ac54151e5e` |
| `fire-whoosh.ogg` | gas fire jet ignites, a quick punchy whoosh of flame bursting out of a nozzle, short, dry | 0.80 s | -16.0 / -3.5 | `7a9191bd7b04cb74d56142db094c2e9be7bca8d66115e99fd13d3b6e0f4d8f4f` |
| `go.ogg` | party game GO signal, a bright cheerful air horn toot with a confetti pop and a short sparkle, punchy, about one second | 1.16 s | -15.7 / -8.5 | `d14558f96d21d43a356ac79e06dd88dcdaa06dd017518e59335b7ff00d3a2681` |
| `goal.ogg` | goal reached in a party game, a triumphant short brass and xylophone fanfare with a crowd cheer and party poppers, joyful, about two seconds | 1.81 s | -16.8 / -1.5 | `68fb3068b9a81005ac732fb97c961295bdc7ce8114ae3676e4b482149ebebd92` |
| `grab.ogg` | cartoon grab, a quick cloth grab rustle with a soft funny effort grunt hup, a character picks up a friend, short and punchy, dry | 0.33 s | -19.2 / -1.5 | `ecc22d4db47ecca3ddbdfc6699a8fc3c80b7b8e1e8b034452443a94faad06b41` |
| `land-1.ogg` | four separate soft landings of a small cartoon character on the ground after a jump (one usable landing) | 0.64 s | -23.7 / -1.5 | `1e919774ef4c8d7c9b7d9e2fb62a20f9b39b7e3adc88c713eee9c091a5967ad2` |
| `land-2.ogg` | a small cartoon character lands on the ground after a jump, one light padded thump with a soft scuff, short, dry | 0.32 s | -23.6 / -1.5 | `4ecf90b282014ec5f5957288bae9e69ff3c9d8fa5809dd848285750da6c59155` |
| `land-3.ogg` | a chubby cartoon character lands heavily after a big jump, one bouncy soft thud with a little rubbery boing, short, dry | 0.37 s | -17.7 / -1.5 | `81c410a0007ef2d30026fbda68675c3db78ebac7e58e935dd5ac49912fac34df` |
| `laser-hum.ogg` | steady electric laser beam hum, a smooth buzzing sci-fi energy drone with a light crackle, constant level, seamless loop | 1.55 s loop | -20.0 / -4.0 | `bf6749238f24908dc3523fb477b929e4a929b6e709cbadddc8afd2e3c27a9bd0` |
| `level-clear.ogg` | level cleared in a party game, a short bright rising xylophone run ending in a happy chime and a few hand claps, joyful, about one and a half seconds | 1.17 s | -16.0 / -2.1 | `d403bb97ae6db0962931c827376c493c5ddc7c51248d0c159d0fe004e9e7f86d` |
| `level-start.ogg` | level start for a party game, a referee whistle double toot followed by a quick upbeat brass stab, short and energetic | 0.86 s | -16.0 / -8.2 | `582aa58ca37daa94ea9a1630f7a4899a0ece046d0bae6f10901df49e7f04d032` |
| `lift.ogg` | cartoon lift up, a character is hoisted overhead, a quick rising slide whistle blip with a soft cloth rustle, short, dry | 0.58 s | -15.8 / -7.3 | `863a8212066c045f72a79b2da78ff636f9e78d0164eae4129641451ccf1b2c27` |
| `lift-hum.ogg` | a small electric lift platform motor humming smoothly while it moves, soft mechanical whir, constant level, seamless loop | 1.55 s loop | -22.0 / -10.3 | `2fd4c7f660a9bbc8b644af3bbe86b433e7c23dd9672fdd9957774cf88c9bba58` |
| `near-drop.ogg` | balloon dropping dangerously low warning, a quick nervous rising rubber squeak, comic tension, short, dry | 0.52 s | -21.8 / -1.5 | `a9a52b1fa08fcd26bf8274df50fd53d5df728db4876885e4852e03a3567192d0` |
| `pad-enter.ogg` | stepping onto a glowing floor pad in a game lobby, a soft magical rising chime with a light whoomp, friendly, short, dry | 0.68 s | -16.0 / -2.2 | `9243fb5d758b25610f85ebec92e01c75e17b4ece9e6e7d94141fd9a938294f76` |
| `pet-curious.ogg` | a small cute puppy tilting its head curiously, one short questioning rising whine like hm?, dry close recording, no music | 0.67 s | -17.9 / -9.1 | `0129b4aa4efddaf888bdee8ea70ce8635e3396c636d26890f10eb963e954cd6f` |
| `pet-happy-2.ogg` | a small cute puppy very excited, a happy little yip yip and excited panting, wagging, dry close recording, no music | 0.92 s | -18.0 / -4.4 | `dc8b8f867e544a4700f89b5f70839615c5cc2671ce2b7dc80827f094a116d202` |
| `pet-idle-1.ogg` | a small cute puppy sniffing the air curiously, three quick little sniffs, dry close recording, no music | 0.90 s | -19.3 / -1.5 | `5f9a4b3bee2ce0a305680c51766a356e32e4a7ee1d917dd54f35958e2cae57ab` |
| `pet-idle-2.ogg` | a small cute puppy doing a tiny squeaky yawn that ends in a soft little whine, dry close recording, no music | 1.13 s | -18.0 / -2.5 | `9184fa7926e0ed919030275949b812b65fc643d17e69011da2259d3f7d24aef0` |
| `pet-pet-2.ogg` | a small cute puppy being scratched behind the ears, soft happy groan and a contented little sigh, dry close recording, no music | 1.26 s | -19.6 / -1.5 | `d13cf0a887b35ab5a984a6b6a64ad14a28c6241c64da9b8134469738da384f64` |
| `pet-poke.ogg` | a small cute puppy surprised by a poke, one short bouncy high woof, playful, dry close recording, no music | 0.60 s | -18.0 / -8.3 | `bcc8f74d0942ec9b1c5c9db621410fd96fdd23257c0fb5d4f65c85fb8b5ad221` |
| `pop.ogg` | a big balloon pops loudly with a burst of confetti and a little comic deflating squeak after, punchy, dry | 0.57 s | -16.0 / -5.4 | `afa749684ed0c37f4991bd1942eb22b3bb5ce6c1aa0d93cda0b4658980cc72f5` |
| `respawn.ogg` | cartoon respawn, a soft magical poof with a bright twinkle as a character reappears, short, dry | 0.56 s | -18.1 / -1.5 | `8ba67fe5780dac135c73dfd53790b9051874a2a72fee231601aa72d15c25f300` |
| `shove-1.ogg` | four separate soft cartoon body bumps, two plush characters bonking into each other with a padded thud and a tiny squeak (one usable bump) | 0.16 s | -22.1 / -1.5 | `97c9856ae650c38a8510987c85636f13f12ad651e3c0890f14fb850ea167a2df` |
| `shove-2.ogg` | one soft cartoon body bump, two plush characters bonk shoulders, a padded thud with a tiny rubbery squeak, short, dry | 0.47 s | -30.1 / -1.5 | `7988167af692f60a6fad4e0e38c304cbbc1c608fefc724b5e4d819dad8c83734` |
| `shove-3.ogg` | a playful cartoon shove, a quick soft whump of a padded body pushed aside with a little cloth rustle, short, dry | 0.40 s | -20.1 / -1.5 | `9acc10fe16c3251917c808e5a87029d5a77503505cf0619262e299a492f0db22` |
| `slap.ogg` | crisp cartoon slap of a hand on a big rubber balloon, a sharp smack with a springy rubbery thwong after, very punchy, short, dry | 0.36 s | -19.1 / -1.5 | `850637a9d05ea755e8a1eecd9258b610df8c7971ec929748fb96a86a7ae97cc8` |
| `spikes.ogg` | metal spike bed shoots up out of the floor, a sharp metallic shing with a mechanical clack, short, dry | 0.49 s | -23.8 / -1.5 | `75d0128b9b138b6c7929e08717a4e61c955c70827011ca0d2f6045a65883897b` |
| `sweeper.ogg` | a big padded sweeper arm swinging past fast, a deep airy whoosh, short, dry | 0.58 s | -17.8 / -1.5 | `4c05c7e778be5581a0a92eb1809a9384da64f23c14bd8c4e52510fff6544c155` |
| `swing.ogg` | a quick cartoon arm swing whoosh, a light short swish of a hand through the air, dry | 0.43 s | -24.0 / -1.5 | `05cbf1e64bcabf06e6947507fd729c18f8a41885415f46452522ff40ef0f6315` |
| `throw.ogg` | cartoon throw, a fast airy whoosh swish with a little springy launch twang at the start, short and punchy, dry | 0.35 s | -16.7 / -1.5 | `104a7afea701676dda8bcc66d0109bce5cd3496d27402112a9cd675b1af6994b` |
| `ui-back.ogg` | soft cartoon UI back button sound, two quick descending bubbly blips, gentle and friendly, short, dry | 0.44 s | -23.5 / -1.5 | `cd0b383ec649a30c5175233560131ca3bef65d373f094e8e1376d2b65c9ab2b4` |
| `ui-click.ogg` | bubbly cartoon UI button click for a cheerful party game, a bright round pop with a tiny wooden knock, short and punchy, dry | 0.48 s | -29.5 / -1.5 | `7db8ffaabfc196a1fedd3c1c1537dd7548b0a218f32e4d0befcafd11b46a1581` |
| `ui-hover.ogg` | soft rounded UI hover tick for a cheerful party game menu, a tiny wooden marimba tap, very short, dry, no reverb | 0.36 s | -16.3 / -1.5 | `210ca35c145e98b56a6da657396ebccf353e17726a1c1e32b2d919a6ceddcd76` |
| `ui-stamp.ogg` | punchy cartoon stamp thump for a game menu, a rubber stamp hitting paper on a wooden desk, short, dry | 0.31 s | -21.2 / -1.5 | `7cc4c2e7a88b34513bf5a3d141a2de8ea9febb08369b06f8f83eeec9df0b7f26` |
| `ui-start.ogg` | joyful short start jingle for a party game PLAY button, a bright rising marimba and glockenspiel arpeggio ending on a happy sparkle, a little hand clap, about one second | 1.21 s | -16.0 / -1.7 | `a9d78ef0dbbf693dec4a477adefb326e18dada3f4d41d9beac7b6f5bfe5f199d` |
| `ui-toggle.ogg` | small satisfying toggle switch click for a game menu, a light plastic tick with a soft rising blip, very short, dry | 0.16 s | -21.6 / -1.5 | `1adb7b6ab5a9e66bb18662a7228af8b976a4b359481b1b3470d372c7d481fce8` |
| `wardrobe-close.ogg` | a wooden wardrobe door closes with a soft solid thud and a little latch click, short, dry | 0.46 s | -25.6 / -1.5 | `3b5477ba4af2b7c4b4ddd6e2606d5df5c575ecf0806c8d684c6f5cff324f0708` |
| `wardrobe-open.ogg` | a wooden wardrobe door swings open with a cheerful creak and a soft sparkle chime, short, dry | 0.64 s | -21.7 / -1.5 | `042f827410d7b745e54f0beba3c9ef1bbb322467ccbde90329848e3878e1fed0` |
| `wardrobe-pick.ogg` | trying on a new outfit, a quick clothes swish with a wooden hanger clack and a tiny bright ding, short, dry | 0.53 s | -24.4 / -1.5 | `dc5325dd5c1fff906bc1ff73162ce0477ca5d23b42887c4501dcf37a75ab1e02` |
| `wobble.ogg` | nervous wobble of a framed glass painting about to slip, a quick wooden frame creak with a shaky glass rattle, short, dry | 0.74 s | -21.9 / -1.5 | `bbad7f493392c73d3042508942c1009aa574e464a1b6183e272009374ee347b8` |
| `zap.ogg` | cartoon electric zap, a character gets zapped by a laser, a sharp buzzy crackle with a funny boing at the end, punchy, short, dry | 0.61 s | -15.8 / -4.6 | `464c75c9747e534d332986519cfa8f2e3257c956dab8f950db71acb2b0b347a4` |

Surface footsteps (`footsteps.surfaces` in `mix.json`: metal on movers, ice on ice blocks), the same tools and processing, levelled
to -20 LUFS and cut to 0.3 s:

| File | Prompt | Length | LUFS / peak dBFS | SHA-256 |
|---|---|---|---|---|
| `step-metal-1.ogg` | one single light footstep of a rubber sneaker on a hollow steel platform, a soft metallic tap with a tiny ring, short, dry | 0.30 s | -23.1 / -1.5 | `93fa46abd0971795af8c43ef6495a39dbedb2d07d5aefe5c7b3d6b1984a41743` |
| `step-metal-2.ogg` | one single quick footstep on a brushed metal lift floor, a dull clank of a soft shoe on thin steel, short, dry | 0.30 s | -20.9 / -1.5 | `4e350b2b0165883a1b7597fb317408eb0ec3dec00197a6966a58f0e9505cc8b2` |
| `step-ice-1.ogg` | one single footstep on a slippery shiny plastic ice floor, a light squeaky rubber sole slip, short, dry | 0.30 s | -21.9 / -1.5 | `e04dd29ed1389cae91b75b37a43dfcd01c4e39aa1f449e92ddd672f19d1ff349` |
| `step-ice-2.ogg` | one single sliding step on a slick glossy plastic floor, a short high sneaker squeak, dry | 0.30 s | -24.5 / -1.5 | `1347260337b21a69a7ffa47429a047c2fb0be7bdf112a816d36e589ecd870687` |

The footstep runtime shape is pitch −2 … +0.5 semitones, gain 1, radius 0.32 m, fall-off 12 m. The ending sting
(`audio/music/end-sting.wav`, ElevenLabs Music) is described in `../music/provenance.md`.
