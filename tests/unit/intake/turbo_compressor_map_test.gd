extends SceneTree

const ENGINE_AIR := preload("res://scripts/intake/engine_air.gd")
const ENGINE_SPEC := preload("res://scripts/engine/engine_spec.gd")

func test_electric_compressor_spool():
    var spec = ENGINE_SPEC.new()
    spec.electric_compressor = true
    spec.compressor_map_id = "garrett_gtx3076r"
    spec.compressor_inertia_kgm2 = 0.00002
    spec.compressor_power_w = 2000.0
    spec.compressor_battery_wh = 40.0
    spec.compressor_charge_w = 1000.0
    spec.max_boost_ratio = 2.0
    
    var air = ENGINE_AIR.new()
    air.setup(spec)
    
    # Simulate 1s at WOT - verify compressor spins up and system doesn't crash
    for i in 100:
        air.manifold_update(0.01, 1.0, 0.04, spec, 4000.0, true, 0.0)
    
    # Check that compressor spins up (speed > 0) and charge depletes
    assert(air.compressor_speed_rpm > 10000.0)
    assert(air.compressor_charge < 1.0)
    print("Electric compressor spool test passed")

func test_turbine_compressor_map():
    var spec = ENGINE_SPEC.new()
    spec.electric_compressor = false
    spec.compressor_map_id = "garrett_gtx3076r"
    spec.compressor_inertia_kgm2 = 0.00005
    spec.turbine_a_r = 0.63
    spec.turbine_efficiency = 0.70
    spec.wastegate_type = "internal"
    spec.wastegate_pressure_ratio = 2.0
    spec.max_boost_ratio = 2.5
    
    var air = ENGINE_AIR.new()
    air.setup(spec)
    
    # Need mock exhaust conditions - simplify for unit test
    # This test mainly verifies no crashes and map loads
    for i in 100:
        air.manifold_update(0.01, 1.0, 0.05, spec, 4000.0, true, 10.0)
    
    assert(air.compressor_map != null)
    print("Turbine compressor map test passed")

func _init():
    test_electric_compressor_spool()
    test_turbine_compressor_map()
    print("All turbo compressor map tests passed")
    quit()