# Asset sources

This file records third-party source material shipped in the repository. The
game does not contain extracted Counter-Strike or Valve audio.

## Combat audio samples

All files below were downloaded on 2026-08-03 and converted with FFmpeg to
mono, 44.1 kHz Ogg Vorbis. Weapon recordings were cropped into individual
events, high-pass filtered, loudness-normalized to -16/-15 LUFS with a -1 dBTP
ceiling, and given short tail fades. Foley was normalized to -19 LUFS/-2 dBTP;
surface sounds were normalized to -21 LUFS/-2 dBTP. These transformations are
permitted by CC0.

License for every entry: [Creative Commons Zero 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

### Gunshot Sounds

- Work: **Gunshot Sounds**
- Author/uploader: **Tabasco**; embedded recording metadata credits Vince Sevedge
- Original page: https://opengameart.org/content/gunshot-sounds
- Original archive: https://opengameart.org/sites/default/files/sounds.zip
- Page license declaration: CC0
- Derived files:
  - `assets/audio/weapons/pistol_fire_01.ogg` — crop from `cz.wav`
  - `assets/audio/weapons/pistol_fire_02.ogg` — crop from `cz.wav`
  - `assets/audio/weapons/rifle_fire_01.ogg` — crop from `sks.wav`
  - `assets/audio/weapons/rifle_fire_02.ogg` — crop from `sks.wav`

### Gun reload sounds

- Work: **Gun reload sounds**
- Author: **SpringySpringo**
- Original page: https://opengameart.org/content/gun-reload-sounds
- Original files:
  - https://opengameart.org/sites/default/files/assaultriflereload1_0.wav
  - https://opengameart.org/sites/default/files/gunreload1.wav
- Page license declaration: CC0; attribution optional and appreciated
- Derived files:
  - `assets/audio/foley/rifle_reload.ogg`
  - `assets/audio/foley/pistol_reload.ogg`

### 100 CC0 SFX #2

- Work: **100 CC0 SFX #2**
- Author: **rubberduck**
- Original page: https://opengameart.org/content/100-cc0-sfx-2
- Original archive: https://opengameart.org/sites/default/files/sfx_100_v2.zip
- Page license declaration: CC0
- Derived files:
  - `assets/audio/footsteps/concrete_01.ogg` from `sfx100v2_footstep_01.ogg`
  - `assets/audio/footsteps/concrete_02.ogg` from `sfx100v2_footstep_02.ogg`
  - `assets/audio/footsteps/water_01.ogg` from `sfx100v2_footstep_wet_01.ogg`
  - `assets/audio/footsteps/water_02.ogg` from `sfx100v2_footstep_wet_02.ogg`
  - `assets/audio/footsteps/wood_01.ogg` from `sfx100v2_footstep_wood_01.ogg`
  - `assets/audio/footsteps/wood_02.ogg` from `sfx100v2_footstep_wood_02.ogg`
  - `assets/audio/footsteps/metal_01.ogg` from `sfx100v2_metal_01.ogg`
  - `assets/audio/footsteps/metal_02.ogg` from `sfx100v2_metal_02.ogg`

The metal recordings are used as short hard-surface shoe/landing accents rather
than represented as a specific brand or object.
