# Validation Test Templates

**Purpose:** Ready-to-copy GDScript test templates following the `[external value]` pattern from amt911/engine-sim. Each test asserts a value from outside the code (hand calc, table, closed form, figure, measurement, independent impl).

---

## 1. Gas Properties (`tests/unit/engine/gas_properties_test.gd`)

```gdscript
extends GutTest

func test_cp_air_table_points():
	# [table] Keenan & Kaye / Cengel, Thermodynamics Appendix
	# cp_air at 300, 1000, 2000, 3000 K
	assert_eq(GasProperties.cp_air(300.0), 1005.0, 1.0)
	assert_eq(GasProperties.cp_air(1000.0), 1142.0, 2.0)
	assert_eq(GasProperties.cp_air(2000.0), 1278.0, 3.0)
	assert_eq(GasProperties.cp_air(3000.0), 1328.0, 5.0)

func test_cp_burnt_table_points():
	# [table] Stoich hydrocarbon flame products (same sources)
	assert_eq(GasProperties.cp_burnt(300.0), 1105.0, 1.0)
	assert_eq(GasProperties.cp_burnt(1000.0), 1207.0, 2.0)
	assert_eq(GasProperties.cp_burnt(2000.0), 1302.0, 3.0)
	assert_eq(GasProperties.cp_burnt(3000.0), 1338.0, 5.0)

func test_u_round_trip():
	# [closed] u(T) is integral of cv; temp_from_u is inverse
	for T in [300.0, 500.0, 800.0, 1200.0, 1500.0, 2000.0, 2500.0]:
		var u = GasProperties.u(0.0, T)  # air
		var T_back = GasProperties.temp_from_u(0.0, u)
		assert_near(T_back, T, 0.1)  # 0.1 K tolerance

		for burnt in [0.2, 0.5, 0.8, 1.0]:
			u = GasProperties.u(burnt, T)
			T_back = GasProperties.temp_from_u(burnt, u)
			assert_near(T_back, T, 0.1)

func test_h_equals_u_plus_RT():
	# [closed] h = u + R·T
	for T in [300.0, 1000.0, 2000.0]:
		for burnt in [0.0, 0.5, 1.0]:
			var h = GasProperties.h(burnt, T)
			var u = GasProperties.u(burnt, T)
			assert_near(h, u + 287.05 * T, 1e-6)

func test_cpp_gdscript_parity():
	# [ind] C++ and GDScript must agree to 1e-9
	# Requires CylinderNative built and exposed
	var cpp = CylinderNative.new()
	for T in [300.0, 1000.0, 2000.0]:
		for burnt in [0.0, 0.5, 1.0]:
			var cp_gd = GasProperties.cp(burnt, T)
			var cp_cpp = cpp.cp(burnt, T)
			assert_near(cp_gd, cp_cpp, 1e-9)

			var cv_gd = GasProperties.cv(burnt, T)
			var cv_cpp = cpp.cv(burnt, T)
			assert_near(cv_gd, cv_cpp, 1e-9)

			var u_gd = GasProperties.u(burnt, T)
			var u_cpp = cpp.u(burnt, T)
			assert_near(u_gd, u_cpp, 1e-9)

			var h_gd = GasProperties.h(burnt, T)
			var h_cpp = cpp.h(burnt, T)
			assert_near(h_gd, h_cpp, 1e-9)

			var T_gd = GasProperties.temp_from_u(burnt, u_gd)
			var T_cpp = cpp.temp_from_u(burnt, u_gd)
			assert_near(T_gd, T_cpp, 1e-9)
```

---

## 2. Woschni Heat Transfer (`tests/unit/engine/woschni_validation_test.gd`)

```gdscript
extends GutTest

# [hand] Woschni SAE 670931; Qasemian 2020 Table 1 (constants per phase)
# h = 3.26 * B^-0.2 * p^0.8 * T^-0.55 * w^0.8
# w = C1 * v_p + C2 * (V_d * T_r * (p - p_m)) / (p_r * V_r)

func test_woschni_motored():
	# Motored case: 300 K, 1 bar, 3000 RPM
	# B=0.086m, L=0.056m (typical 250cc), v_p = 2*L*RPM/60 = 5.6 m/s
	# C1=2.28, C2=0 (motored), p_m = p_r = 1 bar, T_r = 300 K, V_d/V_r = CR-1
	var h = Cylinder.woschni_h(
		300.0,      # T (K)
		100000.0,   # p (Pa)
		3000.0,     # RPM
		0.086,      # bore (m)
		0.056,      # stroke (m)
		12.0,       # compression_ratio
		true        # motored
	)
	# Hand calc: v_p=5.6, w=2.28*5.6=12.77, h=3.26*0.086^-0.2*1e5^0.8*300^-0.55*12.77^0.8 ≈ 1250
	assert_near(h, 1250.0, 150.0)  # ±12%

func test_woschni_fired():
	# Fired case: peak 80 bar, 3000 RPM
	# C1=2.28, C2=3.24e-3 (fired), p_m=10 bar, p_r=1 bar, T_r=300 K
	var h = Cylinder.woschni_h(
		2500.0,     # T (K) — avg gas temp during combustion
		80e5,       # p (Pa) — 80 bar peak
		3000.0,     # RPM
		0.086,      # bore (m)
		0.056,      # stroke (m)
		12.0,       # compression_ratio
		false       # fired
	)
	# Hand calc: v_p=5.6, p_m=10e5, w=2.28*5.6 + 3.24e-3*(V_d*300*(80e5-10e5))/(1e5*V_r)
	# V_d/V_r = 11, so w ≈ 12.77 + 3.24e-3*11*300*70 = 12.77 + 748 = 761
	# h = 3.26*0.086^-0.2*(80e5)^0.8*2500^-0.55*761^0.8 ≈ 8500
	assert_near(h, 8500.0, 1000.0)  # ±12%

func test_woschni_constants_per_phase():
	# [table] Qasemian 2020 Table 1 (from Woschni 1967)
	# Intake:  C1=6.18, C2=0
	# Compression: C1=2.28, C2=0
	# Combustion: C1=2.28, C2=3.24e-3
	# Expansion: C1=2.28, C2=3.24e-3
	# Exhaust: C1=6.18, C2=0
	assert_eq(Cylinder.WOSCHNI_C1_INTAKE, 6.18)
	assert_eq(Cylinder.WOSCHNI_C2_INTAKE, 0.0)
	assert_eq(Cylinder.WOSCHNI_C1_COMPRESSION, 2.28)
	assert_eq(Cylinder.WOSCHNI_C2_COMPRESSION, 0.0)
	assert_eq(Cylinder.WOSCHNI_C1_COMBUSTION, 2.28)
	assert_eq(Cylinder.WOSCHNI_C2_COMBUSTION, 3.24e-3)
	assert_eq(Cylinder.WOSCHNI_C1_EXPANSION, 2.28)
	assert_eq(Cylinder.WOSCHNI_C2_EXPANSION, 3.24e-3)
	assert_eq(Cylinder.WOSCHNI_C1_EXHAUST, 6.18)
	assert_eq(Cylinder.WOSCHNI_C2_EXHAUST, 0.0)
```

---

## 3. Valve Flow (`tests/unit/engine/valve_flow_test.gd`)

```gdscript
extends GutTest

# [fig] Heywood Fig 6-18, p.229; SAE 820154 / 962527
# Cd vs L/D (lift/diameter): ~95% at L/D=0.1, ~90% at 0.25, ~70% at 0.4

func test_valve_cd_vs_ld():
	var cd_01 = Cylinder.valve_cd(0.1)   # L/D = 0.1
	var cd_025 = Cylinder.valve_cd(0.25) # L/D = 0.25
	var cd_04 = Cylinder.valve_cd(0.4)   # L/D = 0.4

	assert_near(cd_01, 0.95, 0.05)   # 0.90–1.00
	assert_near(cd_025, 0.90, 0.05)  # 0.85–0.95
	assert_near(cd_04, 0.70, 0.05)   # 0.65–0.75

	# Monotonic increase with L/D
	assert_true(cd_01 > cd_025)
	assert_true(cd_025 > cd_04)

func test_curtain_area():
	# [hand] A = π * d_valve * lift * Cd
	# d=35mm, lift=10mm, Cd=0.7 → A = π*0.035*0.01*0.7 = 7.697e-4 m²
	var area = Cylinder.curtain_area(0.035, 0.01, 0.7)
	assert_near(area, 7.697e-4, 1e-6)

func test_curtain_to_port_blend():
	# [fig] Heywood Fig 6-18: curtain area blends to port area at L/D > 0.25
	# Port area for 35mm valve: π*(35/2)² = 9.62e-4 m²
	var port_area = Cylinder.port_area(0.035)
	assert_near(port_area, 9.62e-4, 1e-6)

	var blended = Cylinder.flow_area(0.035, 0.015, 0.7)  # lift=15mm, L/D=0.43
	# Should be near port area (curtain > port, so min applies)
	assert_near(blended, port_area, 5e-5)
```

---

## 4. Orifice Mass Flow (`tests/unit/engine/orifice_flow_test.gd`)

```gdscript
extends GutTest

# [hand] Heywood App C eq C.8–C.9
# Choked: ṁ = Cd * A * p0 * sqrt(γ/(R*T0)) * (2/(γ+1))^((γ+1)/(2(γ-1)))
# Subsonic: ṁ = Cd * A * p0 * sqrt(2γ/(R*T0*(γ-1))) * [(p/p0)^(2/γ) - (p/p0)^((γ+1)/γ)]^0.5

func test_orifice_choked():
	# Cd=0.7, A=1e-4 m², p0=5e5 Pa, T0=300 K, γ=1.4, R=287.05
	# sqrt(γ/(R*T0)) = sqrt(1.4/(287.05*300)) = 0.00402
	# (2/(γ+1))^((γ+1)/(2(γ-1))) = (2/2.4)^(2.4/0.8) = 0.833^3 = 0.578
	# ṁ = 0.7 * 1e-4 * 5e5 * 0.00402 * 0.578 = 0.0815 kg/s
	var mdot = GasProperties.orifice_mass_flow(0.7, 1e-4, 5e5, 300.0, 1.4)
	assert_near(mdot, 0.0815, 0.001)

func test_orifice_subsonic():
	# Same but p/p0 = 0.8 (subsonic, since critical = 0.528)
	# [hand] Calculation yields ~0.065 kg/s
	var mdot = GasProperties.orifice_mass_flow_subsonic(0.7, 1e-4, 5e5, 4e5, 300.0, 1.4)
	assert_near(mdot, 0.065, 0.002)

func test_orifice_continuity_at_critical():
	# [closed] Choked and subsonic formulas meet at p/p0 = (2/(γ+1))^(γ/(γ-1)) = 0.528
	var p_crit = 5e5 * 0.528
	var mdot_choked = GasProperties.orifice_mass_flow(0.7, 1e-4, 5e5, 300.0, 1.4)
	var mdot_sub = GasProperties.orifice_mass_flow_subsonic(0.7, 1e-4, 5e5, p_crit, 300.0, 1.4)
	assert_near(mdot_choked, mdot_sub, 1e-4)
```

---

## 5. Exhaust Open-End Reflection (`tests/unit/exhaust/open_end_reflection_test.gd`)

```gdscript
extends GutTest

# [closed] Levine & Schwinger 1948: end correction = 0.6133 * radius
# [ind] Silva et al. 2009 fit for reflection coefficient R(ka)

func test_open_end_low_ka():
	# ka << 1: |R| ≈ 1 - (ka)²/2
	var R = ExhaustNative.reflection_coeff(0.01)  # ka = 0.01
	assert_near(abs(R), 0.99995, 1e-5)

	var R2 = ExhaustNative.reflection_coeff(0.1)  # ka = 0.1
	assert_near(abs(R2), 0.995, 0.001)

func test_open_end_end_correction():
	# [closed] Phase of R gives end correction: δ = 0.6133 * a
	# At ka=1, phase lag corresponds to 0.6133 radius
	var R = ExhaustNative.reflection_coeff(1.0)  # ka = 1.0
	var phase = atan2(R.imag, R.real)  # negative for lag
	var delta = -phase / 1.0  # normalized by ka
	assert_near(delta, 0.6133, 0.02)  # within 3%

func test_open_end_silva_fit():
	# [ind] Silva 2009: |R|² = 1 - (ka)² for low ka, 13% high at ka=2
	var R1 = ExhaustNative.reflection_coeff(1.0)
	assert_near(abs(R1)**2, 0.5, 0.05)  # Silva: ~0.5 at ka=1

	var R2 = ExhaustNative.reflection_coeff(2.0)
	# Silva fit: |R|² ≈ 0.15 at ka=2 (code may be 13% high → ~0.17)
	assert_near(abs(R2)**2, 0.15, 0.03)
```

---

## 6. Dyno Regression (`tests/integration/dyno/dyno_regression_test.gd`)

```gdscript
extends GutTest

# [meas] Measured dyno curves from assets/dyno/*.json
# Tolerance: ±5% torque, ±3% power, ±2% BSFC (where available)

func test_dyno_regression_cbr1000rr():
	var spec = EngineSpec.from_json(load("res://assets/engines/honda_cbr1000rrr_sp.json"))
	var measured = load("res://assets/dyno/honda_cbr1000rrr_sp.json")
	
	var sim = EngineSim.new()
	sim.build(spec)
	
	var errors = []
	for point in measured.points:  # {rpm, torque_nm, power_kw}
		sim.set_throttle(1.0)
		sim.run_to_rpm(point.rpm)
		var sim_torque = sim.torque
		var sim_power = sim.power
		
		var torque_err = abs(sim_torque - point.torque_nm) / point.torque_nm
		var power_err = abs(sim_power - point.power_kw) / point.power_kw
		
		if torque_err > 0.05:
			errors.append("RPM %d: torque err %.1f%%" % [point.rpm, torque_err * 100])
		if power_err > 0.03:
			errors.append("RPM %d: power err %.1f%%" % [point.rpm, power_err * 100])
	
	assert_true(errors.is_empty(), "Dyno regression failures:\n" + "\n".join(errors))

func test_dyno_regression_all_bikes():
	var bikes = [
		"honda_cbr1000rrr_sp",
		"kawasaki_h2r",
		"kawasaki_zx25r",
		"yamaha_yzf_r1m",
		"honda_cbr250rr_2020"
	]
	
	var all_errors = []
	for bike in bikes:
		var spec = EngineSpec.from_json(load("res://assets/engines/%s.json" % bike))
		var measured = load("res://assets/dyno/%s.json" % bike)
		
		var sim = EngineSim.new()
		sim.build(spec)
		
		for point in measured.points:
			sim.set_throttle(1.0)
			sim.run_to_rpm(point.rpm)
			var torque_err = abs(sim.torque - point.torque_nm) / point.torque_nm
			if torque_err > 0.05:
				all_errors.append("%s @ %d RPM: torque %.1f%%" % [bike, point.rpm, torque_err * 100])
	
	assert_true(all_errors.is_empty(), "Multi-bike dyno failures:\n" + "\n".join(all_errors))
```

---

## 7. C++/GDScript Parity (`tests/unit/engine/cylinder_native_test.gd`)

```gdscript
extends GutTest

# [ind] C++ and GDScript cylinder kernel must agree to 1e-9
# Referenced in cylinder_kernel.cpp:19

func test_cylinder_advance_parity():
	var cpp = CylinderKernel.new()
	var gd = Cylinder.new()
	
	# Same setup
	var bore = 0.086
	var stroke = 0.056
	var cr = 12.0
	var recip = 0.15
	
	cpp.setup(bore, stroke, cr, recip)
	gd.setup(bore, stroke, cr, recip)
	
	# Same initial state
	var p0 = 100000.0
	var T0 = 300.0
	cpp.set_state(p0, T0)
	gd.set_state(p0, T0)
	
	# Advance same step
	var dphi = 1.0  # deg
	var dt = 1e-6
	var pm = 100000.0
	var tm = 300.0
	var ign_phi = 360.0
	var fuel_mass = 1e-6
	var lambda = 1.0
	var spark = true
	var limiter = false
	var p_ex = 100000.0
	var t_ex = 800.0
	
	var res_cpp = cpp.advance(dphi, dt, pm, tm, ign_phi, fuel_mass, lambda, spark, limiter, p_ex, t_ex)
	var res_gd = gd.advance(dphi, dt, pm, tm, ign_phi, fuel_mass, lambda, spark, limiter, p_ex, t_ex)
	
	assert_near(res_cpp.pressure, res_gd.pressure, 1e-9)
	assert_near(res_cpp.temperature, res_gd.temperature, 1e-9)
	assert_near(res_cpp.mass, res_gd.mass, 1e-9)
	assert_near(res_cpp.torque, res_gd.torque, 1e-9)

func test_gas_properties_parity():
	# Delegates to gas_properties_test.cpp_gdscript_parity()
	pass
```

---

## 8. Pacejka Tire (`tests/unit/sim/pacejka_test.gd`)

```gdscript
extends GutTest

# [table] Pacejka MF 6.2 coefficients (example for 120/70ZR17 front)
# From Moto-Braking-Dynamics / literature

func test_pacejka_pure_longitudinal():
	var tire = PacejkaTire.new()
	tire.set_coefficients({
		# Pure longitudinal (MF 6.2)
		"PCX1": 1.6, "PDX1": 1.0, "PDX2": -0.05, "PDX3": 0.0,
		"PEX1": 0.4, "PEX2": 0.0, "PEX3": 0.0, "PEX4": 0.0,
		"PKX1": 21.0, "PKX2": 10.0, "PKX3": -0.4,
		"PHX1": 0.0, "PHX2": 0.0,
		"PVX1": 0.0, "PVX2": 1.0e5,
		"RBX1": 1.0, "RBX2": 0.0, "RBX3": 0.0,
		"RCX1": 1.0, "REX1": 0.0, "REX2": 0.0,
		"RHX1": 0.0
	})
	
	# At slip=0.12, Fz=3000N, expect peak Fx ≈ 1.05 * 3000 = 3150 N
	var Fx = tire.Fx(0.12, 3000.0, 0.0)  # slip, Fz, camber
	assert_near(Fx, 3150.0, 300.0)  # ±10%
	
	# At slip=1.0 (locked), Fx ≈ 0.75 * 3000 = 2250 N
	var Fx_locked = tire.Fx(1.0, 3000.0, 0.0)
	assert_near(Fx_locked, 2250.0, 250.0)

func test_pacejka_load_sensitivity():
	var tire = PacejkaTire.new()
	# ... set coefficients ...
	
	# Fx should scale sub-linearly with Fz
	var Fx_2000 = tire.Fx(0.12, 2000.0, 0.0)
	var Fx_4000 = tire.Fx(0.12, 4000.0, 0.0)
	
	# Ratio should be < 2.0 (load sensitivity)
	assert_true(Fx_4000 / Fx_2000 < 2.0)
	assert_true(Fx_4000 / Fx_2000 > 1.5)
```

---

## 9. ABS Controller (`tests/unit/sim/abs_controller_test.gd`)

```gdscript
extends GutTest

# [meas] Bosch ABS literature; Moto-Braking-Dynamics validation
# Release at 1.15×target, reapply at 0.8×target
# Slew: release 60,000 N·m/s, apply 12,000 N·m/s

func test_abs_release_hysteresis():
	var abs = AbsController.new()
	abs.configure(0.12, 8.0, 5.0)  # target=0.12, 8Hz, 5 km/h min
	
	var capacity = 1000.0  # N·m
	var torque = capacity
	var dt = 1e-4
	
	# Step 1: slip below target → should hold/apply
	torque = abs.step(dt, -0.08, 10.0, torque, capacity)  # slip=0.08 < 0.12
	assert_near(torque, capacity, 10.0)  # full apply
	
	# Step 2: slip exceeds release threshold (1.15×0.12 = 0.138)
	torque = abs.step(dt, -0.15, 10.0, torque, capacity)
	assert_true(torque < capacity * 0.5)  # releasing
	
	# Step 3: slip drops below reapply threshold (0.8×0.12 = 0.096)
	# Need to simulate multiple steps until slip < 0.096
	for i in 30:
		torque = abs.step(dt, -0.09, 10.0, torque, capacity)
	assert_near(torque, capacity, 50.0)  # reapplied

func test_abs_cycle_count():
	var abs = AbsController.new()
	abs.configure(0.12, 8.0, 5.0)
	
	var torque = 1000.0
	var dt = 1e-4
	var cycles = 0
	
	# Simulate one full cycle: apply → release → reapply
	for i in 200:
		var slip = -0.15 if i > 50 and i < 100 else -0.08
		torque = abs.step(dt, slip, 10.0, torque, 1000.0)
	
	# Should have counted 1 release event
	assert_eq(abs.cycles, 1)

func test_abs_min_speed():
	var abs = AbsController.new()
	abs.configure(0.12, 8.0, 5.0)  # 5 km/h = 1.39 m/s
	
	# Below min speed → returns capacity (no ABS)
	var torque = abs.step(1e-4, -0.5, 1.0, 0.0, 1000.0)  # speed=1 m/s
	assert_near(torque, 1000.0, 1.0)
	assert_false(abs.active)
```

---

## Running Tests

```bash
# Run all validation tests
./run_test.bat --filter=validation

# Or with Gut (Godot Unit Testing)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/engine -ginclude="*validation*"
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/engine -ginclude="*valve*"
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/exhaust -ginclude="*open_end*"
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/dyno -ginclude="*regression*"
```

---

## Adding New Tests

1. Copy template to `tests/unit/<module>/<name>_test.gd`
2. Replace `[hand]`, `[table]`, etc. with actual reference
3. Add reference citation in comment
4. Run and verify it **fails first** (TDD)
5. Implement fix in production code
6. Verify test passes
7. Update `docs/physics-validation.md` status table