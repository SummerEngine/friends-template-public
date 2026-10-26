# FRIENDS music

`friends-careful-step.wav` (the default loop) and `end-sting.wav` were generated for this project with the ElevenLabs Music API (model
`music_v2`). They are our own generated audio; the licence is the project's.

The six genre loops (`friends-<id>.ogg`, the cast's `music` ids other than the default) are edits of third-party instrumental tracks
that their authors released under CC0 1.0 (public domain dedication, https://creativecommons.org/publicdomain/zero/1.0/) on the page
named in each section. CC0 needs no attribution; the title, author and page are kept here as the record of where each file comes from.
No other game's audio, tune, score, sample or recording is included.

## `friends-careful-step.wav` — the gameplay loop ("Careful Step")

- Generated 2026-10-18 through Summer with ElevenLabs Music `music_v2` (audition "D"). The generation prompt was written by an AI
  coding assistant (Claude via OMP); the same assistant chose the loop edit. The raw MP3 and the prompt live in the project's local
  build folder and are not part of this tree. Audition D was picked after listening, as long as it loops properly.
- The shipped file is an edited loop of that recording: loop period 45.75 s, stereo PCM16 at 48 kHz (2,196,000 frames). It uses
  source seconds 6.5–48.25 followed by a four-second raised-cosine blend of 48.25–52.25 into 2.5–6.5, so the last and first samples are
  neighbouring samples of the source and the source's ending is dropped. Constant gain −2.29 dB, loudness −18.0 LUFS, true peak −4.70 dBFS.
- Stored as PCM (about 8.8 MB), not a lossy codec. The WAV import keeps `compress/mode=0`
  (`tools/prepare_audio_imports.py`).
- SHA-256 of the file: `f32dccb234c85f41f4d3b512ae8d84dbee3ee4fb7fd4325051c061f799dc963d`.
- Checks done: engine playback wraps the loop three times with the right hash and no silent chunks. Nobody has done a human listening
  approval of the seam; that remains a taste test.

## `end-sting.wav` — the ending sting

- Generated 2026-10-19 with ElevenLabs Music `music_v2` (`POST /v1/music`, `music_length_ms` 29000, `force_instrumental` true, take 3 of 3).
  Prompt: a short instrumental celebration sting, F major, 100 BPM shuffle, brushed drums, upright bass, felt piano, vibraphone,
  a little glockenspiel and hand-claps, ending on a real final cadence.
- Shipped as 28.6 s stereo PCM16 at 48 kHz, gain −0.1 dB. SHA-256 `c2a605bf588febdb0ef1a1fccc786a89b03e4fe687986e1fbdfb69edcd70f777`.

## `friends-lofi.ogg` — the `lofi` loop ("Blue Skies")

- Title "Blue Skies", author Holizna (HoliznaCC0). Source: https://opengameart.org/content/happy-lo-fi-lofi-collection (the
  collection page "Happy Lo-Fi (Lofi Collection)" by Holizna, License(s): CC0, "This music is public domain Cc0, so use it how you
  want!"; the track is `03 HoliznaCC0 - Blue Skies.mp3.mp3` (320 kbps MP3) in `happy_lo-fi_lofi_collection.zip`).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 81.9512 s (3,614,049 frames). Source seconds 50.451-128.402, then a four-second raised-cosine blend of
  128.402-132.402 into 46.451-50.451, so the last and first samples are neighbouring samples of the source. Constant gain -6.64 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.0 LUFS, true peak -5.5 dBFS (measured on the shipped file).
- SHA-256 of the file: `dba78da369c8ab07c048db5202c1adfeb2cd0b8fe94faa22d2f76abe8874496f`.

## `friends-electronic.ogg` — the `electronic` loop ("Happy Dance")

- Title "Happy Dance", author Holizna (HoliznaCC0). Source: https://opengameart.org/content/happy-pop-electronic-collection (the
  collection page "Happy Pop Electronic (Collection)" by Holizna, License(s): CC0, "This music is public domain Cc0, so use it how
  you want!"; the track is `06 HoliznaCC0 - Happy Dance.mp3` (320 kbps MP3) in `happy_electronic.zip`).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 72.0000 s (3,175,200 frames). Source seconds 23.214-91.214, then a four-second raised-cosine blend of
  91.214-95.214 into 19.214-23.214, so the last and first samples are neighbouring samples of the source. Constant gain -5.12 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.1 LUFS, true peak -4.8 dBFS (measured on the shipped file).
- SHA-256 of the file: `dc50b17b27ab0e6f1e63db3007c11b200403a25a3fe9aaee0e26cffee624efcc`.

## `friends-hiphop.ogg` — the `hiphop` loop ("Sunglasses")

- Title "Sunglasses", author Loyalty Freak Music. Source:
  https://freemusicarchive.org/music/Loyalty_Freak_Music/INSTRUMENTAL_RB_BEATS_TO_SING_OR_RAP_ON/Loyalty_Freak_Music_-_INSTRUMENTAL_RB_BEATS_TO_SING_OR_RAP_ON_-_01_Sunglasses/
  (the track page on the Free Music Archive, "Sunglasses by Loyalty Freak Music is licensed under a CC0 1.0 Universal License",
  album "INSTRUMENTAL R&B BEATS TO SING OR RAP ON" (2018), 320 kbps MP3).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 65.8286 s (2,903,040 frames). Source seconds 60.308-122.137, then a four-second raised-cosine blend of
  122.137-126.137 into 56.308-60.308, so the last and first samples are neighbouring samples of the source. Constant gain -3.80 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.1 LUFS, true peak -3.9 dBFS (measured on the shipped file).
- SHA-256 of the file: `bbf657eae3b97277ad91eed2e59f7236870fda158c2cd6a9ebe36ff118c0f365`.

## `friends-indie.ogg` — the `indie` loop ("Can't Stop My Feet !")

- Title "Can't Stop My Feet !", author Loyalty Freak Music. Source:
  https://freemusicarchive.org/music/Loyalty_Freak_Music/ROLLER_DISCO_DANCE_DANCE/Loyalty_Freak_Music_-_ROLLER_DISCO_DANCE_DANCE_-_04_Cant_Stop_My_Feet_/
  (the track page on the Free Music Archive, "Can't Stop My Feet ! by Loyalty Freak Music is licensed under a CC0 1.0 Universal
  License", album "ROLLER DISCO DANCE DANCE" (2018), 320 kbps MP3).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 73.8461 s (3,256,615 frames). Source seconds 54.422-124.268, then a four-second raised-cosine blend of
  124.268-128.268 into 50.422-54.422, so the last and first samples are neighbouring samples of the source. Constant gain -6.10 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.1 LUFS, true peak -6.2 dBFS (measured on the shipped file).
- SHA-256 of the file: `182059cd9777447d90086c0fe39514950062be330f1c164b6a3402dfc530aecb`.

## `friends-funk.ogg` — the `funk` loop ("Funky Disco Beats to Boogie/Woogie to")

- Title "Funky Disco Beats to Boogie/Woogie to", author Fupi. Source:
  https://opengameart.org/content/funky-disco-beats-to-boogiewoogie-to (the track page on OpenGameArt, License(s): CC0; the file is
  `funkydiscobeatstoboogieslashwoogieto_0.ogg`).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 66.5455 s (2,934,655 frames). Source seconds 37.599-100.144, then a four-second raised-cosine blend of
  100.144-104.144 into 33.599-37.599, so the last and first samples are neighbouring samples of the source. Constant gain -1.90 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.0 LUFS, true peak -2.1 dBFS (measured on the shipped file).
- SHA-256 of the file: `2f08275ad34f04ee87f6a092e25a156ebc96372fa3c59df0c5b744af62ad62b4`.

## `friends-epic.ogg` — the `epic` loop ("Determined Pursuit (epic orchestra loop)")

- Title "Determined Pursuit (epic orchestra loop)", author Emma_MA. Source:
  https://opengameart.org/content/determined-pursuit-epic-orchestra-loop (the track page on OpenGameArt, License(s): CC0; the file
  is `determined_pursuit_loop.wav` (PCM WAV)).
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/. Downloaded 2026-10-19.
- Edit: loop period 72.0000 s (3,175,200 frames). Source seconds 26.982-94.982, then a four-second raised-cosine blend of
  94.982-98.982 into 22.982-26.982, so the last and first samples are neighbouring samples of the source. Constant gain -5.60 dB,
  Ogg Vorbis (`oggenc -q 4`) stereo 44.1 kHz. Loudness -18.1 LUFS, true peak -5.8 dBFS (measured on the shipped file).
- SHA-256 of the file: `12c25078d2303029ec68c67b94f16ac19b76ed1aeb46fc9c2fde25f7d018bda9`.

The six genre loops: the loop point and period were picked by measurement (the period where the track repeats, then the start whose
four seconds before it match the four seconds before the period's end, sample-aligned by waveform correlation; 0.92-0.9999), and the
start moved onto a nearby beat. Engine playback (`AudioStreamOggVorbis` with `loop` set by `music_stream`) wraps each loop twice with
output equal to the decoded file across both wraps and no silent chunks. The original downloads and the licence page text are kept
outside the tree. Nobody has done a human listening approval yet; genre fit and the seams remain a taste test.

## `title-loop.ogg` and `lobby-loop.ogg` — the title and yard loops (2026-10-20)

Generated for this project through the Summer asset tools (`summer_assets_generate_audio`, ElevenLabs Music `music_v2`, one take each,
44.1 kHz stereo MP3). Our own generated audio; the licence is the project's. The prompts were written by an AI coding assistant
(Claude) and describe generic instrumentation; they name no other game, artist or tune.

- `title-loop.ogg` (game/game_audio.gd `music_path("menu")`, also the first track the music player starts with). Prompt: cheerful
  bouncy instrumental title theme for a colourful friends party game, 120 BPM, C major, ukulele strums, plucky marimba melody,
  playful pizzicato strings, glockenspiel sparkles, warm bass, light claps, shaker and a tight snappy drum kit, steady energy, no
  intro and no ending, instrumental. Take 48.04 s at a measured 119.96 BPM. Loop: source seconds 2.000-41.998 (20 bars), its last
  2 s blended (raised cosine) into source seconds 0-2, period 39.998 s (1,763,928 frames at 44.1 kHz). Gain -2.40 dB, -18.0 LUFS,
  peak -2.0 dBFS, Ogg Vorbis `oggenc -q 4`. SHA-256 `6b79d66005da517b850a4a0b3ff2cf3e4a55b5ccc5b349913dd9058493596a68`.
- `lobby-loop.ogg` (`music_path("lobby")`, the walk-in yard). Prompt: light laid-back instrumental hangout loop for the waiting yard
  of a playful friends party game, 96 BPM, F major, soft muted electric guitar plucks, gentle vibraphone, warm upright bass, brushed
  drums, finger snaps and a soft whistle-like synth, sunny and relaxed, low energy, no intro and no ending, instrumental. Take
  40.05 s, a 10 s (four-bar) pattern. Loop: source seconds 2.500-32.505 (12 bars), its last 2 s blended into 0.5-2.5, period
  30.005 s (1,323,225 frames). Gain -2.10 dB, -18.0 LUFS, peak -3.2 dBFS, `oggenc -q 4`. SHA-256
  `e442caff899e70987026675c27de11d19cd3e47936ca74e52f7f880d7bb5718a`.
- The results phase plays `end-sting.wav` once (`music_path("results")`); in a round the cast's `music` id plays.
- Nobody has done a human listening approval of either loop or its seam yet.

The playback code is `game/game_audio.gd` (`install_music`, `set_music`, `music_stream`).
