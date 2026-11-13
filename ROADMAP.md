# Gridiron development roadmap

Updated November 13, 2026. This records the agreed development order so the plan
is available from any checkout. Priorities 1 and 2 are implemented; priority 3
is next. Future content counts and event rules below are proposals to tune during
development, rather than features already in the game.

## Priorities

| Priority | Status | Work and intended result |
|---|---|---|
| 1 | Complete | **Branding and loading.** Rename the game and repository to Gridiron, add the turf loading bar and animated player, and prepare the players and sidelines before revealing a match. Preserve existing QB/bowl completion records. |
| 2 | Complete | **Lineup and shop clarity.** Show the selected starter, eligible replacements and stat comparisons. Use explicit Start, Swap, Equip and Unequip actions. Explain purchase destinations, lab costs, and ritual player losses before confirmation. |
| 3 | Next | **Remove touchdown buffs and add drive events.** Remove post-touchdown stat-buff choices while retaining scoring and football-buck rewards. Give every offensive drive a chance of an event, with a higher chance deeper into the run. Balance this before adding more items and bowl effects. |
| 4 | Planned | **Run, match and result presentation.** Introduce the team and QB at run start, show a team-versus-team match splash, clarify win/loss/tie results, and add subtle menu animation. Make repeated introductions skippable. |
| 5 | Planned | **Head variety.** Add hair and facial-hair styles. Check all facings, portraits, skin-matched hands and collars, including sideline NPCs. Suggested first batch: 8–12 generic styles. |
| 6 | Planned | **Items and recognizable sets.** Explain set membership, equipped-piece progress and active bonuses before purchase or equipping. Define set bonuses before expanding the item pool; suggested first batch: three sets of three pieces. |
| 7 | Planned | **More Oddity and Cursed players.** Add distinct abilities that complement existing builds and explain their strengths and drawbacks during acquisition. Keep Cursed names demon-themed. Suggested first batch: three of each. |
| 8 | Planned | **Complete bowl identities.** Add unique players or gimmicks to the four bowls without special defenders, then review the existing Pro Bowl and Toilet Bowl effects. Explain every gimmick and provide meaningful counterplay. |

## Next milestone: touchdown rewards and drive events

The requested change is to remove touchdown stat-buff choices and let random
events occur on any offensive drive, becoming more likely as the run progresses.
Touchdowns still score points and award football bucks.

The initial event rules proposed in the plan are:

- Roll once at the start of each offensive drive, including the opening drive.
- Increase the event chance with run depth; choose the curve and cap through playtesting.
- Start with at most one event per drive.
- Announce the effect before the snap and explain its duration.
- Clear drive-specific effects before rolling the next event.
- Include beneficial and disruptive events, then rebalance complete runs.

| Event | Proposed behavior |
|---|---|
| Oil spill | Clearly marked slippery patches affect footing. |
| Fans throwing bottles | Telegraphed throws show landing zones and give players time to react. |
| Extra defender | Add one defender for the drive and remove him afterward. |
| Aura farm | Buff the team with an aura whose effect and duration are visible. |

Exact odds, buff strengths and hazard behavior remain balance decisions for this
milestone. Removing touchdown buffs changes the power curve, so item and bowl
balancing follows the event system.

## Completed foundation

Priority 1 preserves the original `Gridiron Run` save namespace and existing
completion records. Browser progress remains tied to the existing site address.
In-progress runs are not saved.

Priority 2 includes the formation/inspector layout, base-stat comparisons,
explicit roster and gear actions, shop Players/Gear tabs, purchase placement,
lab balance information and a named-loss ritual confirmation. Existing prices
and roster rules remain in place, including automatic release of a displaced
placeholder rookie and automatic starting placement of the first kicker.

The priority 2 build passed 47 real-screen roster checks, navigation checks,
keyboard confirmation/focus checks and rendered layout inspection at two window
sizes. See [README.md](README.md) for the game instructions and verification routes.

## Longer-term achievements

Build on the saved QB/bowl completion marks for the proposed **30 achievements**:
five QBs × six bowls, unlocking **15 players and 15 items**. This remains
longer-term work after the playable milestones above.

## Release direction

The recommended next playable milestone is priorities **1–4**, followed by
content in small batches and complete-run balance testing. Sound remains a
separate follow-up the developer intends to handle later. Steam onboarding and
store preparation are separate from this game-development sequence; this
roadmap does not promise a Steam release date.
