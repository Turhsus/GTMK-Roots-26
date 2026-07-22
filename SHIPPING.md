# Shipping checklist — itch.io

Two presets are configured in `export_presets.cfg`: **Web** (the one judges will
use) and **Windows**. Web is exported single-threaded on purpose — it runs on
itch.io without the SharedArrayBuffer toggle and works in every browser.

## 0. One-time setup

- [ ] In the Godot editor: `Editor > Manage Export Templates > Download and Install`
      (must match 4.6.2-stable). Exports fail with a template error until this is done.
- [ ] Create the itch.io project page (Dashboard → Create new project),
      set **Kind of project: HTML**.

## 1. Export

- [ ] `Project > Export… > Web` → Export Project → keep `build/web/index.html`
      (the file **must** be named `index.html` or itch shows a blank page).
- [ ] `Project > Export… > Windows` → Export Project → `build/windows/pack-your-childs-adventure.exe`
      (`embed_pck` is on, so the .exe is the whole game).
- [ ] Zip each folder's *contents* (not the folder itself):
      `web.zip` = index.html + .js + .wasm + .pck/.png files at the zip root;
      `windows.zip` = the .exe at the zip root.

## 2. Sanity pass before uploading

- [ ] Play the Web build locally once — a browser won't load wasm from `file://`, so serve it:
      `python -m http.server 8000 -d build/web` → http://localhost:8000
- [ ] Full loop: menu → brief → pack → rotate (R **and** right-click) → invalid drop
      shakes + buzzes → send off → log reads correctly → pack again → send again.
- [ ] Audio plays (browsers block audio until the first click — the Play button counts).
- [ ] Quit button is hidden in the Web build, visible on Windows.
- [ ] Window resize / fullscreen: bag and tray stay usable (canvas_items + expand).

## 3. itch.io page

- [ ] Upload `web.zip`, tick **"This file will be played in the browser"**.
- [ ] Viewport: **1280 × 720**, enable the **fullscreen button**. Leave
      "SharedArrayBuffer support" **off** (not needed, single-threaded build).
- [ ] Upload `windows.zip` as a downloadable, platform: Windows.
- [ ] Cover image (630×500) + 3–5 screenshots (pack screen, a mid-log playout, stats bars).
- [ ] Description: one-line pitch, controls (drag / R or right-click to rotate /
      Esc cancels a drag), and "made in 96 hours for GMTK Game Jam 2026".
- [ ] Tags: `gmtk-jam-2026` (check the jam's required tag), plus cozy, puzzle, inventory.
- [ ] Set the page public **before** the jam deadline, then submit the itch URL
      on the jam page (submission is a separate step from publishing!).

## 4. After submitting

- [ ] Open the public page in a private/incognito window and play the whole loop once.
- [ ] Test on one other browser (Chrome + Firefox covers most judges).
- [ ] Lock the uploads until judging ends (no post-deadline edits unless the jam allows).
