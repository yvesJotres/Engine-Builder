# Custom 3D parts

Procedural 3D generators are in `assets/3d/generated/`, grouped by drawing, drivetrain, dyno, exhaust and fuel. Imported models use `assets/models/` as described below. Simulation and physics remain in `scripts/`.

Tank shells can be supplied per motorcycle as `assets/models/<preset_id>/tank.glb` in the Godot source project. For example, the 2017 CBR250RR uses `assets/models/honda_cbr250rr/tank.glb`. Import the file through the Godot editor before running or exporting the project.

The GLB must have a 3D scene root. It replaces only the red tank shell; the existing filler cap, outlet, fuel lines and level gauge remain. Model the shell without these parts. Axes are X across the bike, Y up and Z along the bike. One scene unit is 10 cm. Use the existing shell's center as origin, and leave the size and alignment compatible with its approximately 2.3 × 1.45 × 3.6 scene-unit bounding box. The game scales the whole tank by the existing capacity factor and positions it above the engine. Real tank shapes are not cubes; these dimensions are alignment guidance, not a target outline.

Missing or invalid assets fall back to the generated shell. This attachment point does not automatically fit or collision-test an imported shape against each engine. Verify clearance in the source game at every intended engine configuration.

Optional `front_rim.glb` and `rear_rim.glb` in the same per-preset directory replace the rim, spokes and hub. They are attached to the rotating wheel; the generated tyre, brake rotor and ABS ring remain separate. Model each rim around the origin, with its axle along X and Y/Z in the wheel plane, in scene units (10 cm each). Match the configured rim size and width; imported rims are not resized automatically. Missing or invalid rims fall back to the generated parts.

Optional `front_rotor.glb` and `rear_rotor.glb` replace the generated disc, carrier and bolts. Place the model origin at the axle center, with the disc in the Y/Z plane and axle along X; the game moves it to the existing disc plane. ABS tone rings and sensors stay separate. The replacement must fit the existing caliper and sensor geometry.

Optional `muffler_stock.glb`, `muffler_sport.glb`, and `muffler_short.glb` replace the matching muffler body when that option is selected. Place the inlet at the origin, extending along local +Y; the game attaches it to the generated pipe and rotates it toward the tail. Model it to match the selected layout length and radius. The generated connecting pipes and clamps remain, and the visual asset does not change exhaust physics or audio. Two-stroke expansion chambers have no muffler slot.

No OEM models are included. The game does not yet offer an in-game file picker, automated fitting, clipping checks or authored caliper replacements.
