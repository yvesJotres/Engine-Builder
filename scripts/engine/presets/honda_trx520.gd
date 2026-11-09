class_name PresetHondaTRX520
extends RefCounted

## Honda TRX520 (engine-sim) - 518 cc single
## From engine-sim assets/engines/atg-video-1/01_honda_trx520.mr (MIT, Copyright 2022 Ange Yaghi)
## Bore x stroke: 96.0 x 71.5 mm = 517.4 cc (published 518 cc)
## Rod ratio 2.13, redline 5000 rpm from engine-sim
## Increased flywheel inertia for launch
## Primary 3.13, final 3.0
## Header: stock
## Fuel: RON 95
static var DATA := {
	"display_name": "Honda TRX520 (engine-sim)",
	"cylinders": 1,
	"displacement_cc": 517.4,
	"bore_mm": 96.0,
	"stroke_mm": 71.5,
	"rod_ratio": 2.13,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 5000.0,
	"fire_deg": [0.0],
	"flywheel_kg": 5.0,
	"flywheel_radius_mm": 120.0,
	"vehicle_kg": 300.0,
	"primary_ratio": 3.13,
	"final_drive": 3.0,
	"gear_ratios": [3.5, 2.2, 1.6, 1.2, 0.95, 0.8],
}