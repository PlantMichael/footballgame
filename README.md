# Gridiron Run

A 2D football roguelike in Godot 4.3. You coach the offense of one team through a
five-round bracket. Every match is 4-5 drives; you set the lineup, hand out items,
pick five plays, and call one every snap. The play then simulates in real time on
the field. Football bucks earned on the field buy plays, players, and items between
rounds. Lose once and the run is over.

## Running

Open the folder in Godot 4.3 and press play, or:

```
godot --path . 
```

## Layout

```
scripts/
  data/        player_data, ability_db, item_db, play_db, generator
  core/        game_state.gd  (autoload: roster, lineup, playbook, bucks, bracket, shop)
  sim/         sim_player.gd, match_sim.gd  (the play simulation)
  ui/          ui_kit, field_view, play_diagram, and one script per screen
scenes/        one .tscn per screen; each is a bare Control that its script fills in
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
ends up behind the play menu.

Players are drawn from above as a slim upright capsule with the jersey number
printed on it and a head circle at the top. They **always stand upright** and
never lean into the direction they are running. Three bits of motion sit on top
of that, all in `_draw_person`:

- a **walk bob**, a side-to-side waddle plus a bounce, driven by
  `SimPlayer.stride`, which advances with distance actually covered rather
  than with wall time
- a **topple** when a player is tackled: `SimPlayer.downed` counts up and the
  body rotates from upright toward the way he was running, stretches out along
  it, the head slides to the far end, the number fades, and the shape darkens.
  Being tackled is the only thing that ever rotates a body.
- a **pre-snap shift**: changing the play call sets `target_pos` rather than
  teleporting, and `MatchSim.presnap_step` walks everyone onto their new spots

Sprites can drop in later by replacing `_draw_person`; nothing else touches
player rendering.

Each play runs: formation from `PlayDB` -> snap -> per-frame updates for offense,
defense, ball, and contact -> a result dictionary with yards, a description, and
football bucks earned.

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
ability; 15 is the ceiling. Everything else is calibrated to that: bracket
opponents start at quality 2.8 and climb 0.7 per round, while the shop's draft
board starts at 4.5 and climbs 1.3, so signing upgrades is how you keep pace.

## Test and tuning harnesses

These run headless and print results; none of them are shipped game content.

```
godot --headless --path . res://tools/sim_test.tscn   # balance stats per bracket round
godot --headless --path . res://tools/sweep.tscn      # win rate vs roster quality
godot --headless --path . res://tools/trace.tscn      # step-by-step trace of one play
godot --path . res://tools/uiflow.tscn                # end-to-end match through the UI
godot --path . res://tools/uishot.tscn                # PNG of every screen (needs a GPU)
```

`sim_test` is the one to watch when changing the sim. Current numbers, against a
roster assumed to improve by +0.55 quality per round:

| Round | Win rate | Score | Yds/play | Yds/rush | Comp % | Sack % | Plays/drive |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Wild Card | 58% | 11-5 | 5.4 | 2.0 | 48% | 1% | 7.8 |
| Divisional | 33% | 6-5 | 4.2 | 2.2 | 44% | 7% | 8.6 |
| Conference | 17% | 7-13 | 3.7 | 1.0 | 42% | 8% | 8.3 |
| Semifinal | 0% | 1-13 | 0.8 | -0.8 | 35% | 34% | 5.8 |
| Championship | 0% | 1-15 | 1.5 | 0.4 | 34% | 27% | 6.0 |

Those runs model a roster improving only +0.55 quality per round against a
bracket that climbs +0.7, so by the Semifinal the harness team is a full step
behind and the offence caves in — sack rate is the tell. The first three rows
are the calibrated ones. **Late-round balance is the known weak spot**: the
sim punishes falling behind very steeply, and how steep it should be depends on
how much a real player can actually upgrade per round.

The sim is very sensitive near parity (see `sweep`): about +1.0 quality over the
defense wins comfortably, an even matchup wins roughly 40%.

## Notable design decisions

- **The defense gets no pre-snap tell** about run vs pass. Linebackers only crash
  downhill after the handoff, on a reaction timer set by their Intelligence.
- **Blocking is assigned centrally**, one blocker per rusher, so linemen never
  double-team while somebody else runs free.
- **A blocked defender cannot make a tackle** unless the runner comes right to him.
- Opponent possessions are resolved abstractly (`sim_opponent_drive`) rather than
  simulated, keeping every visible snap one the player called.
- **Pursuit solves for an interception point** rather than running at where the
  carrier currently is. With a short lead cap, a defender trailing an equally
  fast runner can never close, and every broken tackle turns into a touchdown.
- **The match screen is the field.** No sub-menus during a game: the play menu
  is a strip along the bottom, clicking any player raises a card with his stats
  and abilities, and the card's substitute action slides a bench list in from
  the right. Subs are allowed before the snap and between drives.
