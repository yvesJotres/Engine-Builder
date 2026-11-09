extends SceneTree

class TestLibrary extends EngineLibrary:
	func _load_cache() -> void:
		pass

	func _save_cache() -> void:
		pass

var _fails := 0

func _init() -> void:
	await process_frame
	var probe := TestLibrary.new()
	var merged: Dictionary = probe._merge_extras({"Honda CBR150R (K45N)": {"cylinders": 1}, "Test engine": {"cylinders": 2}})
	if merged.has("Honda CBR150R (K45N)"):
		_fail("display-name copy of a bundled engine was kept")
	if not merged.has("honda_cbr150r") or not merged.has("Test engine"):
		_fail("bundled engine or new server engine was dropped")
	var old_r1: Dictionary = Presets.PRESETS.yamaha_yzf_r1m.duplicate(true)
	old_r1.erase("preset_revision")
	old_r1.intake_lift_mm = 6.0
	merged = probe._merge_extras({"yamaha_yzf_r1m": old_r1})
	if merged.yamaha_yzf_r1m.intake_lift_mm != 9.7:
		_fail("old server cache replaced the corrected R1M")
	old_r1.preset_revision = Presets.PRESETS.yamaha_yzf_r1m.preset_revision
	merged = probe._merge_extras({"yamaha_yzf_r1m": old_r1})
	if merged.yamaha_yzf_r1m.intake_lift_mm != 6.0:
		_fail("current server revision could not override a bundled preset")
	var old_cbr: Dictionary = Presets.PRESETS.honda_cbr150r.duplicate(true)
	old_cbr.erase("preset_revision")
	old_cbr.wheelbase_mm = 1310.0
	merged = probe._merge_extras({"honda_cbr150r": old_cbr})
	if merged.honda_cbr150r.wheelbase_mm != 1309.0:
		_fail("old server cache replaced the corrected K45N wheelbase")
	await _check_response(200, '{"Test engine":{"cylinders":2}}')
	await _check_response(500, "error")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func _check_response(status: int, body: String) -> void:
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		_fail("could not start local HTTP server")
		return
	var library := TestLibrary.new()
	library._loading = true
	library.call_deferred("_start_request", "http://127.0.0.1:%d" % server.get_local_port())
	var peer: StreamPeerTCP
	var responded := false
	var deadline := Time.get_ticks_msec() + 5000
	while library._loading and Time.get_ticks_msec() < deadline:
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer != null:
			peer.poll()
			if not responded and peer.get_available_bytes() > 0:
				peer.get_data(peer.get_available_bytes())
				var response := "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, "OK" if status == 200 else "Error", body.to_utf8_buffer().size(), body]
				peer.put_data(response.to_utf8_buffer())
				responded = true
		await process_frame
	if not library.is_ready():
		_fail("request did not complete for HTTP %d" % status)
	elif status == 200 and not library.get_library().has("Test engine"):
		_fail("server library was not loaded")
	if library._http != null:
		library._http.free()
	server.stop()

func _fail(message: String) -> void:
	_fails += 1
	print("FAIL " + message)
