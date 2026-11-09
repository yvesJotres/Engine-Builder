class_name PresetYamahaYZFR1M
extends RefCounted

## Yamaha YZF-R1M (2015) - 998 cc crossplane inline four
## Bore x stroke from motodealers.co.uk and Ultimate Motorcycling: 79.0 x 50.9 mm = 998.0 cc
## Compression 13.0 from same sources
## Gear ratios, redline (limiter 14,600), flywheel, rod ratio, 200 kg mass from engine-sim yzf_r1.mr (MIT, Copyright 2022 Ange Yaghi)
## engine-sim has no separate primary drive: total ratio with 4.7 final drive, primary = 1.0 here
## Crossplane crank: firing 270/180/90/180 apart
## Header: stock
## Fuel: RON 95
static var DATA := {
	"display_name": "Yamaha YZF-R1M (2015)",
	"cylinders": 4,
	"displacement_cc": 998.0,
	"bore_mm": 79.0,
	"stroke_mm": 50.9,
	"rod_ratio": 2.0,
	"compression_ratio": 13.0,
	"crossplane": true,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 14600.0,
	"fire_deg": [0.0, 450.0, 270.0, 540.0],
	"flywheel_kg": 5.2,
	"flywheel_radius_mm": 103.2,
	"primary_ratio": 1.0,
	"final_drive": 4.7,
	"gear_ratios": [2.600, 2.176, 1.842, 1.579, 1.381, 1.250],
	"vehicle_kg": 200.0,
}