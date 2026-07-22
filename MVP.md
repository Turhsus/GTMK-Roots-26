# MVP Plan — "Pack Your Child's Adventure" (working title)

> Cozy packing game for GMTK Game Jam 2026. Engine: **Godot 4.6** (GDScript, 2D, Forward+).
> Inspirations: *Unpacking*, *A Little to the Left*, *Resident Evil* inventory.

---

## 1. One-sentence pitch

You are a parent packing your child's adventuring backpack. Space is limited, so every
item you drag, rotate, and squeeze into the bag is a tradeoff. When you send them off,
you read a short, reactive **adventure log** shaped by exactly what you packed — then you
can repack and try again.

---

## 2. Locked decisions (from kickoff)

| Decision | Choice | Consequence for the plan |
|---|---|---|
| Core mechanic | **Grid/spatial packing** — shaped items, drag + rotate + collision | Most code goes here; must be working early |
| Session structure | **Single quest, replayable** | One item pool + one quest; keeps scope tight |
| Outcome | **Narrated playout** — reactive text adventure log | Needs a small data-driven narrative engine + writing |
| Art | **Team artist** (custom art) | Plan defines asset specs + a placeholder→real swap pipeline |

---

## 3. What "MVP done" means (the finish line)

The MVP is complete when a player can, in one uninterrupted loop:

1. See a **quest brief** ("Rescue the lost kitten in Whisper Woods — you'll be gone ~4 days").
2. See a **tray of shaped items** and a **bag grid** with limited space.
3. **Drag** items from tray into the bag, **rotate** them (R / right-click), with valid/invalid
   placement clearly shown (green/red), and **remove** items back to the tray.
4. Watch **live stat bars** (Food, Health, Attack, Defense) update as items go in/out.
5. Press **"Send off"** and read a **narrated adventure log** whose beats change based on
   packed stats and specific items.
6. Press **"Pack again"** to reset and replay.

Everything beyond this is a stretch goal (Section 10). If we only ship the above, polished,
it is a complete, satisfying jam entry.

---

## 4. Core loop

```
  Quest brief  ─▶  PACK (drag / rotate / fit)  ─▶  Send off  ─▶  Narrated playout  ─▶  Pack again
                        ▲  live stat feedback                        │
                        └──────────────── retry ─────────────────────┘
```

---

## 5. Systems & data model

### 5.1 ItemData (Resource — `res://data/items/*.tres`)
Each item is a data asset so designers/artists can add items without touching code.

| Field | Type | Notes |
|---|---|---|
| `id` | String | Stable unique key, e.g. `"bread"` |
| `display_name` | String | "Loaf of Bread" |
| `shape` | Array[Vector2i] | Occupied cell offsets from top-left, e.g. `[(0,0),(1,0)]` for a 2×1 |
| `icon` | Texture2D | Art sprite (sized to shape bounding box — see Section 8) |
| `food` / `health` / `attack` / `defense` | int | Stat contribution (can be negative for tradeoffs) |
| `tags` | Array[String] | Narrative hooks, e.g. `["light","food","fragile"]` |
| `flavor` | String | One-line tooltip text |

### 5.2 QuestData (Resource — `res://data/quests/*.tres`)
| Field | Type | Notes |
|---|---|---|
| `title` | String | "Rescue the Lost Kitten" |
| `brief` | String | Shown before packing |
| `bag_cols` / `bag_rows` | int | Grid size (start 6×5) |
| `item_pool` | Array[ItemData] | Items available in the tray |
| `target_food/health/attack/defense` | int | Soft thresholds used to color bars + weight the narrative |
| `narrative` | Array[NarrativeEvent] | Ordered story beats (see 5.4) |

### 5.3 Stats
`Stats = componentwise sum of every packed item's contributions`. Recomputed on every
placement change. Bars show current value vs the quest's target (target = "full" mark).
Stats are **inputs to the narrative**, not a hard pass/fail gate.

### 5.4 NarrativeEvent (Resource) + NarrativeEngine
Data-driven so writers can add beats freely. Each event is one "day"/beat with variant lines
chosen by a condition:

```
NarrativeEvent:
  beat_id: String            # "day_2_food"
  variants: Array[Line]      # first matching variant wins
Line:
  text: String               # "Day 2 — the bread ran out early. Tummy rumbling."
  require_stat: {stat: min}  # e.g. {"food": 8}  (optional)
  require_tags: Array[String]# item tags that must be packed (optional)
  forbid_tags: Array[String] # tags that must NOT be packed (optional)
```

The engine walks events in order, picks the first variant whose conditions pass (fallback =
last/unconditional variant), and appends a final **outcome line** based on how many stat
targets were met. Result: a short, coherent log that feels authored by the player's packing.

---

## 6. Godot architecture

### 6.1 Autoloads (singletons)
- **GameState.gd** — current quest, packed items, computed stats; emits `stats_changed`.
- **AudioManager.gd** *(thin, optional in MVP)* — one-shot SFX for place/rotate/invalid/send.

### 6.2 Scenes
```
Main.tscn                # root; owns flow: Brief → Packing → Playout → back to Packing
├── BriefPanel.tscn      # quest title + brief + "Start packing"
├── PackingScene.tscn
│   ├── BagGrid.tscn     # the grid; placement/rotation/collision logic
│   ├── ItemTray.tscn    # spawns DraggableItem for each pool item
│   ├── DraggableItem.tscn
│   ├── StatsPanel.tscn  # 4 live bars vs targets
│   └── SendButton
└── PlayoutScene.tscn    # renders NarrativeEngine output line-by-line + "Pack again"
```

### 6.3 Key scripts & responsibilities
- **BagGrid.gd** — holds a `cols×rows` occupancy grid; `can_place(item, origin, rotation)`,
  `place(...)`, `remove(...)`; converts mouse → cell coords; draws hover highlight.
- **DraggableItem.gd** — follows mouse while dragging; asks BagGrid to validate; handles
  rotation (rotate the `shape` offsets 90°); returns to tray on invalid drop.
- **ItemTray.gd** — instantiates one DraggableItem per `item_pool` entry; refills on removal.
- **StatsPanel.gd** — listens to `GameState.stats_changed`; tweens bar fills.
- **NarrativeEngine.gd** — pure function: `(packed_items, stats, quest) → Array[String]`.

### 6.4 Grid math (implementation note)
Use a **custom drag** (item sprite follows the mouse), not Godot's `_get_drag_data` — shaped
multi-cell placement is much easier with manual grid math. Cell coord = `floor((mouse - grid_origin) / cell_size)`.
Rotation transforms each `Vector2i` offset: `(x,y) → (-y, x)` then normalize so min offset is `(0,0)`.

---

## 7. Milestone schedule (96 hours)

Aim to have a **playable end-to-end loop by ~hour 56**, then spend the back half on content,
art integration, and polish. Order is deliberately front-loaded on the risky core mechanic.

| Window | Goal | "Done when…" |
|---|---|---|
| **H0–8: Skeleton** | Project structure, autoloads, empty scenes, ItemData/QuestData resources, static bag grid + tray rendering with **placeholder colored rects** | Bag grid and tray draw on screen from data |
| **H8–24: The mechanic** | Drag, snap-to-grid, rotation, collision + bounds check, remove-back-to-tray, valid/invalid highlight | You can pack a bag with shaped items and it *feels* right |
| **H24–40: Stats** | Stat computation, StatsPanel live bars vs targets, GameState wiring | Bars react instantly and correctly as you pack/unpack |
| **H40–56: Full loop** | Send-off flow, NarrativeEngine, PlayoutScene, "Pack again" reset, quest brief | **End-to-end loop playable start→finish** |
| **H56–72: Content** | ~10–14 items with real stats/shapes/tags, one tuned quest, ~6 narrative beats with variants; begin swapping in real art | Game has real content, not just test data |
| **H72–88: Polish** | Juice (hover/snap/rotate tweens, invalid shake), SFX, main menu, tooltips, final art integration | It looks and feels cozy |
| **H88–96: Ship** | Export (Web/HTML5 for itch.io + Windows), bug bash, itch page, **buffer** | Uploaded and playable in a browser |

> **Golden rule:** if you hit hour 56 and the loop isn't playable, cut content and narrative
> variety — never cut the packing mechanic or the retry loop.

---

## 8. Art asset specs (for the team artist)

Give the artist these constraints up front so code + art fit without rework.

### 8.1 Grid & sizing
- **Cell size: 96×96 px** (cozy/chunky; readable). Author art at **2× (192px/cell)** for crispness, import at 100%.
- Bag grid MVP: **6 columns × 5 rows**.
- Each item sprite fills its **shape's bounding box**: a 2×1 item = 384×192 px source (192×96 in-game),
  transparent PNG, art centered in the occupied cells.
- Anchor/pivot at top-left of the bounding box (matches grid math).

### 8.2 Asset list (MVP)
- **Items (~10–14):** each = one transparent PNG. Suggested starters + shapes:
  bread (2×1), waterskin (1×2), sword (1×3), shield (2×2), torch (1×2), rope (2×1),
  potion (1×1), map (2×1), blanket (2×2), lantern (1×1), apple (1×1), spellbook (2×2),
  boots (2×1), whistle (1×1). *(Final shapes/stats set during H56–72 tuning.)*
- **Bag:** open-backpack background that the grid sits inside (grid area ≈ 576×480 px + framing).
- **UI:** 4 stat-bar frames + fills (Food/Health/Attack/Defense) with icons; buttons
  ("Start packing", "Send off", "Pack again"); brief/playout panel background; one display font.
- **Backdrop:** a cozy table/room scene behind the bag (single static image is fine).

### 8.3 Style guide
- Warm, soft, hand-drawn cozy palette (reference *A Little to the Left* / *Unpacking*).
- Consistent light direction across all items; consistent outline weight; muted saturation.
- Deliver as individual PNGs (no atlas needed for MVP; Godot imports loose files fine).

### 8.4 Placeholder → real swap pipeline
- Code renders every item from `ItemData.icon`. Until real art exists, `icon` points to a
  generated colored-rect placeholder sized to the shape.
- **Swap = drop the real PNG into `res://assets/items/` and set it as the item's `icon`.**
  No code changes. Keep filenames matching item `id` (e.g. `bread.png`) to make this trivial.

---

## 9. Project folder structure (target)

```
res://
├── autoload/        GameState.gd, AudioManager.gd
├── data/
│   ├── items/       *.tres (one per item)
│   └── quests/      whisper_woods.tres
├── resources/       item_data.gd, quest_data.gd, narrative_event.gd (class_name defs)
├── scenes/          Main, BriefPanel, PackingScene, BagGrid, ItemTray,
│                    DraggableItem, StatsPanel, PlayoutScene (.tscn + .gd)
├── assets/
│   ├── items/       real + placeholder PNGs
│   ├── ui/          bars, buttons, panels, font
│   └── sfx/         place/rotate/invalid/send (optional)
└── Main.tscn (entry scene)
```

---

## 10. Out of scope for MVP (stretch goals)

Only touch these after Section 3 is polished and shipped-ready:
- Multiple quests / quest select / difficulty curve.
- Save system, item unlocks, currency, progression.
- Animated adventurer mini-scene (we chose narrated text instead).
- Weight vs volume dual constraints; fragile-item breakage; weather modifiers.
- Full soundtrack; localization; controller support.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Drag/rotate/collision eats too much time | It's scheduled first (H8–24); use custom grid math, not Godot drag API; placeholder art so code is unblocked |
| Narrative feels flat | Keep beats few but condition-rich; write for the *extremes* (packed no food / all weapons) first — those are the funny ones |
| Art arrives late | Placeholder pipeline (8.4) means art is a no-code swap at any time |
| Scope creep into multiple quests | Data supports it, but MVP ships one quest tuned well |

---

## 12. Prompts you can give me to build this

Copy-paste these to me **in order**. Each is a self-contained build step; I'll implement,
you playtest, then move to the next.

1. **Skeleton & data**
   > "Set up the Godot project skeleton from the MVP plan: create the folder structure,
   > the GameState autoload, and the `ItemData`, `QuestData`, and `NarrativeEvent` resource
   > scripts with `class_name`. Make placeholder colored-rect textures for items."

2. **Static bag + tray from data**
   > "Build BagGrid.tscn and ItemTray.tscn that render a 6×5 grid and a tray of shaped items
   > from a QuestData resource, using placeholder art. No dragging yet — just correct layout
   > and sizing at 96px cells."

3. **The core mechanic**
   > "Implement drag-and-drop in DraggableItem/BagGrid: snap-to-grid placement, rotation on
   > R and right-click, bounds + collision checks, green/red placement highlight, and
   > remove-back-to-tray. Use custom grid math, not Godot's drag API."

4. **Stats**
   > "Add the stats system: compute Food/Health/Attack/Defense from packed items in GameState,
   > and build StatsPanel.tscn with four live bars vs the quest targets that tween on change."

5. **Full loop**
   > "Wire the whole flow in Main.tscn: quest brief → packing → Send off → PlayoutScene →
   > Pack again. Implement NarrativeEngine.gd that turns packed items + stats + quest into an
   > ordered list of log lines, and render them one-by-one in PlayoutScene."

6. **Content pass**
   > "Create ~12 real items (.tres) with balanced shapes/stats/tags and the Whisper Woods
   > quest with ~6 narrative beats (with stat/tag-conditioned variants). Tune bag size for a
   > meaningful ~70%-fill tradeoff."

7. **Juice & audio**
   > "Add polish: hover lift, snap and rotate tweens, invalid-placement shake, and SFX hooks
   > through AudioManager for place/rotate/invalid/send."

8. **Ship it**
   > "Add a main menu, set up HTML5 (Web) and Windows export presets for itch.io, and give me
   > an itch.io upload checklist."

Optional anytime:
   > "Swap in the real art: here are PNGs in assets/items/ named by item id — wire them up."

---

## 13. Open questions to confirm before/while building

- **Title?** ("Pack Your Child's Adventure" is a placeholder.)
- **Tone of the narrative:** wholesome-sweet, gently comedic, or bittersweet? (Affects writing.)
- **Can stats go negative / can items be harmful** (e.g. a heavy anvil that tanks Food)? Adds
  fun tradeoffs but slightly more balancing.
- **Rotation control:** keyboard `R`, right-click, or both? (Plan assumes both.)
- **Target platform for judging:** browser (HTML5) is strongly recommended for jam reach —
  confirm we optimize for that.
```
