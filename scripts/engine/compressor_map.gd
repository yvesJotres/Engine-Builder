class_name CompressorMap
extends Resource

@export var map_id: String
@export var name: String
# speed_lines: each line is [corrected_speed_rpm, [ [pr, flow, eff], ... ]]
@export var speed_lines: Array = []
# surge line: [ [flow, pr], ... ] — left boundary
@export var surge_line: Array = []
# choke line: [ [flow, pr], ... ] — right boundary
@export var choke_line: Array = []
# reference conditions
@export var ref_temp_k: float = 288.15
@export var ref_pressure_pa: float = 101325.0

static func load_from_json(path: String) -> CompressorMap:
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open compressor map: " + path)
        return CompressorMap.new()
    var json = JSON.parse_string(file.get_as_text())
    file.close()
    var map = CompressorMap.new()
    var data = json
    map.map_id = data.map_id
    map.name = data.name
    map.speed_lines = data.speed_lines
    map.surge_line = data.surge_line
    map.choke_line = data.choke_line
    map.ref_temp_k = data.get("ref_temp_k", 288.15)
    map.ref_pressure_pa = data.get("ref_pressure_pa", 101325.0)
    return map

# Corrected mass flow: m_dot * sqrt(T/T_ref) / (P/P_ref)  [kg/s]
func correct_flow(raw_flow: float, temp_k: float, pressure_pa: float) -> float:
    return raw_flow * sqrt(temp_k / ref_temp_k) / (pressure_pa / ref_pressure_pa)

# Corrected speed: N / sqrt(T/T_ref)  [rpm]
func correct_speed(raw_speed: float, temp_k: float) -> float:
    return raw_speed / sqrt(temp_k / ref_temp_k)

# Bilinear interpolation on speed line: given corrected_flow, return (pr, efficiency)
func lookup_speed_line(line_idx: int, corrected_flow: float) -> Vector2:
    var line = speed_lines[line_idx]
    var points = line[1] # [ [pr, flow, eff], ... ]
    # sort by flow
    points.sort_custom(func(a, b): return a[1] < b[1])
    for i in range(points.size() - 1):
        var f0 = points[i][1]
        var f1 = points[i + 1][1]
        if corrected_flow >= f0 and corrected_flow <= f1:
            var t = (corrected_flow - f0) / (f1 - f0)
            var pr = lerp(points[i][0], points[i + 1][0], t)
            var eff = lerp(points[i][2], points[i + 1][2], t)
            return Vector2(pr, eff)
    # extrapolate nearest
    if corrected_flow < points[0][1]:
        return Vector2(points[0][0], points[0][2])
    return Vector2(points[-1][0], points[-1][2])

# Interpolate between speed lines at given corrected_speed and corrected_flow
func lookup(corrected_speed: float, corrected_flow: float) -> Dictionary:
    # find bounding speed lines
    var speeds = []
    for line in speed_lines:
        speeds.append(line[0])
    # clamp
    if corrected_speed <= speeds[0]:
        var res = lookup_speed_line(0, corrected_flow)
        return {"pr": res.x, "eff": res.y, "speed_line": 0}
    if corrected_speed >= speeds[-1]:
        var res = lookup_speed_line(speeds.size() - 1, corrected_flow)
        return {"pr": res.x, "eff": res.y, "speed_line": speeds.size() - 1}
    # interpolate between two lines
    for i in range(speeds.size() - 1):
        if corrected_speed >= speeds[i] and corrected_speed <= speeds[i + 1]:
            var t = (corrected_speed - speeds[i]) / (speeds[i + 1] - speeds[i])
            var res0 = lookup_speed_line(i, corrected_flow)
            var res1 = lookup_speed_line(i + 1, corrected_flow)
            var pr = lerp(res0.x, res1.x, t)
            var eff = lerp(res0.y, res1.y, t)
            return {"pr": pr, "eff": eff, "speed_line": i, "interp": t}
    return {"pr": 1.0, "eff": 0.7, "speed_line": 0}

# Check if operating point is in surge (left of surge line)
func is_surge(corrected_flow: float, pr: float) -> bool:
    if surge_line.is_empty():
        return false
    for i in range(surge_line.size() - 1):
        var f0 = surge_line[i][0]
        var f1 = surge_line[i + 1][0]
        var p0 = surge_line[i][1]
        var p1 = surge_line[i + 1][1]
        if corrected_flow >= f0 and corrected_flow <= f1:
            var surge_pr = lerp(p0, p1, (corrected_flow - f0) / (f1 - f0))
            return pr > surge_pr # operating PR higher than surge line at this flow = surge
    return false

# Check if operating point is in choke (right of choke line)
func is_choke(corrected_flow: float, pr: float) -> bool:
    if choke_line.is_empty():
        return false
    for i in range(choke_line.size() - 1):
        var f0 = choke_line[i][0]
        var f1 = choke_line[i + 1][0]
        var p0 = choke_line[i][1]
        var p1 = choke_line[i + 1][1]
        if corrected_flow >= f0 and corrected_flow <= f1:
            var choke_pr = lerp(p0, p1, (corrected_flow - f0) / (f1 - f0))
            return pr < choke_pr
    return false