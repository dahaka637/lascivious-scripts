# Integration Notes - Evil Morty Death Screen

- `module_key`: `evil-morty-death-screen`
- `bundled_mod_id`: `LS_EvilMortyDeathScreen`
- Workshop item `3773191030`, upstream `id=EvilMortyDeathScreen`, `modversion=1.0.0`,
  `versionMin=42.13`.

## Function

Changes the post-death UI into a cinematic pull-back with fade to black and plays
`EvilMortyDeathTheme` once when the local player dies.

The module is client-side only for behavior. It ships one Lua file, one sound script and one OGG
asset. It has no server commands, client commands, sandbox options, items, recipes, traits, perks,
vehicles, Java/JAR, maps, tiledefs, packs, `modData` or `GlobalModData`.

## Inventory and Gate

- Build 42 compatible and integrated for 42.20.x.
- No dependencies or incompatible declarations.
- No checks of the original Mod ID, so the bundled rename is safe.
- No save-sensitive identifiers.
- The upstream root/common duplicate `mod.info`/`icon.png`/`poster.png` packaging was not shipped;
  the functional Build 42 folder is preserved in the pristine snapshot and bundled submod.

## Local Audio Fix

User reports on the Workshop mentioned buzzing/glitching music when the player burns to death. The
likely culprit in the upstream is the combination of:

- declaring the theme as `category = Music` / `master = Music`;
- playing it through `getSoundManager():playUISound()`;
- calling `StopMusic()` every second while the death screen is active;
- making the theme 3D and repeatedly moving the UI emitter to the corpse/player.

The bundled copy keeps the same theme and timing, but changes the sound script to `category = UI`,
`is3D = false`, removes the recurring music-stop loop, and only stops vanilla music once when death
starts. This avoids fighting the music manager while the custom theme is already playing.

## Collision Review

The module wraps `ISPostDeathUI:prerender`, `:onMouseWheel`, `:onExit`, `:onRespawn` and
`:onConfirmQuitToDesktop`. The bundled copy adds an idempotency guard and makes `onMouseWheel` call
through to the captured implementation when the death-screen effect is not active.

No existing bundled module patches `ISPostDeathUI`. Several modules listen to `Events.OnPlayerDeath`
for cleanup/UI state, but all listeners are additive and no listener removes or replaces another.

## Remaining Risk

This could not be tested in-engine here, so the audio fix is a static mitigation based on the code
path and the reported symptom. The most important runtime check is death by fire: the theme should
play once, without buzzing, and stop cleanly on respawn/exit/main menu.
