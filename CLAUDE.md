# CLAUDE.md

Guidance for Claude Code working in this repo. Keep it current — when files are added, renamed, or deleted, update the map below in the same change.

## What this is

**GTMK-Roots-26** — a cozy packing game for GMTK Game Jam 2026. Godot 4.7, GDScript, 2D
Forward+. You pack a bag for your child's adventure; the packing decides how the trip goes.
Inspirations: *Unpacking*, *A Little to the Left*, *Resident Evil* inventory.

Design intent lives in `MVP.md` (scope/plan) and `narrative_treatment.md` (the coming-of-age
theme). `review.md` is an architecture review from 2026-07-23 — useful context, but it
predates later commits, so trust the code over it.

## Commands

Run the headless test harnesses in `tools/` — these are scenes, not `--script`, so the
autoloads exist:

```
godot --headless --path . res://tools/TestPacking.tscn   # mouseless drag end-to-end
godot --headless --path . res://tools/TestEffects.tscn   # PackLayout + ItemEffects, no scene tree
godot --headless --path . res://tools/TestSave.tscn      # save round-trip + corrupt/outdated files
godot --headless --path . res://tools/TestFlow.tscn      # full loop + RunState progression
godot --headless --path . res://tools/TestShop.tscn      # shop stock, buy/sell, restock
```

Each prints failures and sets a nonzero exit on failure. `TestSave` writes to the real
`user://` save path but backs up and restores any existing save. A harness whose script
fails to *parse* never reaches `quit()` and so hangs rather than exiting — if a run seems
to stall, look for a `Parse Error` in its first lines (this is `TestEffects` today).

`tools/Screenshot.tscn` photographs the loop screens. It must **not** run headless — the
dummy renderer captures blank frames:

```
godot --path . res://tools/Screenshot.tscn -- --phases packing,gather --out shots
```

### Debug switches

The `DebugFlags` autoload holds the runtime switches (`skip_playout`,
`durability_report`, `debug_menu`). They are toggleable mid-run from the pause menu's
debug panel, and settable at launch:

```
godot --path . res://scenes/Main.tscn -- --skip-playout=false
```

`DebugFlags.available` is `OS.is_debug_build()`, so **every flag reads off in an exported
build** no matter its default — a shipped build cannot skip the playout. Nothing persists;
flags are launch-scoped, which is why the harnesses force the ones they care about off in
`_ready()` rather than depending on the defaults. Adding a switch is one entry in
`DebugFlags.FLAGS` — the pause-menu toggle is built from that dictionary.

Export presets are **Web** (`build/web/index.html`, single-threaded on purpose so itch.io
works without the SharedArrayBuffer toggle) and **Windows** (`releases/pack_bag.exe`).
Full release checklist in `SHIPPING.md`.

## Architecture

`project.godot`: entry scene `scenes/menu/MainMenu.tscn`, viewport 1920x1080
(`canvas_items` + `expand`), project theme `resources/ui/roots_theme.tres`.

**The loop**, owned end to end by `scenes/main.gd`:

```
MainMenu -> Main -> tutorial quest -> Packing -> send-off -> Playout
					  ^                                        |
					  |                          (on failure) PerkSelect
					  |                                        |
				 QuestSelect <- RoadScene/ShopScene (gather) <-+
```

The first quest is a fixed tutorial (`RunState.TUTORIAL`) — packed immediately, no picker
and no gather before it. `ThankYouScreen` ends the run when the day clock runs out.

**Three layers of state, and the split matters:**

- `GameState` — the *current* packing. What is in the bag and the stats that follow.
- `BagGrid` — *where* things sit. Cell↔pixel math and the occupancy map.
- `RunState` — the run *above* both. Gold, owned inventory, bag tier, difficulty, perks,
  quest draws, item wear.

Don't let these leak into each other. `GameState` never learns about positions; `BagGrid`
never learns about stats.

**Two extension points, both "add a subclass, never a new data class":**

- **Perks** (`resources/perk_data.gd`) — hooks `modify_stats` (during packing) and
  `modify_item` (at send-off). `resources/perks/perk_registry.gd` is *the one place* to
  register a perk: write the subclass, add its class name to `TYPES`. No `.tres` needed.
- **Item effects** (`resources/effects/item_effect.gd`) — per-item placement rules,
  composed onto an `ItemData` via its `effects` array. Most resolve at **send-off** against
  a `PackLayout` snapshot and dock durability — a bad pack is a *consequence*, never a
  blocked placement. A separate `live_bonus` hook resolves continuously *while packing*
  (BagGrid.compute_live_bonus -> GameState.set_layout_bonus) for temporary,
  neighbour-dependent stat bonuses that never touch durability and don't survive send-off
  (see `neighbor_stat_boost_effect.gd`).

`systems/` is deliberately free of scene-tree and autoload access — `NarrativeEngine` is a
pure `(quest, packed_items, stats) -> Array[String]`, which is why the playout can be
regenerated, previewed, or tested headless.

## Conventions

- A `X.tscn` pairs with a snake_case `x.gd` in the same folder.
- Every `.gd` has a sibling `.uid`, every `.png`/`.wav` a sibling `.import`. Godot
  generates both — never hand-edit them, and don't count them as files.
- Content is authored as `.tres` under `data/` so items, quests, shops, and events can be
  added or tuned without touching code.
- Trait strings must come from `data/trait_registry.tres` (reached via the `Traits`
  autoload) so spelling can't drift into "warm" vs "warmth". `ItemData` and `QuestData` are
  `@tool` purely so the inspector shows that vocabulary as a dropdown.
- Screens below `Main` hold no state and no selection logic — they lay out what they're
  handed and emit a signal up (`quest_chosen`, `perk_chosen`, the shop's buy/sell). `Main`
  owns scene changes and phase jumps.
- Code that builds a `PanelContainer` at runtime must go through `systems/ui.gd`. The
  project theme's default label colour is light for dark backdrops, but a themed panel is
  tan — a plain `PanelContainer.new()` renders light-on-tan and is invisible.
- Autosaves happen at *phase boundaries* only (start of packing, each town day, the
  picker), never mid-drag. The save has a "run" half owned by `RunState` and a "loop" half
  owned by `main.gd`.
- Shop backgrounds are convention, not config: `assets/backgrounds/shop_<id>.png`.

## File map

Line counts are from 2026-07-25 (commit `43b2cd5`) and are there to signal weight, not to
be precise.

### autoload/ — singletons, registered in `project.godot`
| File | | |
|---|---|---|
| `game_state.gd` | 93 | Current quest, packed items, derived stats (food/health/combat/utility). |
| `run_state.gd` | 548 | The run: gold, inventory, bag tier, difficulty, perks, draws, wear, serialization. Biggest file here. |
| `save_manager.gd` | 122 | Reads/writes the single autosave file. |
| `traits.gd` | 23 | Global access to the trait vocabulary. |
| `audio_manager.gd` | 30 | One-shot SFX; a missing stream is a harmless no-op. |
| `debug_flags.gd` | 78 | Runtime debug switches; off in exported builds. See "Debug switches". |

### systems/ — pure logic, no scene tree
| File | | |
|---|---|---|
| `narrative_engine.gd` | 102 | Packed bag -> adventure log. Departure line, authored beats, homecoming line. |
| `pack_layout.gd` | 97 | Immutable send-off snapshot of the board; what effects query. |
| `ui.gd` | 25 | Runtime UI constructors (see the theme note above). |

### resources/ — the data schema
| File | | |
|---|---|---|
| `item_data.gd` | 159 | One packable item: shape, stats, durability, traits, `effects`. `@tool`. |
| `quest_data.gd` | 77 | Brief, offered items, stat targets, narrative beats. `@tool`. |
| `quest_pool.gd` | 27 | The authored list of all quests; `RunState` draws from it. |
| `shop_data.gd` | 27 | A shop's themed stock. Selling is per-item, not per-shop. |
| `trait_registry.gd` | 19 | Master lists of item traits and quest traits. |
| `travel_event.gd` | 17 | Road vignette; at most one per gather. |
| `narrative_event.gd` / `narrative_line.gd` | 18 / 31 | A beat and its conditional variants — first passing variant wins, so authored order is priority. |
| `perk_data.gd` | 45 | Perk base class. |
| `perks/` | | `perk_registry.gd` (the `TYPES` list), `forage_perk.gd`, `crafty_perk.gd`. |
| `effects/` | | `item_effect.gd` (base: `resolve_send_off` + `live_bonus`), `clear_above_effect.gd`, `no_adjacent_trait_effect.gd`, `no_rotation_effect.gd`, `protect_adjacent_item_effect.gd`, `neighbor_stat_boost_effect.gd` (live-only neighbour stat bonus, no `.tres` registry needed — effects are picked straight off `class_name` in the inspector). |
| `ui/*.tres` | | `roots_theme.tres`, `panel_content_theme.tres`, `panel_frame.tres`, `button_{normal,hover,pressed,focus,disabled}.tres`. |

### scenes/
| File | | |
|---|---|---|
| `main.gd` | 516 | Root. Owns the loop and the save's "loop" half. |
| `menu/main_menu.gd` | 49 | Title screen, outside the loop. |
| `packing/packing_scene.gd` | 334 | Owns the drag — the only node that sees both bag and tray. |
| `packing/bag_grid.gd` | 247 | Always draws the full 6x6 board; the bag tier is the playable top-left region, the rest blacked out. `@tool`. |
| `packing/draggable_item.gd` | 262 | One item view, sized to its shape's bounding box at 96 px/cell. |
| `packing/item_tray.gd` | 118 | Spawns views from `RunState.inventory`; nodes are reparented tray↔bag, never re-instantiated. |
| `packing/stats_panel.gd` | 85 | Four live bars; reads `GameState` and nothing else. |
| `packing/grid_highlight.gd` | 36 | Green/red placement preview, above the item layer. |
| `playout/playout_scene.gd` | 120 | Reveals the log line by line; click/space dumps the rest. |
| `gather/road_scene.gd` | 419 | The gather phase: day budget, one shop per day, next-quest preview, travel events. |
| `gather/shop_scene.gd` | 196 | Presentation-only buy/sell rows; the road applies the trade. |
| `select/quest_select.gd` | 138 | Quest picker cards. |
| `perk/perk_select.gd` | 68 | The lesson screen after a failed quest. |
| `pause/pause_menu.gd` | 87 | Overlay, `PROCESS_MODE_WHEN_PAUSED`, emits requests to `Main`. |
| `end/thank_you_screen.gd` | 36 | Run summary sign-off. |

Also `scenes/gather/TownScreen.tscn` (no paired script).

### data/ — authored content
- `items/` — 19: apple, axe, berries, blanket, boots, bread, cheese_wedge, crowbar, flail,
  flint_and_steel, health_potion, helmet, knife, package, rope, shield, sword, torch, wine.
- `quests/` — **only 3**: `tutorial`, `rescue`, `scouting`. `quest_pool.tres` is the pool.
- `shops/` — grocer, blacksmith, apothecary.
- `travel_events/` — found_coin, found_coin_pouch.
- `trait_registry.tres` — the trait vocabulary.

### assets/
`items/` (18 png), `shops/` (3), `backgrounds/road.png`, `ui/` (textbox, textbox_small,
finalpacking_bg), `sfx/` (place, rotate, invalid, send).

### tools/
The five test harnesses and `Screenshot.tscn` above, plus asset generators
`make_placeholders.py`, `make_backgrounds.py`, `make_sfx.py`.

Gitignored: `.godot/`, `/android/`, `/build/`, `.vscode/`, and the built `releases/pack_bag*.exe`.

## Known drift

- **No quest has any authored `narrative` at all.** All five `.tres` files have an empty
  beats array, so every playout is just `NarrativeEngine`'s generated departure and
  homecoming lines. `NarrativeEvent`/`NarrativeLine` and the first-match-wins variant
  system are fully built and entirely unused — the conditional-variant tests in
  `test_flow.gd` report SKIP until a quest gets beats.
- `data/quest_pool.tres` holds only `rescue` (tier 1) and `scouting` (tier 2).
  `racoons` and `drowning_fish` exist but are not in the pool, so they are unreachable;
  and **no quest sits at tier 0**, so a fresh run relies on `RunState._nearest_tier()`
  to have anything to offer.
- `tools/test_effects.gd` references a `NoUpsideDownEffect` class that no longer exists —
  **the script fails to parse, so that harness hangs instead of exiting.** Whatever
  replaced it (`NoRotationEffect`?) needs the assertions rewritten, not just renamed.
- `tools/test_packing.gd` has 4 failing assertions: one on the stats-panel bar maximum,
  and three on cell size — the harness compares against `BagGrid.current_cell_size()`
  while the tray's item views are sized from a different value (it reads 61.6 where the
  harness expects otherwise). Needs a decision on the intended sizing contract.
- `data/items/apple.tres` is authored with `id = "Apple"`; all 21 other items are
  lowercase. `RunState.find_item()` masks this via its `data/items/<id>.tres` filename
  fallback, but anything comparing `item.id` against a lowercase literal silently misses.
  The harnesses route through the resource's own id to stay neutral on it.
- `SHIPPING.md` says the Windows export lands at `build/windows/pack-your-childs-adventure.exe`
  and asks for 4.6.2-stable templates; the actual preset writes `releases/pack_bag.exe` and
  `project.godot` declares feature `4.7`. Trust `export_presets.cfg` and `project.godot`.
