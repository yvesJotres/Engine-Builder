class_name Gearbox
extends RefCounted

# Six-speed gearbox, tooth counts from the Honda K45R parts catalogue (E-17 transmission).
# Gear ratio = countershaft teeth / mainshaft teeth, so 1st = 37 / 12 and 6th = 24 / 26.

const MAIN_TEETH := [12, 17, 20, 22, 24, 26] # mainshaft gears, 1st to 6th
const COUNTER_TEETH := [37, 33, 30, 27, 25, 24] # countershaft gears, 1st to 6th
const TOP_GEAR := 6

var gear := 0 # 0 = neutral
var gear_ratios: Array = ratios() # set per engine by EngineSim, default K45R


# Gearbox ratio for each gear, 1st to 6th, from the K45R tooth counts.
static func ratios() -> Array:
	var out := []
	for i in MAIN_TEETH.size():
		out.append(float(COUNTER_TEETH[i]) / MAIN_TEETH[i])
	return out


# Gearbox ratio for the selected gear, 0 in neutral.
func ratio() -> float:
	return gear_ratios[gear - 1] if gear > 0 else 0.0


# Like a real motorcycle drum: 1st, neutral, 2nd, 3rd, ... so neutral is the half click between 1st and 2nd, and there is
# nothing below 1st. Starting in neutral, down gives 1st and up gives 2nd.
func shift_up() -> void:
	gear = mini(2, gear_ratios.size()) if gear == 0 else (0 if gear == 1 else mini(gear + 1, gear_ratios.size()))


func shift_down() -> void:
	gear = 1 if gear == 0 else (0 if gear == 2 else maxi(gear - 1, 1))


func label() -> String:
	return "N" if gear == 0 else str(gear)
