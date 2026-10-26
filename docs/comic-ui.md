# Interface: the candy menu look

The menus wear the party world's own candy look:
bright saturated full-screen backdrops (yellow concentric rings), chunky rounded plates with a white rim and a thick bottom bevel
(a big pink PLAY, cyan secondaries), a charcoal top bar with tabs, violet sheets with a white rim, cyan chips, white heavy italic
Lilita One (OFL) with a dark violet outline, slanted plates and rows. The **in-round HUD** (pills,
banners, GOAL sign, round card, name tags, the lobby's status and name chips: `client/show_theme.gd`, `style/show_hud_kit.gd`,
`style/show_banner.gd`) keeps its dark pills: they are the approved HUD. The file names (`comic_text.gd`, `hud_comic.gd`,
`menu_skin.gd`, `comicify`) are only names: they draw this look.

## The kit (`style/menu_kit.gd`, `Kit`)

- **Colours**: `Kit.primary_color()` is the brand's accent colour (`TeamCast.brand_accent()`, saturated and bright) and the template's
  pink without one; PLAY, the chosen tab, the slider and progress fills, the logo's extrusion and the title cushion take it
  (`docs/swappables.md` `brand_colors`). Secondary plates and chips are cyan (a violet when the primary is itself cyan), sheets violet,
  the top bar charcoal. `Kit.draw_backdrop` is yellow; behind a yellow or orange brand colour it is violet, so the primary never sinks in.
- **Plates**: `Kit.Chunk` is a vector StyleBox (drop shadow, white rim, a thick lip = the bottom bevel, face bands, gloss) for the
  states normal / hover / pressed / disabled, drawn at any size, no textures. A button's meta `&"kit_slant"` leans the whole plate
  (the title's PLAY, 0.2) with a matching focus ring (`Kit.Ring`). Roles (meta `&"comic_role"` of a Button): `primary` and `chosen` (the
  brand's colour), `plain` (cyan, the default secondary), `tab` (light violet, an unchosen tab on a sheet), `go` (green), `danger` (red),
  `blue`, `cream` (keycaps). `Kit.dress(button, role)` adds the springy press (squash on press, pop on release) and the focus ring
  (white with a dark halo, readable on yellow, violet and pink); mouse hover and keyboard/pad focus are one state.
- **Sheets and chips**: `Kit.panel("sheet" | "glass" | "cream")` (violet with a white rim; see-through violet over a 3D stage; a white card
  with a violet rim), `Kit.pill_box()` (a cyan chip with a white rim), `Kit.chip` / `Kit.chip_words` (the drawn twins), `Kit.slab` (a
  leaning parallelogram: the results' rows and clear time), `Kit.bar_box()` (the top bar's charcoal band), `Kit.theme()` (the Theme every
  menu viewport takes). `Kit.hud_pill_box()` is the HUD's own dark pill for what sits over the live world (the lobby's status line and name
  chips). `Kit.label / heading / overline / button` mirror the `Ui` helpers; `Ui` itself (Inter, palette) stays for the 3D lobby boards.
- **Lettering** (`comic_text.gd`, kit mode `set_kit(fill, edge, deep, slant)`): Lilita One, slanted, an outline and an extruded lip;
  `HudComic.word` and `ComicSkin.comicify` use it. The dark outline is `Kit.EDGE` (a deep violet); buttons take their role's shade.
- **Backdrop**: `Kit.draw_backdrop(ci, rect, clock, tone, at)` paints the full-screen page: a radial gradient (bright middle, deeper hue
  at the corners), concentric rings turning slowly outward from `at`, a soft glow. Tones: `sun` (yellow: title, Settings, customizer),
  `sea` (cyan: loading), `grape` (violet: error), `berry`.
- **Logo**: `Kit.LogoMark` draws the team's title in big white italic type with a dark violet outline and an extrusion in the primary's
  shade; the part after a colon in the title (or the balanced second line of a long one) sits under it on a cyan chip.
  It pops in and bobs. `Kit.rank_badge` draws the gold / silver / bronze medals and a violet numbered disc after.
- **Stage** (`style/menu_stage.gd`, `MenuStage`): a 3D backdrop in its own World3D. Title: a transparent viewport (the page's rings show behind it)
  with the cast's characters (the real rigs, the cast's looks) grouped on the podium blocks over a round satin cushion in the primary colour,
  doing yes / dance / point and their own emote in turn; PLAY makes them jump. Results: the show's podium room (`style/podium_room.gd`) with the
  top three landing on the victory flow's timeline. Not built in headless runs. The cast's own `title_backdrop.*` art still wins on the title.

## Screens

- **Title** (`main_menu.gd`, `menu_skin.gd build_main_menu`): logo banner, the tagline on a dark pill, PLAY (gold, big), the
  play note on a pill, SETTINGS / INVITE A FRIEND / QUIT as dark chunky plates. Buttons are real Buttons named by action key.
- **Settings and pause** (`menus.gd`, widgets in `friends_widgets.gd`): a violet sheet with a white rim and chunky tabs (the chosen one the
  primary, the others light violet), rows as translucent sub-slabs, green toggles, primary-coloured sliders on deep violet tracks, segmented
  pickers with a sliding primary pill, cream keycaps in the hint bar. From the title the page is the yellow rings; in a run the world shows
  through a violet wash. RESUME / BACK is the primary, the others cyan, Main menu red.
- **Customizer** (`character/wardrobe/wardrobe_ui.gd`): the violet sheet, kit tabs, tiles with a gold ring, kit sliders; the 3D preview
  stands on a round pedestal over the yellow rings page.
- **Loading, error, notice, lobby chips, results** (`online_screens.gd`, `results_parts.gd`): status pages on the rings page (loading sea
  blue with a primary-coloured progress bar and green / primary step badges, error violet, notice yellow), big outlined lettering, cyan
  chips and a violet detail card; the lobby chips stay the HUD's dark pills over the live yard; the results page is the headline in big
  white outlined italic type (orange for a win, red for a time's up, violet and pink for the rest; a gold crown over a champion) with its
  line on a chip, the tri-colour corner stripes at the top left, and one leaning violet slab per rank (medal, portrait bust from
  `menu_portraits.gd`, name on the player's colour, points counting up, a gold rim for the winner) over the podium room.
  The rows come from the mode's `results()` (`rank`, `points`; `modes/show/rules.gd` also gives `order`).
- **Credit watermark** (`online_screens.gd _build_credit`): the results' one credit line is a watermark, not a button: small white type at
  45 % alpha with a faint outline and no frame in the screen's bottom right corner ("Made by the <team> team · <link>", "Make one for
  your team" above it). It is a flat `Button` named `Credit` with empty plates (so a click still opens `team.credit_link`, the cursor turns to a
  hand and the words brighten to 80 % over it; nothing opens by itself); with no link it is hidden.
- **HUD leftovers** (`level_hud.gd`, key hints): the HUD's pills and Lilita (not part of the kit).

## Proof tools (offscreen only, never windowed)

- `tools/menu_kit_shots.gd --out=<dir> --prefix=<p> [--only=title,settings,pause,wardrobe,loading,error,notice,lobby_hud,results_show,results_six,results_solo,results_run] [--touch]`:
  one boot, every screen above to PNGs (desktop 1280x720, phone `--resolution 844x390 -- --touch`); `--credit` gives the cast a credit link (the watermark), `--brand=#rrggbb` a brand colour.
- `tools/comic_ui_shots.gd`, `tools/loading_shots.gd`, `tools/hud_comic_shots.gd`, `tools/levels_flow_check.gd --shots=<dir>`: the
  per-screen shots.

Fonts must be force-added (`git add -f demo/assets/fonts/...`): the folder is gitignored.
