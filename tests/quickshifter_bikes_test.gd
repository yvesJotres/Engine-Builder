extends SceneTree

const ENGINE_SIM := preload("res://scripts/engine/engine_sim.gd")
const ENGINE_SPEC := preload("res://scripts/engine/engine_spec.gd")
const DYNO_TEST := preload("res://scripts/dyno/dyno_test.gd")
const PRESETS := preload("res://scripts/engine/presets.gd")

func test_bike(bike_id: String):
    var presets = PRESETS.PRESETS
    if not presets.has(bike_id):
        print("FAIL: ", bike_id, " not found")
        return false
    
    var preset = presets[bike_id]
    var spec = ENGINE_SPEC.new()
    
    var prop_list = spec.get_property_list()
    var prop_names = []
    for p in prop_list:
        prop_names.append(p.name)
    
    for key in preset:
        if key in prop_names:
            spec.set(key, preset[key])
    
    print("Testing: ", bike_id, " (", spec.cylinders, " cyl, ", spec.displacement_cc, " cc)")
    print("  QS: has=", spec.has_quickshifter, " enabled=", spec.quickshifter, " cut=", spec.quickshifter_cut_time, " min_rpm=", spec.quickshifter_min_rpm)
    
    # Quick check: run sim for a few frames to verify no crashes
    var sim = ENGINE_SIM.new()
    sim.clutch_pull = 0.0
    for i in 50:
        sim.step(1.0/120.0, spec, 1.0, true, false, false, false, 1.0)
    
    # Run quick dyno
    var dyno = DYNO_TEST.new()
    dyno.max_gears = spec.gear_ratios.size()
    dyno.start(spec, sim)
    
    var frame = 0
    while dyno.active() and frame < 30000:
        dyno.advance(1.0/120.0, sim, spec, 1.0, true)
        frame += 1
    
    var result = dyno.result()
    print("  Status: ", result.status)
    print("  Peak Torque: ", result.peak_torque.torque, " Nm @ ", result.peak_torque.rpm, " RPM")
    print("  Peak Power: ", result.peak_hp.hp, " HP @ ", result.peak_hp.rpm, " RPM")
    print("  Gears tested: ", result.gears.size())
    for g in result.gears:
        print("    Gear ", g.gear, ": ", g.torque, " Nm @ ", g.torque_rpm, " RPM | ", g.hp, " HP @ ", g.hp_rpm, " RPM")
    
    return result.ok

func _init():
    var bikes = ["ducati_panigale_v4", "yamaha_yzf_r1m", "yamaha_mt07", "kawasaki_zx25r", "kawasaki_zx25r_se"]
    var all_pass = true
    
    for bike in bikes:
        var ok = test_bike(bike)
        if not ok:
            print("FAIL: ", bike)
            all_pass = false
        else:
            print("PASS: ", bike)
        print("")
    
    if all_pass:
        print("ALL BIKES PASSED")
    else:
        print("SOME BIKES FAILED")
    quit()