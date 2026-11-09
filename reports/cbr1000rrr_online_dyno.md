# CBR1000RR-R Fireblade SP and online dyno comparison

Added **Honda CBR1000RR-R Fireblade SP (2020, Europe)** to the source library. The dyno screen now offers a separate estimated rear-wheel comparison with an online stock-bike reference. **The full curve is not matched yet.** No publication or commit was performed.

## Results

The independent target is [BSD/BikeSocial's UK stock 2020 RR-R test](https://www.bennetts.co.uk/bikesocial/reviews/bikes/honda/honda-cbr1000rr-r-fireblade-sp-2020-review-price-spec): **199.76 wheel hp at 13,900 rpm and 78.96 lb-ft (107.05 Nm) at 12,500 rpm**. It tested the base RR-R in fourth gear; the tester explicitly identifies its engine as shared with the SP. Its chart uses DIN correction and does not publish ambient conditions. Sampled curve points are approximate, with a stated ±2 hp reading uncertainty; reported peaks are retained exactly.

| Comparison | Online stock | Source, 2,400 Hz | Source, 7,200 Hz |
|---|---:|---:|---:|
| Peak rear-wheel power | 199.76 hp | 199.08 hp (−0.34%) | 204.85 hp (+2.55%) |
| Engine speed at power peak | 13,900 rpm | 14,377 rpm | 14,501 rpm |
| Peak engine-equivalent rear-wheel torque | 107.05 Nm | 99.11 Nm (−7.42%) | 100.85 Nm (−5.79%) |

The table above records uncorrected wheel estimates. Wheel output is an **estimate from the original crank measurement using the simulator's existing 93% drivetrain efficiency**, not measured roller output or an efficiency fitted to this reference. Crank data and saved reference runs are retained unchanged.

The final comparison screen also applies **1.011366 DIN normalization**, calculated from the cylinder model's actual fixed dry air (300 K, 101325 Pa). [Dynojet specifies 20 C, 1013 mbar, dry air](https://docs.dynojet.com/Support/SoftwareHelpFiles/PowerCoreHelp/en-US/2.1.0/DataCenter/DataCenter/DataCenter/To_Apply_Correction_Factors.htm); the naturally aspirated factor is `(101300 / pressure_pa) * sqrt(temp_k / 293.15)`, consistent with the DIN formula in [MAHA's dynamometer operating manual](https://www.mahaireland.ie/support_documents/dokumente/Betriebsanleitungen/04%20Leistungsmesstechnik/BA053101-en.pdf?_locale=en). Editable weather metadata is deliberately not mistaken for simulated cylinder conditions.

At 7,200 Hz the DIN comparison is **207.17 wheel hp (+3.71%) and 102.00 Nm (-4.72%)**. Torque meets the 5% peak tolerance, but power exceeds the 3% limit. The source uses a multi-gear road sweep; the online test used a fourth-gear roller pull. Its acceleration rate, tyre loss and actual drivetrain efficiency are not reproduced. This is a provisional comparison, not an equivalent test or validated match.

The high-resolution source main-scene run completed all six gears: **51 bins, 4,598 independent engine cycles**, estimated crank peaks **220.26 hp and 108.44 Nm**, highest simulated road speed **307.13 km/h**, terminal clutch slip **−2.1 rpm**. Road speed is not a validated real-world result: the stock ECU's speed limit and gear-dependent throttle maps are not reproduced.

Power peak location misses the strict 600-rpm boundary by about 1 rpm. Across the 21 sampled reference points, DIN-normalized power error RMS is **4.06% of reference peak**, and the largest error is **8.27% of peak**. The full-curve check therefore fails. Matching the low-resolution uncorrected power peak alone would hide these differences. `plot_online_dyno.py --check` intentionally exits nonzero for this result.

![Source simulation against the online curve](D:/Projects/Engine%20Builder/reports/honda_cbr1000rrr_sp_dyno_comparison.png)

## Data and implementation

- Honda's [European EICMA release](https://global.honda/en/newsroom/news/2019/2191105aeng.html) supplies the 160 kW at 14,500 rpm / 113 Nm at 12,500 rpm factory crank reference. Its [first-generation technical release](https://hondanews.ca/en-CA/hci-power/releases/release-b6701d6c6a3ec3934c67bf479d61e09a21b3cd41-2020-honda-cbr1000rr-r-fireblade-sp) supplies the 81 × 48.5 mm geometry, 13.0 compression, four 52 mm throttles and 32.5/28.5 mm valve heads. Equipment declarations distinguish the SP's quickshifter from the base trim.
- Correct 1,455 mm wheelbase, 201 kg curb mass plus a separate 75 kg rider, 120/70-17 and 200/55-17 tyres are stored with the preset. First-generation owner/press gearing is 1.630 primary, 2.500 final and 2.615/2.058/1.700/1.478/1.333/1.214 gears; [Honda's 2020 Japanese specification table](https://global.honda/jp/news/2020/2200305-cbr1000rr-r.html) corroborates these ratios. Its 13.2 compression entry is not substituted for the selected European 13.0 specification. Nominal displacement is calculated from bore/stroke, approximately 999.7 cc.
- ABS, HSTC, Start Mode, up/down quickshifter and slipper-clutch availability are declared. ABS/traction-control switches remain hidden under the existing policy until independent wheel-slip intervention is implemented; declaring hardware does not turn on a fake intervention.
- The comparison view shows both reference power and torque, DIN normalization, peak errors, curve RMS and an explicit not-matched status. Crank/wheel selection cannot overwrite the measured crank data or save a wheel curve as a crank reference. Switching bikes clears the online overlay. The panel scrolls at short viewport heights.
- Dyno runs now retain a higher selected simulation rate instead of forcing every run to 2,400 Hz. The previous rate is restored after the sweep.
- Export presets explicitly include engine and dyno JSON assets. A local Windows PCK export succeeded, and its export log confirms inclusion of the new preset, benchmark and comparison script. The exported game was not installed or used for gameplay testing.

## What is still provisional

No verified stock SC82 cam trace was found. The initial 10/10 mm lifts, 110-degree centres and 225-degree durations at 0.050 inch are inherited **provisional engine-sim inputs**, represented by 256.5-degree estimated seat durations. They are not asserted to be Honda stock cam specifications. The panel now preserves these half-degree durations.

Runner equivalent bore follows the 52 mm throttle as an estimate; runner length, taper and effective port volume are unmeasured. Flywheel/piston/rod/wheel masses, clutch capacity, slant, limiter and shift timings are estimates. Drag area remains an estimate: Honda's dimensionless Cd 0.270 is **not** incorrectly used as CdA. The procedural motorcycle is not an OEM bodywork replica.

The remaining midrange torque and curve-shape discrepancies need verified cam/runner dimensions, stock throttle-control behaviour and further flow/combustion/exhaust validation, plus a comparable fourth-gear roller protocol. No engine-output multiplier, target-curve lookup, guessed ECU binary map or race-kit cam was introduced to force a pass. The documented DIN display normalization changes neither engine physics nor original crank measurements.

## Validation

- Native and GDScript CBR1000RR-R cylinders agree within 1e-6 relative torque tolerance over 20 prescribed engine cycles at both 12,500 and 14,500 rpm.
- Fixed-speed crank measurements at 14,400 / 28,800 Hz: **167.02 / 167.64 kW at 14,500 rpm**, and **109.22 / 109.73 Nm at 12,500 rpm**. Doubling the rate changes these by 0.37% / 0.47%. Fine-rate factory power error is still +4.8%, so the factory accuracy contract also fails.
- JSON schema validation, all 17 preset panel defaults, online-unit conversion, curve comparison, preservation of crank data, short-panel scrolling, bike switching and dyno rate restoration pass. The full **30-test gate plus server tests** passes; the separate real-world accuracy check correctly fails.
- A bounded 11-second real-time run used the actual Godot source main scene with normal graphics/audio drivers at a 60 FPS cap. Idle and high rev both held approximately **60 FPS**; high rev reached about **15,000 rpm**, with 95th-percentile game-update time **4.76 ms** and frame time **16.69 ms**. One audio buffer-starvation flag occurred in each three-second idle/high-rev sample. Longer audio testing and Android runtime are unverified.

Artifacts: `build/dyno_honda_cbr1000rrr_sp_repaired.json` and `.csv`, `build/accuracy/honda_cbr1000rrr_sp_online_comparison.json`, `tools/diagnostics/out/dyno_honda_cbr1000rrr_sp_repaired.png`, and the comparison plot alongside this report.
