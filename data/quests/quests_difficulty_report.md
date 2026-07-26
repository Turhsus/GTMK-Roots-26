# Quests by difficulty — audit

Generated 2026-07-26 from the eight `.tres` files in this folder, `data/quest_pool.tres`,
`resources/quest_data.gd` and `autoload/run_state.gd`. Values marked *(default)* are not
authored in the `.tres` — they fall out of the `@export` defaults in `quest_data.gd`.

## How difficulty actually works

`QuestData.difficulty` is an `@export_range(0, 4)` int, default **0**. It is a *bucket*,
not a curve: `RunState.current_difficulty()` is `min(completed_count, MAX_DIFFICULTY=4)`,
and `draw_choices()` pulls **only** from `POOL.by_difficulty(current_difficulty())` —
one tier, never a blend. So the tier a quest is stamped with decides exactly when in the
run it can appear, and nothing else about it scales.

Two escape hatches soften that:

- A cleared quest is held back until its whole tier is exhausted, then that tier's clears
  are wiped and it is offered fresh — a thin tier repeats rather than running dry.
- An **empty** tier falls back to `_nearest_tier()`, which walks outward (below first, then
  above) until it finds quests. A sparse pool never dead-ends the loop — it just silently
  serves a different tier than the player's progress asked for.

## The roster

| Quest | Difficulty | In pool? | Days | Gold | Food | Health | Combat | Utility | Σ targets |
|---|---|---|---|---|---|---|---|---|---|
| `tutorial` (Fetch Quest) | 0 *(default)* | no — forced first | 2 | 5 | 2 | 0 | 0 | 1 | **3** |
| `drowning_fish` (Drowning Fish) | 1 | **yes** | 1 | 10 | 3 | 0 | 0 | 2 | **5** |
| `harvest` (Harvest Herbs) | 1 | **yes** | 1 | 20 | 1 | 0 | 0 | 3 | **4** |
| `rescue` (A Trapped Chipmunk!) | 1 | **yes** | 3 *(default)* | 0 *(default)* | 2 | 2 | 0 | 4 | **8** |
| `racoons` (Thieving Raccoons) | 2 | **yes** | 4 | 30 | 5 | 3 | 5 | 2 | **15** |
| `scouting` (Explore the Verazon Forest) | 2 | **yes** | 5 | 25 | 6 | 2 | 3 | 4 | **15** |
| `weed_wacker` (Slay the Weed Wacker) | 2 | **yes** | 3 *(default)* | 25 | 2 | 5 | 5 | 1 | **13** |
| `wine_delivery` (Wine Delivery) | 3 | **yes** | 3 *(default)* | 40 | 2 | 1 | 5 | 1 | **9** |

Extra requirements, per quest:

| Quest | `required_items` (advisory) | `required_empty_cells` (gate) | `traits` |
|---|---|---|---|
| `tutorial` | package | — | warmth, cutting |
| `drowning_fish` | rope | — | food |
| `harvest` | — | **3** | versatile |
| `rescue` | — | — | cutting, healing, morale |
| `racoons` | — | — | movement, weapon |
| `scouting` | — | — | warmth, versatile, weapon |
| `weed_wacker` | — | — | defence, weapon, healing |
| `wine_delivery` | wine ×3 | — | weapon, liquid |

Reminder on the two strengths: `required_items` is **advisory** — a missing item is named
in the verdict line and changes nothing about whether the quest cleared.
`required_empty_cells` is a **gate**, judged alongside the four stat targets
(`cleared == count_targets_met() == 4 and quest.empty_space_met(free_cells)`).
`harvest` is the only quest using it.

## Tier occupancy

```
tier 0   authored: tutorial                          pool: —                (EMPTY)
tier 1   authored: drowning_fish, harvest, rescue    pool: all three
tier 2   authored: racoons, scouting, weed_wacker    pool: all three
tier 3   authored: wine_delivery                     pool: wine_delivery
tier 4   authored: —                                 pool: —                (EMPTY)
```

Every authored quest except `tutorial` is now in `quest_pool.tres`. `tutorial` stays out on
purpose: `main.gd` hands it to the player directly as the forced first quest, and pooling it
would make it redrawable later in the run.

## What that means for a real run

`current_difficulty()` climbs one per clear and caps at 4. Walking a clean run:

| Clears so far | Tier asked for | Tier actually served | Offered |
|---|---|---|---|
| 0 (after tutorial) | 0 | 1 (fallback) | 3 of drowning_fish, harvest, rescue |
| 1 | 1 | 1 | the tier-1 quests not yet cleared |
| 2 | 2 | 2 | 3 of racoons, scouting, weed_wacker |
| 3 | 3 | 3 | wine_delivery (alone) |
| 4+ | 4 | 3 (fallback) | wine_delivery, repeating |

So the ladder now runs **three real rungs**, three quests wide at the bottom two and one at
the top. Two soft spots remain: tier 0 has no pooled quest, so the first draw is still a
`_nearest_tier` fallback upward into tier 1; and tier 4 is empty, so a player who clears
four quests falls back to tier 3 and re-runs `wine_delivery`. In practice the day clock
(`TOTAL_DAYS = 15`) usually ends the run before that, since the tier-2 quests cost 3–5
gather days each.

## Findings worth a human call

1. **`rescue` pays 0 gold.** It never sets `gold_reward`, so it falls to the default of 0 —
   the only pool quest that pays nothing. Its neighbour at the same tier, `drowning_fish`,
   pays 10. This reads as an authoring omission, not a design choice, and it lands on a
   quest every run sees first.
2. **Tier 0 has no pool quest**, so the first post-tutorial draw is always a `_nearest_tier`
   fallback into tier 1. The fallback works, but it means the tier-0 rung of the ladder is
   fiction — the tutorial is the only thing that ever sits there.
3. **Tier 4 is empty and tier 3 holds one quest.** `MAX_DIFFICULTY` is 4, so a player who
   clears four quests falls back to tier 3 and is offered `wine_delivery` on repeat.
4. **`wine_delivery` is stamped harder than it plays.** At tier 3 its target sum is 9,
   below all three tier-2 quests (15/15/13). Its actual difficulty is concentration, not
   volume — combat 5 plus wine ×3 plus wine's `NoRotationEffect(rotate = 2)`. If tier is
   meant to track "how demanding", the stamp and the numbers disagree; if it tracks "how
   fiddly", it's right and the totals are a red herring.
5. **`harvest`'s room gate is tight against a starting bag.** `RunState.BAG_SIZES` is
   `[3, 4, 5, 6]`, so tier 0 is a **3×3 = 9-cell** board and `required_empty_cells = 3`
   asks for a third of it while still hitting utility 3 and food 1. Note the docstring on
   `quest_data.gd:83` says "a tier-0 (4×4) bag" and CLAUDE.md repeats the 4×4 — the code
   says 3×3. Trust `BAG_SIZES`. Now that `harvest` is pooled at tier 1, a player can hit
   this on a starting bag, so it wants a playtest.
6. **Three quests use the default `days = 3`** (`rescue`, `weed_wacker`, `wine_delivery`).
   Since `days` is the gather budget the *next* town phase gets, an unset value is a real
   balance value being chosen by accident rather than by the author.

## Note on narrative coverage

`departure` and `homecoming` are authored on **no** quest, and `narrative` beats only on
`tutorial` (`tutorial_beat`, `tutorial_supplies_beat`). Every other quest's playout is
verdict line only. That is known drift, documented in CLAUDE.md — not a difficulty problem,
but it does mean tiers 1–3 currently read identically at the story layer no matter how
they're packed.
