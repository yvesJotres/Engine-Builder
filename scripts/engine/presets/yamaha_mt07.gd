class_name PresetYamahaMT07
extends RefCounted

## Yamaha MT-07 (CP2, 689 cc) - 270° parallel twin
## Bore x stroke: 80.0 x 68.6 mm = 689.0 cc
## Compression 11.5, rod ratio 1.7 from public specs
## Redline 10,500 rpm
## Twin pin: 270° crank pin angle for CP2 parallel twin
## Firing: cylinder 2 fires 270° after cylinder 1 (intervals 270°/450°)
## Increased flywheel for 270° twin launch
## Primary 2.0, final 2.667
## Header: stock
## Fuel: RON 95
static var DATA := {
	"display_name": "Yamaha MT-07 (CP2, 689 cc)",
	"cylinders": 2,
	"displacement_cc": 689.0,
	"bore_mm": 80.0,
	"stroke_mm": 68.6,
	"rod_ratio": 1.7,
	"compression_ratio": 11.5,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 10500.0,
	"twin_pin_deg": 270.0,
	"fire_deg": [0.0, 270.0],
	"flywheel_kg": 6.0,
	"flywheel_radius_mm": 105.0,
	"primary_ratio": 2.0,
	"final_drive": 2.667,
	"gear_ratios": [2.692, 2.063, 1.667, 1.400, 1.227, 1.100],
	"vehicle_kg": 182.0,
}