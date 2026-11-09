class_name PresetHondaCBR150R
extends RefCounted

## Honda CBR150R (K45N) - 150 cc single
## Bore x stroke from Webike Japan spec: 57.3 x 57.8 mm = 149.2 cc
## Redline from press dyno test (Otomotifnet, 2021): limiter near 10,600 rpm
## Flywheel, rod ratio, primary drive, final drive, gear ratios: estimates, no service manual source found
## Header: stock 4-2-1
## Fuel: RON 95
static var DATA := {
	"display_name": "Honda CBR150R (K45N)",
	"cylinders": 1,
	"displacement_cc": 149.2,
	"bore_mm": 57.3,
	"stroke_mm": 57.8,
	"rod_ratio": 1.6,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"fire_deg": [0.0],
	"redline_rpm": 10600.0,
	"flywheel_kg": 2.5,
	"flywheel_radius_mm": 75.0,
}