# Gridiron Run

A 2D football roguelike in Godot 4.3. You coach the offense of one team through a
five-round bracket. Every match is 4-5 drives; you set the lineup, hand out items,
and then **draw the routes** — each of your five flex players gets 30 yards of chalk,
and you drag his route straight onto the field before the snap. The play then
simulates in real time and the QB throws to whoever actually gets open. Football
bucks earned on the field buy players and items between rounds. You get 3 losses across the whole run before the season is over; a loss that
doesn't end it just sends you back to retry the same round.

## Running

Open the folder in Godot 4.3 and press play, or:

```
godot --path . 
```

## Dev mode

The main menu's "Dev mode" button (`GameState.start_dev_mode`) drops you
straight into an endless scrimmage, skipping the QB pick, bracket, and shop
economy entirely: a maxed-out roster (`Generator.full_roster`, which unlike
`starting_roster` doesn't clamp everyone into the rookie 2-4 band) plus every
hardcoded shop player for their unique abilities, and every item,
all available from the start. Drives never run out (`GameState.DEV_DRIVES`
is just a very large number, so the "last drive" checks in `match.gd` and
`MatchSim` never actually trigger - no separate infinite-mode flag needed).
The chalkboard between snaps gets a "Defender power" slider
(`MatchSim.regenerate_defense`) that swaps in a freshly generated defense at
the chosen quality immediately, without waiting for a new drive. "Lineup"
and "Exit dev mode" links sit in the top bar - items can only be equipped
from the lineup screen, since the in-match sub panel only swaps players.

## Layout

```
scripts/
  data/        player_data, ability_db, item_db, route_book, play_db, generator,
               qb_db, shop_player_db
  core/        game_state.gd  (autoload: roster, lineup, drawn routes, bucks, bracket, shop)
  sim/         sim_player.gd, match_sim.gd  (the play simulation)
  ui/          ui_kit, field_view, route_thumb, play_diagram, one script per screen
scenes/        one .tscn per screen; each is a bare Control that its script fills in
data/          shop_players.json - the hardcoded shop roster as data, not code
               items.json - every item (helmet/gloves/cleats); field list in item_db.gd
tools/         headless test and tuning harnesses (not part of the game)
```

### The simulation

`MatchSim` owns one play at a time plus the down/drive bookkeeping around it.
Everything is in **yards**; `field_view.gd` converts to pixels. The field frame is
x from 0 to 120 with the offense always attacking +x, so its own goal line is x=10
and the scoring goal line is x=110.

On screen the field is drawn **vertically** — your offense attacks up. Field-x
maps to screen -y and field-y maps to screen x, and the camera follows the ball,
clamped to the field, and biased upward by `bottom_inset` so the ball never
ends up behind the chalkboard.

Players are drawn from above as a slim upright capsule with the jersey number
printed on it and a head circle at the top. They **always stand upright** and
never lean into the direction they are running. Three bits of motion sit on top
of that, all in `_draw_person`:

- a **walk bob**, a side-to-side waddle plus a bounce, driven by
  `SimPlayer.stride`, which advances with distance actually covered rather
  than with wall time
- a **topple** when a player is tackled: `SimPlayer.downed` counts up and the
  body rotates from upright toward the way he was running, the number fades,
  and the shape darkens. The body keeps its own proportions the whole way
  down - it never stretches or elongates, only its facing changes. Being
  tackled is the only thing that ever rotates a body.
- a **pre-snap shift**: redrawing a route sets `target_pos` rather than
  teleporting, and `MatchSim.presnap_step` walks everyone onto their new spots

Sprites can drop in later by replacing `_draw_person`; nothing else touches
player rendering.

Each play runs: formation and routes from the chalkboard -> snap -> per-frame
updates for offense, defense, ball, and contact -> a result dictionary with yards,
a description, and football bucks earned.

### Drawing routes

`RouteBook` (`scripts/data/route_book.gd`) owns the whole chalk system: the flat
**30 yard** budget every flex gets, the formation spots (personnel-aware — backs
and tight ends claim their spots before receivers, so a three-WR set spreads out
and a two-TE set tightens up), the stock routes, and the geometry helpers.

Routes are stored in `GameState.drawn_routes` as `slot -> Array[Vector2]`,
waypoints **relative to that player's alignment** in the same yard frame `PlayDB`
uses. They persist for the whole run, so a concept you like stays on the board
until you wipe it.

The flow is:

1. `field_view.gd` turns a press-and-drag on one of your flex players into a
   stroke in field yards, clamped live to the remaining budget. A press that
   barely moves is still just a click, so inspecting and drawing share one
   gesture.
2. On release the raw trail is run through Ramer-Douglas-Peucker
   (`RouteBook.simplify`) down to a handful of waypoints, re-based onto the
   alignment spot, and emitted as `route_drawn`.
3. `match.gd` stores it and calls `MatchSim.set_drawn_call`, which builds a
   **synthetic play dictionary** — same shape `PlayDB` returns — from the
   formation plus whatever is on the board. Anything undrawn gets a random
   `RouteBook.STOCK` route, rerolled every snap. Because the dictionary has the
   same shape, nothing downstream in the sim had to change.

There is no scripted read order on a drawn call: `progression` is empty, so the
QB works purely off who is open, nudged by the priority targets you flag.

`PlayDB` survives as reference material, not as a game system. Plays are no
longer bought, owned, or called — the **Route Book** screen browses them, the
match screen's EXAMPLES overlay loads one onto your chalkboard as a starting
point you can then redraw, and the batch harnesses in `tools/` still drive the
sim off them (`MatchSim.set_play`) so their tuning baselines stay comparable.

Stats drive the sim directly, per the design doc:

| Stat | Effect |
| --- | --- |
| Strength | Contact rolls (blocking, coverage jams, breaking tackles), and how far a blocker drives his man. Capped at 25% per contact, rolled every 3 seconds. |
| Agility | Top running speed (`2.9 + agility * 0.46` yards/sec). The constant is kept low on purpose — with a large base every player runs at nearly the same speed and nobody can ever be run down. |
| Dexterity | Catch chance (`0.455 + dexterity * 0.031667`), anchored on two design points: 3 DEX catches 55%, 15 DEX catches 93%. Also QB accuracy. |
| Stamina | Fatigue rate. **Hidden from the player**, as specified. |
| Intelligence | Route precision, QB read quality, coverage leverage, pursuit angles, run vision. |

Abilities and items are folded into an effective stat line at the snap
(`_apply_modifiers`), plus direct hooks for catch chance and contact rolls.

**Stat scale.** Rookies start hard-clamped in the **2-4** band with no special
ability; 15 is the ceiling. Bracket opponents start at quality 2.8 and climb
0.7 per round, so signing upgrades is how you keep pace.

**The shop's draft board is hardcoded**, roguelike-item style: fixed names,
fixed stat lines, fixed abilities, no procedural generation. The roster
itself lives in `data/shop_players.json` (not code), loaded and cached by
`scripts/data/shop_player_db.gd` — adding a player is a data edit, not a
script change. The shop always offers exactly 4 players, drawn without
repeats and weighted by rarity tier so higher tiers show up less often
(Rookie/Sophomore weight 1.0, Veteran 0.8, All Star 0.5). Stat bands rise
with rarity: Rookie 2-4, Sophomore 4-6, Veteran 5-9, All Star 7-11.

**Abilities dispatch through Callables, not a match statement per hook.**
`AbilityDB.ABILITIES` maps each id to a name/desc plus whichever hook
methods it needs (`snap`, `catch`, `contact`, `fatigue_floor`, `speed_cap`,
`guarantees_catch`, `disrupted_mult`, `dashes_at_snap`, `passer_dex_bonus`,
`fake_chance`, `on_carry_bonus`, `dodges_once`, `catches_drops`,
`locks_dl_at_snap`, `team_buff`), each a `Callable` pointing at a small
static method like `_snap_corps_of_three`. Adding an ability means writing
one or two of those methods and one dict entry - no existing function needs
to grow a new match arm. `team_buff` is the odd one out: every other hook
only ever affects the ability holder himself, but a Center's "give all
[position] +N [stat]" needs to reach teammates, so `MatchSim._apply_team_buffs`
does a second full-offense pass after individual snap modifiers are baked in.

**Lineup slots are position-locked.** `GameState.fits_slot` is the single
source of truth: the QB slot only takes a QB, C only a Center, the four T
slots only Tackles, and the five FLEX slots only RB/WR/TE. `set_slot`
refuses any assignment that doesn't fit, so this holds everywhere a player
can be placed - lineup screen, in-match substitutions, and auto-fill.

**A run starts with a quarterback pick** (`scenes/qb_select.tscn`, backed by
`scripts/data/qb_db.gd`): five hardcoded QBs with distinct stat lines and no
ability yet. The choice replaces the first generated QB on the roster; the
backup QB stays procedural.

## Test and tuning harnesses

These run headless and print results; none of them are shipped game content.

```
godot --headless --path . res://tools/sim_test.tscn   # balance stats per bracket round
godot --headless --path . res://tools/routesim.tscn   # the same, but for drawn routes
godot --headless --path . res://tools/yac_check.tscn   # post-catch route-following check
godot --headless --path . res://tools/ability_check.tscn  # does a passer ability reach the catch roll
godot --headless --path . res://tools/prop_check.tscn  # peels/chains/kegs/slot machine + mid-play stat gainers fire
godot --headless --path . res://tools/handoff_check.tscn  # yards per carry and who tackles, on Hand Off plays
godot --headless --path . res://tools/sweep.tscn      # win rate vs roster quality
godot --headless --path . res://tools/trace.tscn      # step-by-step trace of one play
godot --path . res://tools/uiflow.tscn                # end-to-end match through the UI
godot --path . res://tools/uishot.tscn                # PNG of every screen (needs a GPU)
```

`sim_test` is the one to watch when changing the sim. Current numbers, against a
roster assumed to improve by +0.55 quality per round:

`sim_test` (scripted plays, the fixed baseline):

| Round | Win rate | Yds/play | Comp % | Sack % |
| --- | --- | --- | --- | --- |
| Wild Card | 50% | 6.6 | 61% | 0% |
| Divisional | 50% | 5.6 | 58% | 1% |
| Conference | 42% | 4.5 | 59% | 1% |
| Semifinal | 0% | 3.7 | 57% | 5% |
| Championship | 0% | 4.1 | 58% | 4% |

Those runs model a roster improving only +0.55 quality per round against a
bracket that climbs +0.7, so by the Semifinal the harness team is a full step
behind. That used to make the offence cave in outright (sack rate hit 34% and
yards per play fell to 0.8); fixing the QB's drop — see the notable-decisions
list — flattened that out, and the late rounds now lose on scoring rather than
on the pocket disintegrating. **Winning the last two rounds still requires
actually upgrading the roster**, which is the intended pressure.

`routesim` (drawn routes, the real game) compares three coaches at three
rounds. This is the table that matters, because it shows the chalkboard is a
real decision rather than decoration:

| Coach | Wild Card | Conference | Championship |
| --- | --- | --- | --- |
| **blank** (nothing drawn, all random) | 6.4 yd/play, 0% sack | 4.5, 2% | 3.4, 11% |
| **spread** (out/slant/dig/post + checkdown) | 5.6, 0% | 3.8, 0% | 4.7, 0% |
| **deep** (all five downfield) | 9.7, 6% | 4.7, 16% | 1.1, 34% |

Chalking a quick outlet essentially removes sacks, because the QB has somewhere
to go with the ball. Sending all five deep is devastating early (9.7 yards a
play against a weak secondary) and suicidal late (1.1 yards a play, sacked on a
third of dropbacks). Drawing nothing is playable but never optimal.

The sim is very sensitive near parity (see `sweep`): about +1.0 quality over the
defense wins comfortably, an even matchup wins roughly 40%.

## Notable design decisions

- **A signed player cuts the rookie he benches** (`GameState.set_slot`). The
  generated starting roster is placeholder filler; once you can afford a real
  player, the rookie he displaces is removed rather than left cluttering the
  bench. Only on a genuine displacement - a straight swap just moves the other
  man to a different slot, and one rookie replacing another is an ordinary
  lineup change. `PlayerData.quality` is the tell: 0 for generated, 1-4 for the
  hardcoded shop roster.
- **Bodies are normalised to equal area, not fitted to a box**
  (`field_view.BODY_AREA`). The sprite sheet is framed very inconsistently -
  front-view aspect ratios run 0.57 to 1.39 - so box-fitting drew the wide ones
  as squat blobs and the narrow ones as tall slivers at visibly different
  sizes. Matching area instead evens them out without touching the art.
- **Head placement is authored in rig scenes, not code**
  (`assets/players/rigs/<view>/body_0N.tscn`, read by `BodyArtDB.head_rig`).
  Each body/view is a Node2D with a locked "Body" sprite and a "Head" sprite:
  open one in the editor, drag/scale/rotate the Head, save. The field and the
  shop/book portraits both pick it up. Front-view `_dark`/`_pale` skin-tone
  variants share the plain body's rig.
- **The team disc is a rim, not a fill** (`field_view.DISC_ALPHA`). The jersey
  art is a fixed navy for both sides, so with the disc faded out the two teams
  became genuinely indistinguishable on the field. The fill stays near
  invisible; the outline carries the team colour.
- **Catching the ball does not cancel the route** (`MatchSim._carry_route_logic`).
  A receiver keeps running the waypoints the coach drew for him and only
  becomes an ordinary ball carrier once they run out - in a game about drawing
  routes the line should not evaporate the instant the ball arrives, and a
  crosser you chalked to keep working across the field now actually does.
  Waypoints that are *not* downfield of him are skipped, because a curl or a
  comeback has him working back toward the QB and finishing that with the ball
  would just lose yards (`yac_check` shows that guard firing on about a third
  of catches). There is deliberately no defender avoidance while he is still on
  the route: drawing one through traffic is supposed to cost you.
- **The drop is a plan, not a contract** (`MatchSim.PANIC_DIST`). The QB used to
  be unable to throw, throw away, or escape until `dropback` elapsed — he just
  backpedalled to his spot. That was survivable when most plays kept a back in
  to help protect, but with all five flexes releasing it made every free rusher
  an automatic sack (56-71% at the top rounds). Now a rusher inside 2.2 yards
  ends the drop early. Bailing is not free, though: while still in the drop the
  bar for a throw is much higher, there is nothing downfield to throw it away
  past, and only a QB with 9+ Agility can escape. Anyone else wears it, which is
  what keeps sacks a real cost rather than a formality.
- **The drop length comes from the quickest route on the board, not the deepest**
  (`MatchSim.set_drawn_call`). How fast the ball can come out is set by the
  shortest outlet available. Keying it off the deepest route instead made deep
  concepts doubly punishing — long routes *and* a QB frozen in place — and gave
  the coach no way to trade depth for protection.
- **The defense gets no pre-snap tell** about run vs pass. Linebackers only crash
  downhill after the handoff, on a reaction timer set by their Intelligence.
- **Blocking is assigned centrally**, one blocker per rusher, so linemen never
  double-team while somebody else runs free.
- **A blocked defender cannot make a tackle** unless the runner comes right to him.
- **A shed block only frees the rusher for `FREE_RUSH_TIME` (0.15s), not the
  beaten blocker.** `shed_cooldown` (1.0s) keeps the specific lineman who
  lost the rep out of the rotation, but a different, already-idle blocker
  can step in almost immediately. These used to be ~0.8s and ~1.6s, which -
  combined with every blocker's first shed roll landing on the exact same
  instant (`FIRST_CONTACT` is now jittered per-blocker in `_align_offense`
  to stop that) - meant a spare lineman with nothing to do still couldn't
  help for most of a second, and a rusher covered most of the way to the QB
  risk-free on a single shed. `_block_logic` also aims at a predicted lead
  point on its mark now (same trick `_pursue_logic` uses for the ball
  carrier), not his raw current position, so a blocker arriving late to
  help has an actual shot at cutting him off instead of perpetually
  trailing a moving target.
- Opponent possessions are resolved abstractly (`sim_opponent_drive`) rather than
  simulated, keeping every visible snap one the player called.
- **Pursuit solves for an interception point** rather than running at where the
  carrier currently is. With a short lead cap, a defender trailing an equally
  fast runner can never close, and every broken tackle turns into a touchdown.
- **The match screen is the field.** No sub-menus during a game: the chalkboard
  is a strip along the bottom, you draw routes directly onto the field, clicking
  any player raises a card with his stats and abilities, and the card's
  substitute action slides a bench list in from the right. Subs are allowed
  before the snap and between drives.
- **Only the ball carrier can go out of bounds.** Every other offensive and
  defensive player is clamped to the field each frame (`MatchSim._clamp_inbounds`),
  and a pass that lands out of bounds is incomplete regardless of where the
  receiver is standing - closes a bug where routes could drift past the
  sideline and still register a catch.
- **Jersey numbers follow real NFL numbering bands** (`Generator.NUMBER_BANDS` /
  `DEFENSE_NUMBER_BANDS`), keyed by position for the roster and by role for
  procedurally generated defenses.
- **Hardcoded player prices scale by rarity tier, not stat total** — see
  `Generator.TIER_BASE_PRICE`. A single All Star is priced to eat most of
  what one win pays out; buying the whole draft board in one sitting isn't
  supposed to be possible.
- **A loss costs a life, not the run** (`GameState.MAX_LOSSES`, `losses`).
  `round_index` only ever advances on a win, so a loss just retries the same
  opponent; the run only truly ends once `losses` reaches 3 or you win the
  Championship. `post_match.gd` has three outcomes, not two: win-and-continue,
  lost-but-still-alive (retry), and run-over (season over or champion).
- **Catch chance gets a distance bonus, never a penalty.** A short throw -
  a checkdown, a screen, anything within about 7 yards - is close to
  automatic regardless of the receiver's Dexterity (`MatchSim._resolve_catch`).
  The bonus fades to exactly 0 by 7 yards and stays there; normal-to-deep
  routes are untouched, since completion rates were already balanced around
  those and QB accuracy already makes long throws harder on its own.
- **Defenses get tougher with every match played, not just every round -
  and with how strong your own roster actually is.**
  `GameState.current_match_quality()` adds `MATCH_QUALITY_STEP` (0.15) per
  match already played this run - wins and retried losses alike - on top of
  the round's base quality, and both the actual defenders (`Generator.make_defense`)
  and the pre-kickoff difficulty rating in the hub read it. Grinding out
  extra attempts at a round after a loss doesn't leave it exactly as easy
  as it was the first time. On top of that, `_difficulty_overshoot()` compares
  the round's base quality against `roster_overall()` (the 11 starters'
  average `PlayerData.overall()`) and feeds however far the roster is ahead
  of that curve into both the defenders' quality and `aura_count()` - so
  landing an All Star well ahead of schedule gets you a defense (and
  possibly more than one aura'd defender) sized to that roster, not to the
  round you happen to be on.
- **Mid-play stat gains pop up next to the player** (`SimPlayer.pending_stat_gains`,
  `field_view.gd`'s `_advance_pops`/`_draw_stat_pops`). An ability that changes a
  stat *during* a live play - `MatchSim._set_carrier` on a handoff/catch,
  `_step_contacts`' dodge penalty - queues one raw stat-name entry per point
  onto the player instead of applying the whole delta as a single number.
  The renderer drains that queue at a steady pace (independent of
  simulation sub-stepping, since it runs on real frame-delta) so +6
  Strength plays as six quick "+ STR" pops rather than one. A passer's
  on-target bonus (e.g. "trusted_target_wr") is applied in `_resolve_catch`,
  not `_throw` - it has to land when the ball actually reaches the
  receiver, not the instant it leaves the QB's hand, and only if the throw
  was even catchable. Presnap `snap` hooks aren't wired into this - they resolve before the play
  is even visible, so there's no live moment to pop them up over.
- **An undrawn receiver gets a random stock route, not a block.** Leaving a flex
  blank is a choice with a cost (unpredictable, possibly the wrong shape), not a
  dead player — and the reroll happens every snap, so the defense can never
  settle on what an undrawn man will do. The pick comes off `MatchSim.rng` rather
  than `Array.pick_random`, which reads Godot's own global random state and would
  break the seeded determinism the tuning harnesses rely on.
- **The budget is flat, not stat-scaled.** Every flex gets the same 30 yards, so
  route design is about shape and spacing rather than about which of your
  receivers can afford to run deep. Stats still decide whether he wins the rep.

## Deploying (Web build)

The game ships to the web as a static export - Vercel has no Godot to run, so
the HTML5/WASM build in `web_build/` is produced locally and committed as-is;
`vercel.json` just points Vercel at that folder (`outputDirectory`), no build
step. The project's renderer is set to GL Compatibility
(`project.godot`'s `renderer/rendering_method`) since Forward+ isn't supported
on the web export target.

To re-export after a change, from the project root:

```
godot --headless --export-release "Web" web_build/index.html
```

(needs the Web export templates for the matching Godot version installed).
The export preset lives in `export_presets.cfg` with threading disabled, so
the build doesn't need the `Cross-Origin-Opener-Policy`/
`Cross-Origin-Embedder-Policy` headers a threaded export would require.
Commit the regenerated `web_build/` and push - Vercel redeploys on push to
`main` once the repo is imported as a project there.
