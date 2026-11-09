extends SceneTree

const ENGINE_SIM := preload("res://scripts/sim/engine_sim.gd")
const ENGINE_SPEC := preload("res://scripts/sim/engine_spec.gd")
const PRESETS := preload("res://scripts/presets/presets.gd")

func test_zx25r_idle():
    var presets = PRESETS.PRESETS
    if not presets.has("kawasaki_zx25r"):
        print("FAIL: kawasaki_zx25r not found")
        return false
    
    var preset = presets["kawasaki_zx25r"]
    var spec = ENGINE_SPEC.new()
    
    var prop_list = spec.get_property_list()
    var prop_names = []
    for p in prop_list:
        prop_names.append(p.name)
    
    for key in preset:
        if key in prop_names:
            spec.set(key, preset[key])
    
    print("Testing ZX-25R idle stability...")
    print("  Target idle RPM: ", spec.idle_target_rpm)
    print("  Bore x Stroke: ", spec.bore_mm, " x ", spec.stroke_mm)
    print("  Compression: ", spec.compression_ratio)
    print("  Flywheel: ", spec.flywheel_kg, "kg @ ", spec.flywheel_radius_mm, "mm")
    
    var sim = ENGINE_SIM.new()
    
    # Warm up at idle with closed throttle, use starter for first 3 seconds
    print("\n--- Warming up at idle (closed throttle) ---")
    for i in 300:  # 3 seconds with starter
        sim.step(0.01, spec, 0.0, true, true, false, false, 1.0)
        if i % 50 == 0:
            print("  t=%.1fs: RPM=%.1f, Torque=%.3f Nm, Manifold=%.1f kPa, Lambda=%.3f" % [i*0.01, sim.rpm, sim.torque, sim.intake.pressure/1000.0, sim.o2_lambda()])
    
    print("\n--- Continuing warmup without starter ---")
    for i in 1700:  # 17 more seconds
        sim.step(0.01, spec, 0.0, true, false, false, false, 1.0)
        if i % 200 == 0:
            print("  t=%.1fs: RPM=%.1f, Torque=%.3f Nm, Manifold=%.1f kPa, Lambda=%.3f" % [(i+300)*0.01, sim.rpm, sim.torque, sim.intake.pressure/1000.0, sim.o2_lambda()])
    
    print("\n--- Testing stability at target idle RPM ---")
    var rpm_sum = 0.0
    var rpm_count = 0
    var max_deviation = 0.0
    
    for i in 1000:  # 10 seconds
        sim.step(0.01, spec, 0.0, true, false, false, false, 1.0)
        var deviation = abs(sim.rpm - spec.idle_target_rpm)
        max_deviation = max(max_deviation, deviation)
        rpm_sum += sim.rpm
        rpm_count += 1
    
    var avg_rpm = rpm_sum / rpm_count
    print("Average RPM: %.1f (target: %.1f)" % [avg_rpm, spec.idle_target_rpm])
    print("Max deviation: %.1f RPM" % max_deviation)
    print("Final torque: %.3f Nm" % sim.torque)
    print("Manifold pressure: %.1f kPa" % (sim.intake.pressure/1000.0))
    print("Lambda: %.3f" % sim.o2_lambda())
    
    # Check if stable (within 50 RPM of target)
    if max_deviation < 50.0:
        print("\n✓ IDLE STABLE")
        return true
    else:
        print("\n✗ IDLE UNSTABLE - max deviation %.1f RPM" % max_deviation)
        return false

func _init():
    var ok = test_zx25r_idle()
    if not ok:
        quit(1)
    quit()