# Third-party material

## KALIPER 3D model

[KALIPER](https://sketchfab.com/3d-models/kaliper-a381d3f640b34dbf8ec48b01f16dc222) by [nika23](https://sketchfab.com/nika2022), licensed under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). Original: `assets/3d/imported/kaliper_nika23.glb`. A modified, decimated version with separate promotional text removed is retained as `kaliper_nika23_mobile.glb`. The game's `caliper_simple.glb` was recreated as a simplified model using KALIPER as a visual reference. See `tools/diagnostics/prepare_caliper_asset.py` and `create_simple_caliper.py`.

## engine-sim impulse responses
These exhaust impulse responses are from engine-sim, copyright 2022 Ange Yaghi (AngeTheGreat),
released under the MIT licence. The licence text is in the engine-sim project's LICENSE file.

- `assets/ir/mild_exhaust.wav` (`es/sound-library/new/mild_exhaust.wav`) colors a muffled tailpipe in `scripts/audio/engine_sound.gd`.
- `assets/ir/sharp_01.wav` (`es/sound-library/sharp/sharp_01.wav`) colors an open pipe.
- `assets/ir/minimal_muffling_03.wav` (`es/sound-library/new/minimal_muffling_03.wav`) is an alternate response kept in the tree.

The playback chain in `engine_sound.gd` (DC removal, flow-shaped noise, a little pulse edge, then convolution) follows engine-sim's synthesizer. The gas in the pipes is this project's own solver.
