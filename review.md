# Architecture & State-of-the-Game Review

**Project:** GTMK-Roots-26 — "Pack Your Child's Adventure" (Godot 4.6, GDScript)
**Reviewed:** 2026-07-23, at commit `15006fd` ("Added save but no idea if it worsks.")
**Scope:** architecture, file sizes, file/class organization, coupling, dead code, content state. No code was changed.

---

## 1. Executive summary

The project is in **very good shape for a jam codebase, and honestly better than most shipped jam games**. The layering is clean and consistently enforced: data definitions (`resources/`), authored content (`data/`), stateless logic (`systems/`), global state (`autoload/`), and phase-grouped UI (`scenes/`) each do one job, and the dependency arrows almost all point the right way. Every feature that has landed (multi-quest loop, persistent inventory, gather phase, perks, day clock, save system) arrived with matching headless test coverage, which is remarkable discipline.

The three most important findings, in order:

1. **Debug switches are currently shipping the wrong game.** `DEBUG_SKIP_PLAYOUT = true` in `main.gd` means the narrated adventure log — the core pitch of the game — never plays. `DEBUG_SKIP_GATHER` and the always-on debug quest picker also ship enabled. These are one-line flips, but they must not be forgotten.
2. **The content is far behind the systems.** The difficulty ramp goes to tier 4, but every authored quest is difficulty 0, so the ramp never actually happens. The `utility` stat exists in every UI and data structure but is 0 on all 16 items and all quest targets — a stat that can never do anything. The hardcoded "kitten" homecoming lines play at the end of *every* quest, not just Whisper Woods.
3. **`run_state.gd` is on the path to god-object.** It's fine today, but it now owns six unrelated concerns and every new feature has landed there. Worth a deliberate line in the sand before the next system.

Everything else below is detail, ranked so you can stop reading when it stops being useful.

---

## 2. Architecture overview

### 2.1 The layers

```
data/        authored .tres content (items, quests, shops, perks, trait registry, quest pool)
resources/   class_name'd Resource definitions the .tres files instantiate
systems/     stateless pure logic (NarrativeEngine)
autoload/    global state singletons (GameState, RunState, SaveManager, Traits, AudioManager)
scenes/      phase-grouped UI (menu/ select/ packing/ gather/ perk/ playout/ end/) + Main.tscn loop owner
tools/       headless test harnesses + placeholder-asset generators
```

This is a textbook Godot layering and it is **actually followed**, which is the rare part. Spot checks confirm:

- No scene script holds run state; screens are presenters that read the autoloads and emit signals upward.
- `NarrativeEngine` is genuinely pure — it re-derives packed tags itself rather than reading `GameState`, so logs are testable for hypothetical packings.
- Content changes (new item, new quest, new shop, retuned prices) are .tres edits with zero code, exactly as `MVP.md` §8.4 planned.
- Assets are swappable by filename convention (`assets/items/<id>.png`), and the placeholder generators (`tools/make_placeholders.py`, `make_sfx.py`) keep that pipeline honest.

### 2.2 State ownership (who owns what)

| Owner | Owns | Assessment |
|---|---|---|
| `GameState` | current quest, packed items, derived stats | Clean, small (91 lines), single-purpose |
| `RunState` | progression, inventory, gold, perks, day clock, id lookups, serialization | Correct but overloaded — see §5.1 |
| `SaveManager` | the one autosave file, version gate, pending-loop handoff | Clean, well-reasoned (the flush-on-close web note, the discard-don't-half-load policy) |
| `BagGrid` | *where* items sit (occupancy) | Clean split from GameState's *what* |
| `main.gd` | the phase loop + loop-position save half | Right place for it |
| Screens | nothing but presentation | Consistently true |

The one deliberate cross-layer read — `GameState._recompute()` reading `RunState.food_bonus()` — is documented at the call site and is the only place GameState knows RunState exists. Acceptable; if perks grow more stat effects, consider inverting it (RunState pushes a modifier dict into GameState) so the read stays single-direction.

### 2.3 Signal flow

Signals flow **up** (screens emit `sent_off`, `quest_chosen`, `gather_done`, `perk_chosen`; `main.gd` is the only listener that changes phase) and state flows **down** (autoload signals like `stats_changed`, `inventory_changed`, `gold_changed` fan out to whoever displays them). There are no sideways screen-to-screen connections. This is the right shape and it's why the loop kept absorbing new phases (gather, perk, end) without rewiring.

One subtle strength worth preserving: all loop screens stay in the tree and `_show()` toggles visibility. The comment in `main.gd` explains why (the log is built from a bag that's still packed; quest switch is a reset, not a rebuild). Keep that invariant in mind if anyone ever converts screens to `change_scene`.

### 2.4 Documentation quality

The comment discipline is the best thing in this codebase. Nearly every non-obvious decision has its *why* written at the point of decision — the tray's deliberate non-rebuild on `inventory_changed`, the `_ready` ordering sweep in `PackingScene`, the typed-array parser gotcha in `quest_pool.gd`, the IndexedDB flush in `SaveManager`. A new contributor could onboard from the comments alone. `MEMORY.md`/`MVP.md` and the code agree with each other.

---

## 3. File sizes

All script sizes are healthy. For reference (GDScript, comment-heavy style, so effective logic is ~60% of these numbers):

| File | Lines | Verdict |
|---|---|---|
| `tools/test_flow.gd` | 448 | Fine for a test harness, though it now tests five different systems — see §6.4 |
| `autoload/run_state.gd` | 435 | Largest production file; ~40% doc comments. Fine today, watch it — §5.1 |
| `scenes/gather/town_screen.gd` | 360 | Half of it is build-UI-in-code boilerplate — §5.2 |
| `scenes/main.gd` | 250 | Good size for the loop owner |
| `scenes/packing/draggable_item.gd` | 247 | Two jobs (drag view + info panel) — §5.3 |
| `scenes/packing/packing_scene.gd` | 229 | Dense but coherent; it earns its size as the drag owner |
| `scenes/packing/bag_grid.gd` | 210 | Good |
| everything else | ≤ 138 | Good |

No file is at a worrying size. The signal to watch is not line count but *concern count* (run_state, draggable_item, town_screen).

Scene files are all small (≤ 119 lines) because layout is mostly built in code — a tradeoff, discussed in §5.2.

---

## 4. File organization

The phase-grouped `scenes/` layout (`menu/ select/ packing/ gather/ perk/ playout/ end/` with `Main.tscn` alone at top level) is self-documenting: the folder listing *is* the game loop. `snake_case.gd` / `PascalCase.tscn` naming is consistent throughout. `resources/` vs `systems/` vs `autoload/` boundaries are respected — nothing is misfiled.

Minor housekeeping items:

- **`assets/items/cheese.png` is an orphan** — there is no `cheese.tres`, no reference anywhere. Either it's an upcoming item (fine) or leftover (delete).
- **`assets/ui/GJ_packing_BG.png` is unused** — only `finalpacking_bg.png` is referenced (by `PackingScene.tscn`). Presumably a superseded background; delete or it will ship in the export pack.
- `data/quests/frost_hollow.tres` is authored but deliberately not in the pool — that's documented, fine, but it's only reachable via the debug picker, so remember it exists when the debug picker is removed.
- `README.md` is a two-line stub. Fine until ship; the itch page copy will want a paragraph.

---

## 5. Class organization — the three growth risks

### 5.1 `RunState` is quietly becoming a god object

It currently owns: (1) quest progression & difficulty draw, (2) the persistent inventory, (3) gold, (4) perks, (5) the global day clock, (6) id→resource lookups and save serialization. Each addition was individually reasonable and the file is well-organized internally, but the trend is clear — every new system since multi-quest has landed here, and it now emits five signals and holds four preload consts.

**Recommendation:** don't refactor now (jam), but adopt a rule: the *next* system (e.g. quest requirements) gets its own home. If a post-jam cleanup happens, the natural split is `RunState` (progression/clock) + `Inventory` (items/gold, already a coherent cluster: `gain`/`release`/`apply_wear`/`_stock_starter_inventory`) + keeping serialization where the data lives. The signals already partition along exactly those lines, which tells you the seams are real.

### 5.2 Three screens hand-build near-identical card UIs in code

`QuestSelect._build_card`, `PerkSelect._build_card`, and `TownScreen._build_preview_card` are structural triplets (PanelContainer → MarginContainer → VBox → title label + body + button), and `TownScreen` additionally hand-rolls `_heading`/`_subheading`/`_muted`/`_spacer` label factories. The same "detach-then-queue_free so a same-frame rebuild doesn't stack children" idiom is copy-pasted in four files (`quest_select.gd`, `perk_select.gd`, `playout_scene.gd`, `town_screen.gd` — and notably `PerkSelect.present()` has the detach loop while an equivalent in `ItemTray.populate()` does *not* detach, an inconsistency that works only because tray rebuilds never happen twice in a frame).

Build-in-code was a sound jam choice (no .tscn merge conflicts, easy variable card counts). But the duplication is now big enough that a single shared helper — a `ui_builders.gd` with `card(title, body, button_text) -> {card, button}` and `clear_children(node)` — would delete ~150 lines across three files and make a future theme/skin pass one-file instead of three. This is the highest-value cheap refactor in the codebase.

Same story in miniature: the days-left label logic (`"Final days!" / "Time's up" / "%d days left"`) is duplicated between `town_screen.gd:89` and `quest_select.gd:41` with slightly different strings — a divergence bug waiting to happen.

### 5.3 Smaller structural notes

- **`DraggableItem` has two jobs**: the drag/juice view, and the static `build_info_panel()` item-inspector factory (~60 lines). The static factory would sit better in its own file (or the future `ui_builders.gd`) — right now the *tooltip panel style* lives in the drag view class and is also raised by `PackingScene`.
- **`BagGrid._shared_cell_size` is static mutable state.** It works because there is exactly one BagGrid alive, and the `_enter_tree` seeding order is documented — but it's the kind of hidden global that breaks silently if a second grid ever exists (e.g. a "preview bag" on quest cards). A future pass could inject the cell size via the tray/scene instead. Not urgent; just know it's there.
- **`GameState.get_packed_tags()` vs `NarrativeEngine.collect_tags()`** duplicate the same dedup loop. This one is *deliberate* (engine purity) and documented; fine to keep, but `GameState.get_packed_tags` currently has no callers outside itself worth keeping — check whether it's dead (the narrative path uses the engine's copy).
- **`quest_data.gd` carries three fields nothing reads**: `item_pool` (vestigial since persistent inventory — documented), `required_items` (groundwork, unread), `traits` (groundwork, unread), plus `bag_cols`/`bag_rows` which `BagGrid` deliberately ignores (fixed 6×6) while quests still author 5×4 / 6×4 / 6×5 values. Each is individually explained, but together the class now lies to a reader: half its exports do nothing. Recommend a cleanup commit that deletes `item_pool` + `get_grid_size()` and either deletes `bag_cols/rows` or makes BagGrid honor them — the current "authored but ignored" state is the worst of both.
- **The Traits system is scaffolding without a building.** `Traits` autoload + `TraitRegistry` + the `@tool` inspector dropdowns are nicely done, but at runtime nothing reads the registry — narrative matching uses raw item `traits` strings directly, the `int` weights are placeholders, and quest `traits` are unread. This is fine *if* quest requirements land soon; if they don't, the whole autoload is dead weight for the ship build. Either wire it in or note it as post-jam.
- **`PackingScene.QUEST` preload of whisper_woods** as the standalone-run fallback is a small hidden coupling (the packing scene knows a specific quest). Harmless, documented, but consider pointing it at `RunState.TUTORIAL` so there's one "default quest" concept.

---

## 6. Correctness & ship-readiness findings

### 6.1 Ship blockers (trivial fixes, high stakes)

1. **`main.gd:32` — `DEBUG_SKIP_PLAYOUT := true`.** The adventure log — the game's entire narrative payoff, per MVP §1 — is currently skipped on every send-off. The log lines are still *built* and discarded.
2. **`town_screen.gd:26` — `DEBUG_SKIP_GATHER := true`** puts a "DEBUG: Skip gather" button on the town square.
3. **`quest_select.gd:86-138` — the debug quest picker is unconditional.** Unlike the other two, it has no flag at all; `_ensure_debug_picker()` always builds the "🔧 DEBUG: pick any quest" button. Removal requires deleting the block (the comment says how). Worth flagging because it also bypasses the day clock and difficulty draw entirely.

**Recommendation:** a single `Debug` autoload or one `const DEBUG := false` in one place that all three read, so ship-readiness is one diff line, greppable. Right now it's three flags in three files with three shapes.

### 6.2 Content bugs / design-code mismatches

4. **The homecoming lines are Whisper Woods-specific but play for every quest.** `narrative_engine.gd:78-89` hardcodes five kitten-rescue endings ("kitten asleep in the crook of one arm...") keyed only to targets-met count. Clear Night Market or Cinder Ford and a kitten still comes home. The departure line is generic, the homecoming is not. Fix options: move outcome lines into `QuestData` (an `outcomes: Array[String]` keyed 0–4, falling back to generic text), or genericize the writing. This is the biggest "systems outgrew the content" seam.
5. **The difficulty ramp has no content.** `MAX_DIFFICULTY = 4`, the picker shows "Difficulty N", `draw_choices` ramps by clears — but every pool quest is difficulty 0, so `_nearest_tier` silently serves tier 0 forever. The system is tested and works; the *game* currently has no ramp. With the 10-day clock a run is roughly 3–4 quests, so you need maybe 6–9 quests across 2–3 tiers to make the ramp felt. This is the single largest remaining content lift.
6. **The `utility` stat is inert.** Renamed in at commit `19c830f`, it appears in `STAT_KEYS`, StatsPanel, tooltips, shop rows — and is 0 on all 16 items and 0 in every quest's target (auto-met). Players will see a bar that never moves. Either give some items utility (map, rope, lantern are obvious candidates) and a quest that targets it, or cut the stat before ship.
7. **"Quest N" numbering counts clears, not attempts** (`quest_select.gd:26` uses `completed_count + 1`), so after a failure the header repeats the same number. Probably fine ("you're still on quest 2"), just confirm it's intended.

### 6.3 Minor robustness notes (no action urgent)

- `RunState.from_dict` doesn't clamp `days_remaining` to `TOTAL_DAYS` (a hand-edited save can exceed the run length) and `spend_day` can drive it negative before `days_are_up` is consulted — both harmless today because the UI floors at 0.
- `TownScreen._skip_gather` bills the clock via a loop of `spend_day()` — correct, but each call emits `days_changed`; fine at this scale.
- `ItemTray.populate` queue-frees without detaching (see §5.2) — currently safe, but it's one repopulate-twice-in-a-frame away from ghost items.
- `SaveManager.delete_save` opens `DirAccess` each call — fine; just noting `FileAccess` has no remove, so this is the right pattern.
- The `quest_pool.gd` typed-array parser workaround is well-documented and correctly quarantined inside the one file where types resolve; nothing to do, but preserve that comment through any refactor.

### 6.4 Tests

Coverage is genuinely good: packing mechanics (`test_packing`), narrative + progression + perks + clock + full-loop integration (`test_flow`), and a save round-trip with corrupt-file and end-to-end-resume cases (`test_save`) — including the `autosave_enabled` guard so tests can't clobber a real save, and backup/restore of the user's actual save file around the run. The commit message says "no idea if it worsks" but `test_save.gd` is 237 lines of exactly finding that out — run it.

Two observations:

- `test_flow.gd` now covers five systems in one file with a shared `check()` counter; splitting is optional, but the flow test's hardcoded whisper-woods target numbers (noted in memory) make content retuning brittle — consider reading targets from the .tres in assertions instead of literals.
- Nothing exercises `MainMenu` (documented) or `ThankYouScreen`'s reset path, and the debug quest picker is untested (it should be deleted before ship anyway).

---

## 7. State of the game vs. the plan

Measured against `MVP.md` §3, the MVP finish line was crossed long ago, and four of the five "out of scope" stretch goals (§10) have since shipped: multiple quests + select + difficulty scaffolding, save system, currency + shops, and progression (perks, durability, day clock). What the plan called the finish line is now the inner loop of a roguelite structure. That's an unusual amount of ground for a jam timeline.

What remains between here and a shippable build, in priority order:

1. **Flip/remove the three debug switches** (§6.1) — minutes.
2. **Quest content**: 4–6 more quests across difficulty tiers 1–2, each with beats and tuned targets (§6.2.5). This is the long pole.
3. **Per-quest (or genericized) homecoming lines** (§6.2.4).
4. **Decide utility's fate** (§6.2.6).
5. **Real art & audio** — the swap pipeline is ready and zero-code; blocked on assets, not engineering.
6. **A balance pass on the economy** — 50 starting gold, rewards 15–30g, prices unreviewed here; the gather loop is tested mechanically but not tuned.
7. Housekeeping: orphaned assets (§4), vestigial QuestData fields (§5.3), the shared card-builder extraction if time allows (§5.2).
8. Run `SHIPPING.md`'s checklist — the export presets are already configured (web single-threaded for itch, correctly).

---

## 8. Summary scorecard

| Area | Grade | One-liner |
|---|---|---|
| Layering & ownership | A | Textbook, and actually enforced |
| Signal architecture | A | Up-only events, down-only state; no sideways coupling |
| Documentation | A+ | Decision-level comments everywhere; memory/docs agree with code |
| File organization | A− | Phase-grouped and consistent; two orphan assets |
| File/class sizes | B+ | Nothing oversized; RunState and the card-builder triplets are the watch items |
| Data-driven content pipeline | A− | .tres + filename conventions all the way down; Traits layer not yet earning its keep |
| Test coverage | A− | Rare for a jam; flow test getting monolithic and literal-coupled |
| Ship readiness | C | Three live debug switches, one of which hides the core feature |
| Content completeness | C+ | Systems: done. Quests/tiers/utility/art: the actual remaining work |

The engineering is ahead of the game. The next commits should mostly be `.tres` files and writing, not code.
