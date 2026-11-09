extends SceneTree

func test_load_map():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    assert(map.map_id == "garrett_gtx3076r")
    assert(map.name == "Garrett GTX3076R (approx)")
    assert(map.speed_lines.size() == 5)
    assert(map.surge_line.size() == 8)
    assert(map.choke_line.size() == 7)
    print("test_load_map passed")

func test_correct_flow():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # At reference conditions, corrected flow = raw flow
    var corr = map.correct_flow(0.1, 288.15, 101325.0)
    assert(abs(corr - 0.1) < 0.001)
    # Higher temp -> higher corrected flow
    var corr_hot = map.correct_flow(0.1, 350.0, 101325.0)
    assert(corr_hot > 0.1)
    # Higher pressure -> lower corrected flow
    var corr_high_p = map.correct_flow(0.1, 288.15, 202650.0)
    assert(corr_high_p < 0.1)
    print("test_correct_flow passed")

func test_correct_speed():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # At reference temp, corrected speed = raw speed
    var corr = map.correct_speed(100000.0, 288.15)
    assert(abs(corr - 100000.0) < 1.0)
    # Higher temp -> lower corrected speed
    var corr_hot = map.correct_speed(100000.0, 350.0)
    assert(corr_hot < 100000.0)
    print("test_correct_speed passed")

func test_lookup_speed_line():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # Line 0: 50000 rpm, flow 0.02 -> pr 1.0, eff 0.45
    var res = map.lookup_speed_line(0, 0.02)
    assert(abs(res.x - 1.0) < 0.01)
    assert(abs(res.y - 0.45) < 0.01)
    # Interpolate between 0.05 and 0.08
    var res_mid = map.lookup_speed_line(0, 0.065)
    assert(res_mid.x > 1.3 and res_mid.x < 1.6)
    assert(res_mid.y > 0.62 and res_mid.y < 0.72)
    # Extrapolate low
    var res_low = map.lookup_speed_line(0, 0.01)
    assert(abs(res_low.x - 1.0) < 0.01)
    assert(abs(res_low.y - 0.45) < 0.01)
    # Extrapolate high
    var res_high = map.lookup_speed_line(0, 0.2)
    assert(abs(res_high.x - 2.5) < 0.01)
    assert(abs(res_high.y - 0.60) < 0.01)
    print("test_lookup_speed_line passed")

func test_lookup():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # At 50000 rpm, flow 0.08 -> should be on first speed line
    var res = map.lookup(50000.0, 0.08)
    assert(abs(res.pr - 1.6) < 0.05)
    assert(abs(res.eff - 0.72) < 0.05)
    assert(res.speed_line == 0)
    # Interpolate between 50k and 70k
    var res_mid = map.lookup(60000.0, 0.08)
    # At 50k: PR=1.6, at 70k: PR~1.5 (interpolated), so mid should be ~1.55
    assert(res_mid.pr > 1.5 and res_mid.pr < 1.65)
    # At 50k: eff=0.72, at 70k: eff~0.72 (interpolated), so mid should be ~0.72
    assert(abs(res_mid.eff - 0.72) < 0.05)
    assert(res_mid.speed_line == 0)
    assert(res_mid.interp > 0.0 and res_mid.interp < 1.0)
    # Clamp high
    var res_high = map.lookup(200000.0, 0.08)
    assert(res_high.speed_line == 4)
    # Clamp low
    var res_low = map.lookup(10000.0, 0.08)
    assert(res_low.speed_line == 0)
    print("test_lookup passed")

func test_surge():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # Low flow, high PR -> surge
    assert(map.is_surge(0.03, 2.0) == true)
    # High flow, low PR -> no surge
    assert(map.is_surge(0.2, 1.2) == false)
    # On surge line boundary
    assert(map.is_surge(0.05, 1.3) == false)  # exactly on line
    assert(map.is_surge(0.05, 1.31) == true)  # slightly above
    print("test_surge passed")

func test_choke():
    var map = CompressorMap.load_from_json("res://assets/compressor_maps/garrett_gtx3076r.json")
    # High flow, low PR -> choke
    assert(map.is_choke(0.4, 1.2) == true)
    # Low flow, high PR -> no choke
    assert(map.is_choke(0.05, 2.5) == false)
    # On choke line boundary
    assert(map.is_choke(0.2, 1.5) == false)
    assert(map.is_choke(0.2, 1.49) == true)
    print("test_choke passed")

func _init():
    test_load_map()
    test_correct_flow()
    test_correct_speed()
    test_lookup_speed_line()
    test_lookup()
    test_surge()
    test_choke()
    print("All CompressorMap tests passed")
    quit()