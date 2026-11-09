extends SceneTree

const ENGINE_SIM := preload("res://scripts/engine/engine_sim.gd")
const ENGINE_SPEC := preload("res://scripts/engine/engine_spec.gd")
const PRESETS := preload("res://scripts/engine/presets.gd")

func test_zx25r_idle_detailed():
    var presets = PRESETS.PRESETS
    var preset = presets["kawasaki_zx25r"]
    var spec = ENGINE_SPEC.new()
    
    var prop_list = spec.get_property_list()
    var prop_names = []
    for p in prop_list:
        prop_names.append(p.name)
    
    for key in preset:
        if key in prop_names:
            spec.set(key, preset[key])
    
    print("Testing ZX-25R idle - detailed ECU diagnostics...")
    print("  Target idle RPM: ", spec.idle_target_rpm)
    print("  Bore x Stroke: ", spec.bore_mm, " x ", spec.stroke_mm)
    print("  Displacement: ", spec.displacement_cc, " cc")
    
    var sim = ENGINE_SIM.new()
    
    # Start with starter for 3 seconds
    print("\n--- Starting with starter (3s) ---")
    for i in 300:
        sim.step(0.01, spec, 0.0, true, true, false, false, 1.0)
        if i % 50 == 0:
            var ecu = sim.ecu
            print("  t=%.1fs: RPM=%.1f, Trim=%.2f, AirFactor=%.3f, BypassArea=%.2e, IntakeP=%.1fkPa" % [
                i*0.01, sim.rpm, ecu.trim, ecu.air_factor(), sim.intake.bypass_area, sim.intake.pressure/1000.0
            ])
    
    print("\n--- Warmup without starter (10s) ---")
    for i in 1000:
        sim.step(0.01, spec, 0.0, true, false, false, false, 1.0)
        if i % 200 == 0:
            var ecu = sim.ecu
            print("  t=%.1fs: RPM=%.1f, Trim=%.2f, AirFactor=%.3f, Overrun=%s, Throttle=%.3f" % [
                (i+300)*0.01, sim.rpm, ecu.trim, ecu.air_factor(), ecu.overrun(), 0.0
            ])
    
    print("\n--- Idle stability test (10s) ---")
    var rpm_sum = 0.0
    var rpm_count = 0
    var max_dev = 0.0
    
    for i in 1000:
        sim.step(0.01, spec, 0.0, true, false, false, false, 1.0)
        if i % 200 == 0:
            var ecu = sim.ecu
            print("  t=%.1fs: RPM=%.1f, Trim=%.2f, AirFactor=%.3f, TargetRPM=%.0f, Overrun=%s" % [
                (i+1300)*0.01, sim.rpm, ecu.trim, ecu.air_factor(), ecu.target_rpm, ecu.overrun()
            ])
        var dev = abs(sim.rpm - spec.idle_target_rpm)
        max_dev = max(max_dev, dev)
        rpm_sum += sim.rpm
        rpm_count += 1
    
    var avg = rpm_sum / rpm_count
    print("\nAverage RPM: %.1f (target: %.1f)" % [avg, spec.idle_target_rpm])
    print("Max deviation: %.1f RPM" % max_dev)
    print("Final manifold: %.1f kPa" % (sim.intake.pressure/1000.0))
    print("Lambda: %.3f" % sim.o2_lambda())
    
    return max_dev < 100.0

func _init():
    var ok = test_zx25r_idle_detailed()
    if ok:
        print("\n✓ IDLE ACCEPTABLE")
    else:
        print("\n✗ IDLE UNSTABLE")
    quit()