# Zombie Survival: Last Day — Godot 4 project

**Status: Phase 1 skeleton. This is a runnable foundation, NOT a finished
game.** It exists so the full loop (menu → level → waves → boss → win/die)
can be tested on a real phone via cloud-built APKs before real art,
animations and content are added.

Engine: **Godot 4.3** (pinned — see CI notes below). Platform: Android,
landscape, Mobile renderer.

## Structure

```
project.godot          Project settings; main scene = scenes/main_menu.tscn
export_presets.cfg     Android export preset (arm64-v8a, package com.zombiesurvival.lastday)
default_bus_layout.tres  Audio buses: Master + Music + SFX
icon.svg               Placeholder icon
scenes/
  main_menu.tscn       Title screen: Play / Offline / Online (disabled) / Settings / Profile
  game.tscn            Dead City block: ground, 6 CSG buildings, sun + environment,
                       navigation region, player spawn, 4 zombie spawn markers, HUD
  player.tscn          CharacterBody3D + capsule placeholder + top-level camera rig
  zombie.tscn          CharacterBody3D + capsule placeholder + NavigationAgent3D
  hud.tscn             Health bar, ammo, weapon name, wave label, message label,
                       virtual joystick, FIRE / RELOAD / SWITCH buttons
scripts/
  main_menu.gd         Menu logic; settings panel (music/SFX bus volumes are real,
                       sensitivity + graphics persist to user://settings.cfg)
  game_manager.gd      Wave spawner: 5 waves, growing counts, boss on the final
                       wave, intermissions, win / death-restart flow
  player.gd            Joystick movement (+ WASD/Space/R for editor testing),
                       health, auto-aim shooting with wall-blocking raycasts,
                       magazine/reserve ammo, reload, weapon switching
  zombie.gd            NavigationAgent3D chase, contact attacks with cooldown,
                       damage + death, boss variant (setup(true): 10x health,
                       1.8x size, slower, double damage)
  weapons.gd           Weapon data: pistol / rifle / shotgun (damage, fire
                       rate, magazine, reload time, range, pellets, auto)
  hud.gd               Binds to the player, forwards joystick/button input,
                       receives wave text + centre messages from the manager
  virtual_joystick.gd  Touch/mouse joystick control with drawn base + knob
assets/                Empty for now (models/textures/audio/fonts) — see assets/README.md
```

## What actually works in this skeleton

- Main menu opens first; Play/Offline loads the level.
- Player moves with the on-screen joystick; zombies spawn at the corner
  markers in waves and pathfind to the player; they damage the player on
  contact; the player auto-aims and shoots the nearest zombie (FIRE button),
  can reload and switch between the three weapons; HUD shows health, ammo,
  weapon and wave/zombie counts.
- Final wave spawns a boss. Clearing all waves shows the win message;
  dying restarts the level.
- Settings sliders change the real Music/SFX bus volumes; the graphics
  Low/High option changes render resolution scale.

## What is placeholder / not done yet

- All visuals are coloured capsules and CSG boxes — no models, animations,
  sounds or music yet (assets/ is empty).
- The navigation mesh is a single flat quad over the whole map, so zombies
  can path through buildings. Proper navmesh baking comes with the real
  level geometry.
- Camera is a fixed-angle follow rig; touch look / free aim is a later step.
- No pickups (ammo/medkit), no weapon upgrade screen, no maps/characters
  screens, no daily reward yet — those are Phase 1 content steps.
- Online mode, lobby and leaderboard are Phase 2 (button disabled on purpose).
- Profile panel is a static placeholder.

## Next steps — GitHub Actions Android export

The user has no PC, so APKs are built in GitHub Actions, same as his other
apps. A workflow (`.github/workflows/build-apk.yml` in the game repo) should:

1. **Pin Godot 4.3** — use the `barichello/godot-ci:4.3` container image, or
   download `Godot_v4.3-stable_linux.x86_64.zip` and
   `Godot_v4.3-stable_export_templates.tpz` from the Godot GitHub releases.
   The editor version and the export templates version MUST match exactly,
   and must match `config/features` in project.godot ("4.3").
2. **Install the export templates** into
   `~/.local/share/godot/export_templates/4.3.stable/` (the godot-ci image
   already has them).
3. **Create a debug keystore** (CI-only signing is fine for test builds):
   `keytool -genkeypair -v -keystore debug.keystore -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`
   then point the preset at it via `keystore/debug` in export_presets.cfg or
   the `GODOT_ANDROID_KEYSTORE_*` environment variables. Release signing
   with real secrets comes later, before any Play Store upload.
4. **Export**: `godot --headless --path game/ --export-debug "Android" out/zombie-survival.apk`
   (run from the repo root; the preset's export_path is relative).
5. **Publish the APK as a release asset**, like the user's other projects,
   and verify the download link before sending it to him. He installs and
   plays it on his phone — only his on-phone confirmation makes a build
   "working", never the CI result alone.

Before the first CI run, open the project once in the Godot 4.3 editor
(any machine) to let it import icon.svg and generate `.godot/` UIDs, and
confirm export_presets.cfg matches the editor's Android preset format.
