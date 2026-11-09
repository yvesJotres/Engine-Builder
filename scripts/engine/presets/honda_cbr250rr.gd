class_name PresetHondaCBR250RR
extends RefCounted

## Honda CBR250RR (2017, MC51) - 250 cc inline twin
## Bore x stroke from Webike Japan spec: 62.0 x 41.3 mm = 249.7 cc (published 249.7 cc)
## Rod ratio, redline, flywheel, gears, final drive from engine-sim cbr250rr.mr (MIT, Copyright 2022 Ange Yaghi)
## engine-sim has no separate primary drive: gear ratios are value * 2, diff_ratio 4.7
## Primary = 1.0 so crank-to-wheel = gear * 2 * 4.7 (not Webike's 2.781 on top)
## Twin pin: 180 deg crank pin angle
## Header: stock
## Fuel: RON 95
## ECU: 38770-K64-N04 (Indonesia 2017-2019), 14000 RPM limiter, 4 fuel maps, 5 ignition maps, torque limiter by gear
static var DATA := {
	"display_name": "Honda CBR250RR (2017, MC51)",
	"cylinders": 2,
	"displacement_cc": 249.3,
	"bore_mm": 62.0,
	"stroke_mm": 41.3,
	"rod_ratio": 2.0,
	"compression_ratio": 12.0,
	"vehicle_kg": 165.0,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 14000.0,
	"twin_pin_deg": 180.0,
	"fire_deg": [0.0, 180.0],
	"flywheel_kg": 3.6,
	"flywheel_radius_mm": 103.2,
	"primary_ratio": 1.0,
	"final_drive": 4.7,
	"gear_ratios": [6.362, 4.918, 3.934, 3.152, 2.530, 2.136],
	"ecu_binary": "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin",
}