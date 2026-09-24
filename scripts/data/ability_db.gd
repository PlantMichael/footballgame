class_name AbilityDB
extends RefCounted

## Special abilities. Every player has exactly one.
##
## Each ability is a name/desc pair plus whichever hook methods it actually
## needs, wired up as Callables rather than dispatched through one big match
## statement per hook. To add an ability: write a `_snap_<id>`, `_catch_<id>`,
## `_contact_<id>`, etc. method below for whichever hooks it uses, then add
## one entry to ABILITIES pointing at them. A hook nobody defines just falls
## through to the neutral default in that hook's getter, so an ability only
## needs the methods it actually uses.
##
## Hook signatures and where the sim calls them:
##   snap(p, ctx)        -> Dictionary of stat deltas, default {}. MatchSim._apply_modifiers.
##   catch(ctx)           -> float catch-chance modifier, default 0.0. MatchSim._resolve_catch.
##   contact(role)         -> float contact-roll modifier, default 0.0. MatchSim._contact_roll / _tackle.
##   fatigue_floor()       -> float speed floor when gassed, default 0.65.
##   speed_cap()           -> int hard ceiling on effective Agility, default 99.
##   guarantees_catch()    -> bool, default false.
##   disrupted_mult()      -> float multiplier on coverage-jam recovery time, default 1.0.
##   dashes_at_snap()      -> bool, default false. MatchSim.snap().
##   passer_dex_bonus(pos) -> int Dexterity granted to a target of this position when this
##                            player throws to him, default 0. MatchSim._throw. `pos` is a
##                            PlayerData.Pos.
##   fake_chance()         -> float chance [0-1] per defender of reacting late to a handoff
##                            to this carrier, as if the QB still had the ball, default 0.0.
##                            MatchSim._do_handoff.
##   on_carry_bonus()      -> Dictionary of stat deltas granted the instant this player
##                            becomes the ball carrier (handoff or catch), default {}.
##                            MatchSim._set_carrier.
##   dodges_once()         -> bool, default false. Once per play, the carrier auto-evades
##                            the first tackle attempt against him for free, then eats a
##                            flat -5 Agility for the rest of the play. MatchSim._step_contacts.
##   catches_drops()       -> bool, default false. If a teammate would drop a catchable
##                            pass, this player swaps in and catches it himself instead.
##                            MatchSim._resolve_catch.
##   locks_dl_at_snap()    -> bool, default false. The instant the ball is snapped, this
##                            blocker claims the closest defensive lineman as his block
##                            assignment instead of waiting for the normal per-frame
##                            assignment pass. MatchSim.snap.
##   team_buff()           -> Dictionary {"pos": PlayerData.Pos, "stat": String, "amount":
##                            int}, default {}. Every teammate of that position gets the
##                            stat bonus for the play, not just the ability holder.
##                            MatchSim._apply_team_buffs.
##   evades_man_coverage()  -> bool, default false. No defender is ever assigned to man
##                            him up at the snap (a zone defender can still end up near
##                            him incidentally). MatchSim._align_defense.
##   distracts_defenders()  -> bool, default false. The 2 defenders nearest his alignment
##                            at the snap take a flat -1 Intelligence for the play.
##                            MatchSim._apply_distraction.
##   taunts_defenders()    -> bool, default false. The 2 defenders nearest his alignment
##                            at the snap take a flat -2 Strength for the play, chasing him
##                            instead of squaring up the real tackle. MatchSim._apply_taunt.
##   cloak_seconds()        -> float, default 0.0. His man defender ignores him entirely for
##                            this many seconds after the snap before starting to cover him.
##                            MatchSim._man_logic.
##   counts_as_positions()  -> Array[PlayerData.Pos], default []. Non-empty replaces this
##                            player's position for every personnel-count/team-buff/
##                            out-of-position check this play - MatchSim._effective_positions
##                            (used by _snap_context, _apply_team_buffs, _out_of_position_penalty).
##   dedicated_blocker()    -> bool, default false. Always blocks regardless of what's drawn
##                            for him (never runs a route or takes a handoff, so the QB never
##                            considers him a target), locked for the whole play onto the
##                            single highest-Strength non-lineman defender rather than
##                            whichever rusher the normal per-frame assignment would give him.
##                            MatchSim._align_offense / _assign_blocks / _pick_dedicated_target.
##   right_side_buff()      -> Dictionary {"stat": String, "amount": int, "count": int},
##                            default {}. The `count` flex players aligned furthest to the
##                            formation's right get the stat bonus, not just the ability
##                            holder (who is usually a lineman, not a flex, himself).
##                            MatchSim._apply_alignment_buffs.
##   tier_buff()            -> Dictionary {"qualities": Array[int] (ShopPlayerDB.QUALITY_*),
##                            "amount": int}, default {}. Every teammate whose shop rarity
##                            tier is in `qualities` gets +amount to every stat - generated
##                            (non-shop) players have quality 0 and never match.
##                            MatchSim._apply_tier_buffs.
##   pushes_defense_at_snap() -> float, default 0.0. The whole defense lines up this many
##                            extra yards back from the LOS at the snap. MatchSim._align_defense.
##   max_agility_on_catch() -> bool, default false. Effective Agility jumps straight to 15
##                            the instant he catches a pass. MatchSim._resolve_catch.
##   explodes_after_seconds() -> float, default 0.0. Holding the ball this many seconds as
##                            carrier ends the play immediately as a turnover, with a big
##                            screen-shake. MatchSim._step_offense / SimPlayer.carry_seconds.
##   route_budget_mult()    -> float, default 1.0. Multiplies RouteBook.BUDGET_YARDS while
##                            the coach is drawing for this player. field_view.gd's
##                            _extend_stroke/_draw_stroke.
##   curses_nearest_defender() -> bool, default false. At the snap, the defender nearest
##                            this player's own alignment spot switches sides for the play -
##                            see SimPlayer.turned, MatchSim._align_defense/_turned_logic.
##   earthquake_on_catch()  -> bool, default false. The instant he catches a pass, every
##                            other player on the field is stunned for 1 second and the
##                            screen does one big multi-directional shake.
##                            MatchSim._resolve_catch.
##
## `ctx` for snap: wr_count, te_count, rb_count, down, to_go, yards_to_endzone,
## score_diff, is_run_play, is_blitzed, is_bowl_game. `ctx` for catch:
## nearest_defender_dist, would_be_first_down, target_is_deep. `role` for
## contact is "carry", "block", or "cover".

const ABILITIES := {
	"corps_of_three": {
		"name": "Corps of Three",
		"desc": "+3 Agility if there are 2 other wide receivers on the field.",
		"snap": Callable(AbilityDB, "_snap_corps_of_three"),
	},
	"iron_anchor": {
		"name": "Iron Anchor",
		"desc": "+4 Strength on 3rd or 4th down.",
		"snap": Callable(AbilityDB, "_snap_iron_anchor"),
	},
	"sure_hands": {
		"name": "Sure Hands",
		"desc": "+8% catch chance on any throw.",
		"catch": Callable(AbilityDB, "_catch_sure_hands"),
	},
	"contested_king": {
		"name": "Contested King",
		"desc": "+18% catch chance when a defender is within 2 yards.",
		"catch": Callable(AbilityDB, "_catch_contested_king"),
	},
	"deep_threat": {
		"name": "Deep Threat",
		"desc": "+2 Agility and +10% catch chance on throws 20+ yards downfield.",
		"snap": Callable(AbilityDB, "_snap_deep_threat"),
		"catch": Callable(AbilityDB, "_catch_deep_threat"),
	},
	"red_zone_beast": {
		"name": "Red Zone Beast",
		"desc": "+3 Strength and +3 Dexterity inside the 20.",
		"snap": Callable(AbilityDB, "_snap_red_zone_beast"),
	},
	"bulldozer": {
		"name": "Bulldozer",
		"desc": "+20% to win contact rolls while carrying the ball.",
		"contact": Callable(AbilityDB, "_contact_bulldozer"),
	},
	"immovable": {
		"name": "Immovable",
		"desc": "+25% to win contact rolls while blocking.",
		"contact": Callable(AbilityDB, "_contact_immovable"),
	},
	"film_study": {
		"name": "Film Study",
		"desc": "+4 Intelligence if 2 or more tight ends are on the field.",
		"snap": Callable(AbilityDB, "_snap_film_study"),
	},
	"gunslinger": {
		"name": "Gunslinger",
		"desc": "+3 Dexterity, -2 Intelligence. Throws harder and sooner.",
		"snap": Callable(AbilityDB, "_snap_gunslinger"),
	},
	"field_general": {
		"name": "Field General",
		"desc": "+3 Intelligence when trailing.",
		"snap": Callable(AbilityDB, "_snap_field_general"),
	},
	"second_wind": {
		"name": "Second Wind",
		"desc": "+4 Stamina, and +2 Agility on 3rd down or later.",
		"snap": Callable(AbilityDB, "_snap_second_wind"),
	},
	"scat_back": {
		"name": "Scat Back",
		"desc": "+4 Agility if no other running backs are on the field.",
		"snap": Callable(AbilityDB, "_snap_scat_back"),
	},
	"possession_man": {
		"name": "Possession Man",
		"desc": "+12% catch chance when the throw gains a first down.",
		"catch": Callable(AbilityDB, "_catch_possession_man"),
	},
	"blindside_wall": {
		"name": "Blindside Wall",
		"desc": "+3 Strength and +2 Intelligence while pass blocking.",
		"snap": Callable(AbilityDB, "_snap_blindside_wall"),
	},
	"escape_artist": {
		"name": "Escape Artist",
		"desc": "+15% to break tackles, +1 Agility.",
		"snap": Callable(AbilityDB, "_snap_escape_artist"),
		"contact": Callable(AbilityDB, "_contact_escape_artist"),
	},
	"chain_mover": {
		"name": "Chain Mover",
		"desc": "+3 Strength and +2 Agility when 3 yards or fewer to go.",
		"snap": Callable(AbilityDB, "_snap_chain_mover"),
	},
	"route_technician": {
		"name": "Route Technician",
		"desc": "+5 Intelligence, -1 Strength. Runs routes crisply.",
		"snap": Callable(AbilityDB, "_snap_route_technician"),
	},
	"workhorse": {
		"name": "Workhorse",
		"desc": "+5 Stamina. Never slows below 85% speed.",
		"snap": Callable(AbilityDB, "_snap_workhorse"),
		"fatigue_floor": Callable(AbilityDB, "_fatigue_floor_workhorse"),
	},
	"clutch_gene": {
		"name": "Clutch Gene",
		"desc": "+2 to every stat on 4th down.",
		"snap": Callable(AbilityDB, "_snap_clutch_gene"),
	},
	"spread_specialist": {
		"name": "Spread Specialist",
		"desc": "+3 Dexterity if 3 or more wide receivers are on the field.",
		"snap": Callable(AbilityDB, "_snap_spread_specialist"),
	},
	"goal_line_back": {
		"name": "Goal Line Back",
		"desc": "+5 Strength inside the 5 yard line.",
		"snap": Callable(AbilityDB, "_snap_goal_line_back"),
	},
	"dash_start": {
		"name": "Track Start",
		"desc": "Dashes forward 5 yards the instant the ball is snapped.",
		"dashes_at_snap": Callable(AbilityDB, "_dashes_at_snap_dash_start"),
	},
	"cant_miss": {
		"name": "Can't Miss",
		"desc": "Never drops a catchable ball, but top speed is capped as if Agility were 4.",
		"speed_cap": Callable(AbilityDB, "_speed_cap_cant_miss"),
		"guarantees_catch": Callable(AbilityDB, "_guarantees_catch_cant_miss"),
	},
	"quick_recovery": {
		"name": "Quick Recovery",
		"desc": "Shakes off a jam and is back to full speed 80% faster than normal.",
		"disrupted_mult": Callable(AbilityDB, "_disrupted_mult_quick_recovery"),
	},
	"trusted_target_wr": {
		"name": "Trusted Target (WR)",
		"desc": "+4 Dexterity to any wide receiver he throws to.",
		"passer_dex_bonus": Callable(AbilityDB, "_passer_dex_bonus_trusted_target_wr"),
	},
	"trusted_target_te": {
		"name": "Trusted Target (TE)",
		"desc": "+4 Dexterity to any tight end he throws to.",
		"passer_dex_bonus": Callable(AbilityDB, "_passer_dex_bonus_trusted_target_te"),
	},
	"misdirection": {
		"name": "Misdirection",
		"desc": "50% chance to fool each defender into reacting late on a handoff, as if the QB still had the ball.",
		"fake_chance": Callable(AbilityDB, "_fake_chance_misdirection"),
	},
	"power_surge": {
		"name": "Power Surge",
		"desc": "+6 Strength the instant he gets the ball.",
		"on_carry_bonus": Callable(AbilityDB, "_on_carry_bonus_power_surge"),
	},
	"phantom_step": {
		"name": "Phantom Step",
		"desc": "Once per play, dashes clean through a tackle attempt for free - but it costs him 5 Agility for the rest of the play.",
		"dodges_once": Callable(AbilityDB, "_dodges_once_phantom_step"),
	},
	"guardian_angel": {
		"name": "Guardian Angel",
		"desc": "If a teammate would drop a catchable pass, swaps in and hauls it in himself instead.",
		"catches_drops": Callable(AbilityDB, "_catches_drops_guardian_angel"),
	},
	"lockdown_block": {
		"name": "Lockdown Block",
		"desc": "At the snap, immediately locks onto the closest defensive lineman instead of waiting to be assigned one.",
		"locks_dl_at_snap": Callable(AbilityDB, "_locks_dl_at_snap_lockdown_block"),
	},
	"field_command": {
		"name": "Field Command",
		"desc": "+2 Intelligence to every tight end on the field.",
		"team_buff": Callable(AbilityDB, "_team_buff_field_command"),
	},
	"spacing_coach": {
		"name": "Spacing Coach",
		"desc": "+2 Agility to every wide receiver on the field.",
		"team_buff": Callable(AbilityDB, "_team_buff_spacing_coach"),
	},
	"power_scheme": {
		"name": "Power Scheme",
		"desc": "+2 Strength to every running back on the field.",
		"team_buff": Callable(AbilityDB, "_team_buff_power_scheme"),
	},
	"line_captain": {
		"name": "Line Captain",
		"desc": "+2 Strength to every Tackle on the field.",
		"team_buff": Callable(AbilityDB, "_team_buff_line_captain"),
	},
	"qb_whisperer": {
		"name": "QB Whisperer",
		"desc": "+3 Intelligence to his quarterback.",
		"team_buff": Callable(AbilityDB, "_team_buff_qb_whisperer"),
	},
	"attention_hog": {
		"name": "Attention Hog",
		"desc": "The 2 defenders nearest him at the snap take -1 Intelligence for the play, distracted trying to account for him.",
		"distracts_defenders": Callable(AbilityDB, "_distracts_defenders_attention_hog"),
	},
	"ghost_route": {
		"name": "Ghost Route",
		"desc": "No defender is ever assigned to cover him man-to-man.",
		"evades_man_coverage": Callable(AbilityDB, "_evades_man_coverage_ghost_route"),
	},
	"down_and_distance": {
		"name": "Down and Distance",
		"desc": "+2 Agility for each down past 1st, up to +6 on 4th.",
		"snap": Callable(AbilityDB, "_snap_down_and_distance"),
	},
	"pressure_reader": {
		"name": "Pressure Reader",
		"desc": "+2 Dexterity on plays where the defense sends a blitz.",
		"snap": Callable(AbilityDB, "_snap_pressure_reader"),
	},
	"instant_burst": {
		"name": "Instant Burst",
		"desc": "+4 Agility the instant he takes the ball, handoff or catch.",
		"on_carry_bonus": Callable(AbilityDB, "_on_carry_bonus_instant_burst"),
	},
	"cloaked_route": {
		"name": "Cloaked Route",
		"desc": "For the first 2 seconds of the play, his man defender doesn't react to him at all.",
		"cloak_seconds": Callable(AbilityDB, "_cloak_seconds_cloaked_route"),
	},
	"decoy": {
		"name": "Decoy",
		"desc": "The 2 defenders nearest him at the snap take a flat -2 Strength for the play, taunted into keying on him instead of squaring up the real tackle.",
		"taunts_defenders": Callable(AbilityDB, "_taunts_defenders_decoy"),
	},
	"positionless": {
		"name": "Positionless",
		"desc": "Counts as an RB, TE, and WR at once for every personnel-based effect on the field.",
		"counts_as_positions": Callable(AbilityDB, "_counts_as_positions_positionless"),
	},
	"bowl_jitters": {
		"name": "Bowl Jitters",
		"desc": "+3 to every stat - except in a bowl game, where the moment gets to him.",
		"snap": Callable(AbilityDB, "_snap_bowl_jitters"),
	},
	"enforcer": {
		"name": "Enforcer",
		"desc": "Never runs a route or takes a handoff. Locks onto the strongest non-lineman defender all game and blocks him alone.",
		"dedicated_blocker": Callable(AbilityDB, "_dedicated_blocker_enforcer"),
	},
	"right_side_coach": {
		"name": "Right Side Coach",
		"desc": "The 2 flex players aligned furthest right get +2 Dexterity.",
		"right_side_buff": Callable(AbilityDB, "_right_side_buff_right_side_coach"),
	},
	"tackle_pride": {
		"name": "Tackle Pride",
		"desc": "+1 Strength to every other Tackle on the field.",
		"team_buff": Callable(AbilityDB, "_team_buff_tackle_pride"),
	},
	"veteran_mentor": {
		"name": "Veteran Mentor",
		"desc": "+1 to every stat for every Rookie or Sophomore-tier signed player on the field.",
		"tier_buff": Callable(AbilityDB, "_tier_buff_veteran_mentor"),
	},
	"drive_block": {
		"name": "Drive Block",
		"desc": "At the snap, the whole defense lines up 5 extra yards off the ball.",
		"pushes_defense_at_snap": Callable(AbilityDB, "_pushes_defense_at_snap_drive_block"),
	},
	"combustion": {
		"name": "Combustion",
		"desc": "When catching the ball, gains max Agility - but explodes 3 seconds later, ending the play.",
		"max_agility_on_catch": Callable(AbilityDB, "_max_agility_on_catch_combustion"),
		"explodes_after_seconds": Callable(AbilityDB, "_explodes_after_seconds_combustion"),
	},
	"boundless": {
		"name": "Boundless",
		"desc": "His route limit is quadrupled.",
		"route_budget_mult": Callable(AbilityDB, "_route_budget_mult_boundless"),
	},
	"corruption": {
		"name": "Corruption",
		"desc": "At the snap, curses the nearest defender - he blocks for your team instead of his own for the rest of the play.",
		"curses_nearest_defender": Callable(AbilityDB, "_curses_nearest_defender_corruption"),
	},
	"aftershock": {
		"name": "Aftershock",
		"desc": "When receiving the ball, triggers an earthquake that stuns every other player on the field for 1 second.",
		"earthquake_on_catch": Callable(AbilityDB, "_earthquake_on_catch_aftershock"),
	},
}


static func get_ability(id: String) -> Dictionary:
	return ABILITIES.get(id, {})


static func ability_name(id: String) -> String:
	var a: Dictionary = ABILITIES.get(id, {})
	return a.get("name", "-")


static func ability_desc(id: String) -> String:
	var a: Dictionary = ABILITIES.get(id, {})
	return a.get("desc", "No special ability.")


static func all_ids() -> Array:
	return ABILITIES.keys()


# ============================================================================
# Hook dispatch - one Callable lookup per call, nothing to edit as the
# ability list grows.
# ============================================================================

static func _dispatch(id: String, hook: String, args: Array, default: Variant) -> Variant:
	if id == "":
		return default
	var entry: Dictionary = ABILITIES.get(id, {})
	var fn: Callable = entry.get(hook, Callable())
	if not fn.is_valid():
		return default
	return fn.callv(args)


## Stat deltas granted at the snap. Returns {stat_key: int}.
static func snap_bonus(id: String, p: PlayerData, ctx: Dictionary) -> Dictionary:
	return _dispatch(id, "snap", [p, ctx], {})


## Additive modifier to catch probability (0.0-1.0 scale).
static func catch_mod(id: String, ctx: Dictionary) -> float:
	return _dispatch(id, "catch", [ctx], 0.0)


## Additive modifier to a contact/push-off roll (0.0-1.0 scale).
## `role` is "carry", "block", or "cover".
static func contact_mod(id: String, role: String) -> float:
	return _dispatch(id, "contact", [role], 0.0)


## Floor on speed loss from fatigue, as a fraction of max speed.
static func fatigue_floor(id: String) -> float:
	return _dispatch(id, "fatigue_floor", [], 0.65)


## Hard ceiling on effective Agility (and therefore top speed), for abilities
## that trade speed for a guaranteed skill elsewhere. 99 means no cap.
static func speed_cap(id: String) -> int:
	return _dispatch(id, "speed_cap", [], 99)


## True if this player never drops a catchable ball (still needs a catchable
## throw; wildly off-target passes are unaffected).
static func guarantees_catch(id: String) -> bool:
	return _dispatch(id, "guarantees_catch", [], false)


## Multiplier on how long a receiver stays knocked off his route after a
## coverage jam. Below 1.0 means he gets back up to speed faster.
static func disrupted_mult(id: String) -> float:
	return _dispatch(id, "disrupted_mult", [], 1.0)


## True for abilities that move the player forward the instant the ball is
## snapped, handled directly by MatchSim.snap().
static func dashes_at_snap(id: String) -> bool:
	return _dispatch(id, "dashes_at_snap", [], false)


## Dexterity granted to a target of `target_pos` when the passer with this
## ability throws to him. `id` is the passer's ability, not the target's.
static func passer_dex_bonus(id: String, target_pos: PlayerData.Pos) -> int:
	return _dispatch(id, "passer_dex_bonus", [target_pos], 0)


## Chance [0-1] that a given defender reacts late to a handoff to this
## carrier, as if the QB still had the ball.
static func fake_chance(id: String) -> float:
	return _dispatch(id, "fake_chance", [], 0.0)


## Stat deltas granted the instant this player becomes the ball carrier.
static func on_carry_bonus(id: String) -> Dictionary:
	return _dispatch(id, "on_carry_bonus", [], {})


## True for abilities that let the carrier auto-evade one tackle attempt
## per play for free.
static func dodges_once(id: String) -> bool:
	return _dispatch(id, "dodges_once", [], false)


## True if this player swaps in and catches the ball himself whenever a
## teammate would drop a catchable pass.
static func catches_drops(id: String) -> bool:
	return _dispatch(id, "catches_drops", [], false)


## True if this blocker claims the closest defensive lineman the instant
## the ball is snapped, rather than waiting for the normal assignment pass.
static func locks_dl_at_snap(id: String) -> bool:
	return _dispatch(id, "locks_dl_at_snap", [], false)


## {"pos": PlayerData.Pos, "stat": String, "amount": int} buff applied to
## every teammate at that position, not just the ability holder. {} if this
## ability doesn't buff the team.
static func team_buff(id: String) -> Dictionary:
	return _dispatch(id, "team_buff", [], {})


## True if no defender should ever be assigned to man-cover this player.
static func evades_man_coverage(id: String) -> bool:
	return _dispatch(id, "evades_man_coverage", [], false)


## True if this player pulls the 2 nearest defenders' focus at the snap.
static func distracts_defenders(id: String) -> bool:
	return _dispatch(id, "distracts_defenders", [], false)


## True if this player taunts the 2 nearest defenders into a Strength
## penalty for the play, chasing him instead of squaring up the tackle.
static func taunts_defenders(id: String) -> bool:
	return _dispatch(id, "taunts_defenders", [], false)


## Seconds after the snap during which this player's man defender ignores
## him entirely. 0.0 means no cloak.
static func cloak_seconds(id: String) -> float:
	return _dispatch(id, "cloak_seconds", [], 0.0)


## Positions this player counts as instead of his real one, for every
## personnel-based check this play. [] means just use his real position.
static func counts_as_positions(id: String) -> Array:
	return _dispatch(id, "counts_as_positions", [], [])


## True if this player always blocks - never a route/handoff target -
## locked for the whole play onto the strongest non-lineman defender.
static func dedicated_blocker(id: String) -> bool:
	return _dispatch(id, "dedicated_blocker", [], false)


## {"stat": String, "amount": int, "count": int} buff for the `count` flex
## players aligned furthest right, default {}.
static func right_side_buff(id: String) -> Dictionary:
	return _dispatch(id, "right_side_buff", [], {})


## {"qualities": Array[int], "amount": int} buff for every teammate whose
## shop rarity tier (PlayerData.quality) is in `qualities`, default {}.
static func tier_buff(id: String) -> Dictionary:
	return _dispatch(id, "tier_buff", [], {})


## Extra yards the whole defense lines up off the ball at the snap, default 0.0.
static func pushes_defense_at_snap(id: String) -> float:
	return _dispatch(id, "pushes_defense_at_snap", [], 0.0)


## True if effective Agility jumps straight to 15 the instant this player
## catches a pass.
static func max_agility_on_catch(id: String) -> bool:
	return _dispatch(id, "max_agility_on_catch", [], false)


## Seconds of holding the ball as carrier before this player's ability ends
## the play as a turnover, default 0.0 (never).
static func explodes_after_seconds(id: String) -> float:
	return _dispatch(id, "explodes_after_seconds", [], 0.0)


## Multiplier on RouteBook.BUDGET_YARDS while the coach draws for this
## player, default 1.0.
static func route_budget_mult(id: String) -> float:
	return _dispatch(id, "route_budget_mult", [], 1.0)


## True if this player curses the nearest defender to his own alignment at
## the snap, turning him into a blocker for the offense for the play.
static func curses_nearest_defender(id: String) -> bool:
	return _dispatch(id, "curses_nearest_defender", [], false)


## True if every other player on the field gets stunned for 1 second the
## instant this player catches a pass.
static func earthquake_on_catch(id: String) -> bool:
	return _dispatch(id, "earthquake_on_catch", [], false)


# ============================================================================
# Per-ability hook implementations
# ============================================================================

static func _snap_corps_of_three(p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("wr_count", 0)) - (1 if p.pos == PlayerData.Pos.WR else 0) >= 2:
		return {"agility": 3}
	return {}


static func _snap_iron_anchor(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("down", 1)) >= 3:
		return {"strength": 4}
	return {}


static func _catch_sure_hands(_ctx: Dictionary) -> float:
	return 0.08


static func _catch_contested_king(ctx: Dictionary) -> float:
	if float(ctx.get("nearest_defender_dist", 99.0)) <= 2.0:
		return 0.18
	return 0.0


static func _snap_deep_threat(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("target_is_deep", false)):
		return {"agility": 2}
	return {}


static func _catch_deep_threat(ctx: Dictionary) -> float:
	if bool(ctx.get("target_is_deep", false)):
		return 0.10
	return 0.0


static func _snap_red_zone_beast(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if float(ctx.get("yards_to_endzone", 99.0)) <= 20.0:
		return {"strength": 3, "dexterity": 3}
	return {}


static func _contact_bulldozer(role: String) -> float:
	return 0.20 if role == "carry" else 0.0


static func _contact_immovable(role: String) -> float:
	return 0.25 if role == "block" else 0.0


static func _snap_film_study(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("te_count", 0)) >= 2:
		return {"intelligence": 4}
	return {}


static func _snap_gunslinger(_p: PlayerData, _ctx: Dictionary) -> Dictionary:
	return {"dexterity": 3, "intelligence": -2}


static func _snap_field_general(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("score_diff", 0)) < 0:
		return {"intelligence": 3}
	return {}


static func _snap_second_wind(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	var out := {"stamina": 4}
	if int(ctx.get("down", 1)) >= 3:
		out["agility"] = 2
	return out


static func _snap_scat_back(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("rb_count", 0)) <= 1:
		return {"agility": 4}
	return {}


static func _catch_possession_man(ctx: Dictionary) -> float:
	if bool(ctx.get("would_be_first_down", false)):
		return 0.12
	return 0.0


static func _snap_blindside_wall(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("is_run_play", false)):
		return {"strength": 3, "intelligence": 2}
	return {}


static func _snap_escape_artist(_p: PlayerData, _ctx: Dictionary) -> Dictionary:
	return {"agility": 1}


static func _contact_escape_artist(role: String) -> float:
	return 0.15 if role == "carry" else 0.0


static func _snap_chain_mover(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if float(ctx.get("to_go", 10.0)) <= 3.0:
		return {"strength": 3, "agility": 2}
	return {}


static func _snap_route_technician(_p: PlayerData, _ctx: Dictionary) -> Dictionary:
	return {"intelligence": 5, "strength": -1}


static func _snap_workhorse(_p: PlayerData, _ctx: Dictionary) -> Dictionary:
	return {"stamina": 5}


static func _fatigue_floor_workhorse() -> float:
	return 0.85


static func _snap_clutch_gene(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("down", 1)) == 4:
		return {"strength": 2, "agility": 2, "dexterity": 2, "stamina": 2, "intelligence": 2}
	return {}


static func _snap_spread_specialist(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("wr_count", 0)) >= 3:
		return {"dexterity": 3}
	return {}


static func _snap_goal_line_back(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if float(ctx.get("yards_to_endzone", 99.0)) <= 5.0:
		return {"strength": 5}
	return {}


static func _dashes_at_snap_dash_start() -> bool:
	return true


static func _speed_cap_cant_miss() -> int:
	return 4


static func _guarantees_catch_cant_miss() -> bool:
	return true


static func _disrupted_mult_quick_recovery() -> float:
	return 0.2


static func _passer_dex_bonus_trusted_target_wr(target_pos: PlayerData.Pos) -> int:
	return 4 if target_pos == PlayerData.Pos.WR else 0


static func _passer_dex_bonus_trusted_target_te(target_pos: PlayerData.Pos) -> int:
	return 4 if target_pos == PlayerData.Pos.TE else 0


static func _fake_chance_misdirection() -> float:
	return 0.5


static func _on_carry_bonus_power_surge() -> Dictionary:
	return {"strength": 6}


static func _dodges_once_phantom_step() -> bool:
	return true


static func _catches_drops_guardian_angel() -> bool:
	return true


static func _locks_dl_at_snap_lockdown_block() -> bool:
	return true


static func _team_buff_field_command() -> Dictionary:
	return {"pos": PlayerData.Pos.TE, "stat": "intelligence", "amount": 2}


static func _team_buff_spacing_coach() -> Dictionary:
	return {"pos": PlayerData.Pos.WR, "stat": "agility", "amount": 2}


static func _team_buff_power_scheme() -> Dictionary:
	return {"pos": PlayerData.Pos.RB, "stat": "strength", "amount": 2}


static func _team_buff_line_captain() -> Dictionary:
	return {"pos": PlayerData.Pos.T, "stat": "strength", "amount": 2}


static func _team_buff_qb_whisperer() -> Dictionary:
	return {"pos": PlayerData.Pos.QB, "stat": "intelligence", "amount": 3}


static func _distracts_defenders_attention_hog() -> bool:
	return true


static func _evades_man_coverage_ghost_route() -> bool:
	return true


static func _snap_down_and_distance(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	var bonus := clampi((int(ctx.get("down", 1)) - 1) * 2, 0, 6)
	if bonus > 0:
		return {"agility": bonus}
	return {}


static func _snap_pressure_reader(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("is_blitzed", false)):
		return {"dexterity": 2}
	return {}


static func _on_carry_bonus_instant_burst() -> Dictionary:
	return {"agility": 4}


static func _cloak_seconds_cloaked_route() -> float:
	return 2.0


static func _taunts_defenders_decoy() -> bool:
	return true


static func _counts_as_positions_positionless() -> Array:
	return [PlayerData.Pos.RB, PlayerData.Pos.TE, PlayerData.Pos.WR]


static func _snap_bowl_jitters(_p: PlayerData, ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("is_bowl_game", false)):
		return {}
	return {"strength": 3, "agility": 3, "dexterity": 3, "stamina": 3, "intelligence": 3}


static func _dedicated_blocker_enforcer() -> bool:
	return true


static func _right_side_buff_right_side_coach() -> Dictionary:
	return {"stat": "dexterity", "amount": 2, "count": 2}


static func _team_buff_tackle_pride() -> Dictionary:
	return {"pos": PlayerData.Pos.T, "stat": "strength", "amount": 1}


static func _tier_buff_veteran_mentor() -> Dictionary:
	return {"qualities": [ShopPlayerDB.QUALITY_ROOKIE, ShopPlayerDB.QUALITY_SOPHOMORE], "amount": 1}


static func _pushes_defense_at_snap_drive_block() -> float:
	return 5.0


static func _max_agility_on_catch_combustion() -> bool:
	return true


static func _explodes_after_seconds_combustion() -> float:
	return 3.0


static func _route_budget_mult_boundless() -> float:
	return 4.0


static func _curses_nearest_defender_corruption() -> bool:
	return true


static func _earthquake_on_catch_aftershock() -> bool:
	return true
