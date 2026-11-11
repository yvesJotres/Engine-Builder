# CBR250RR references

Everything gathered for the CBR250RR (MC51 / K64) work, in one place. Local files are copies; the originals were not changed.

## Local files

- **presets/**: the simulator presets (`honda_cbr250rr_2020.json` is the bike we are matching; `honda_cbr250rr.json` is the 2017 MC51 base; `honda_cbr250rr_sp_qs.json` is the SP QS).
- **dyno/**: the stored reference dyno data (`honda_cbr250rr_2020.json`, the power samples), the SP QS reference, and the digitized reference chart (`cbr250rr_reference_curve.json` / `.png`). The power and torque lines are swapped below 11,250 rpm; see the note below.
- **atg/**: ATG engine-sim engine files for the bike (`cbr250rr.mr`, `cbr250rr_sp.mr`). Both have estimated cam, valve and runner values.
- **atg_source/**: the ATG source files we compared against (`fuel.cpp` for flame speed, `combustion_chamber.cpp` for friction and burn, `cylinder_head.cpp` for port flow, `gas_system.cpp` for flow equations). ATG has no heat-transfer code.
- **photos/**: the camshaft photos you sent (`8.webp`, `9.png`, `10.png`, `5`–`7.png`). `10.png` is the parts listing with the part numbers.
- **sim_graphs/**: the sim comparison graphs we have made so far.

## Official and manufacturer data

- Honda Japan, 2020 CBR250RR release (30 kW / 41 PS at 13,000 rpm; 25 N·m at 11,000 rpm; bore × stroke 62.0 × 41.3 mm; compression 12.1): https://global.honda/jp/news/2020/2200723-cbr250rr.html
- Honda factbook, 2017 CBR250RR (MC51): https://global.honda/factbook/motor/CBR250RR/201704/P21.pdf
- Honda Malaysia / Boonsiew 2020 parts catalogue (PDF, shows the intake and exhaust cam part numbers): https://boonsiewhonda.com.my/wp-content/uploads/2023/08/CBR250RR-Parts-Catalogue-2020.pdf
- Honda Japan spec sheet (the PDF at this address could not be read; not verified): https://www.honda.co.jp/content/dam/site/www/CBR250RR/cq_img/pdf/CBR250RR_sp_spec.pdf
- Cam part numbers, Indonesian parts listings: intake 14110K64N00 and exhaust 14210K64N00 (fits K64 2016–2020, K64J 2020–2022, K64N 2022 on): https://www.hondacengkareng.com/produk/camshaft-comp-14110k64n00/ and https://www.hondacengkareng.com/produk/camshaft-comp-ex14210k64n00/
- Webike MC51 listing (249 cc, 62.0 × 41.3 mm, lists 12.5:1; conflicts with Honda's 12.1): https://japan.webike.net/HONDA/CBR250RR+2016-/13760/m-spec/

## Secondary data (check before relying on it)

- Young Machine 2020 (41 PS at 13,000 rpm; 2.5 kgf·m at 11,000 rpm): https://young-machine.com/2020/07/23/115403/
- Gaadiwaadi 2020 (41.7 PS): https://gaadiwaadi.com/2020-honda-cbr250rr-gets-more-power-and-features/
- moto-data 2019–20 (27.0 kW at 12,500 rpm; 23.3 N·m at 10,500 rpm): https://www.moto-data.net/honda/cbr-250rr-2019-2020
- Wikipedia, Honda CBR250RR (2017): https://en.wikipedia.org/wiki/Honda_CBR250RR_(2017)
- Bikewale 2020: https://bikewale.com/news/2020-honda-cbr250rr-details-explained
- Aftermarket DCR S2 cam (not stock): https://www.steadygarage.com/products/dcr-s2-camshaft-and-valve-spring-set-for-honda-cbr250r-cbr300

## Service manual (not the right one yet)

- A circulating "CBR250RR Service Manual" PDF is the older MC14-era manual. Do not use its valve timing or clearances: https://static1.squarespace.com/static/6231946072f2dc69c743070b/t/632e3cdadd383d3cb75123ea/1663974660496/Honda-CBR250RR-Service-Manual-EN.pdf
- Still needed: the MC51 / K64 workshop manual (cylinder head and camshaft sections).

## Physics literature

- Woschni (1967), SAE 670931: https://doi.org/10.4271/670931 (full text paywalled; the SAE page only shows a loading screen)
- Patton, Nitschke, Heywood (1989), friction model, SAE 890836: https://doi.org/10.4271/890836
- Pipitone (2009), friction model, SAE 2009-01-1984: https://saemobilus.sae.org/content/2009-01-1984/
- Discharge coefficients and engine simulation accuracy, SAE 962527: https://saemobilus.sae.org/content/962527
- Poppet-valve static and dynamic flow, SAE 820154: https://saemobilus.sae.org/papers/air-flow-poppet-inlet-valves-analysis-static-dynamic-flow-coefficients-820154
- Heat-transfer comparison, SAE 2014: https://saemobilus.sae.org/papers/heat-transfer-evaluation-internal-combustion-engine-operating-wet-ethanol-fuel-part-b-2014-36-0357
- Woschni heat transfer on HCCI, SAE 2020-01-0802: https://saemobilus.sae.org/content/2020-01-0802
- Colorado State heat-transfer notes: https://www.engr.colostate.edu/~allan/heat_trans/page7a/page7a.html
- Purdue ICEC paper (Reynolds analogy, exponent 0.8): https://docs.lib.purdue.edu/cgi/viewcontent.cgi?article=1657&context=icec
- MIT 2.61 lecture notes, SI combustion: https://web.mit.edu/2.61/www/Lecture%20notes/Lec.%2009%20SI%20engine%20combustion%20I.pdf
- Burn-duration correlation study: https://www.sciencedirect.com/science/article/abs/pii/S019689040300253X
- Volumetric efficiency thesis (intake natural frequency): https://mountainscholar.org/bitstreams/0d6c0993-76a7-4452-955d-772d600fc1df/download
- Simplified FMEP for fuel-consumption simulation: https://link.springer.com/article/10.1007/s42452-021-04892-y
- Heywood, Internal Combustion Engine Fundamentals: the copy in `docs/papers` is front matter only. The chapter text is still needed for friction, flame development, valve flow and wall temperatures.

## Secondary or forum (checks only)

- Taylor inlet Mach index (breathing limit near 0.6): https://forums.autosport.com/topic/105336-intake-valve-sizing-formula-clash/ and http://www.wallaceracing.com/machcalc2.php
- Heywood flame-development values, 18 to 29 degrees: https://github.com/pangtuwi/ESA.NET/pull/237
- Drivetrain loss estimates: https://en.wikipedia.org/wiki/Motorcycle_testing_and_measurement and https://www.thumpertalk.com/forums/topic/904110-approximate-drivetrain-power-loss/
- Airbox pressure drop (car intake, not a motorcycle baseline): https://journal.ump.edu.my/ijame/article/download/866/728/
- Honda Jade (MC14, a different engine; do not use): https://en.wikipedia.org/wiki/Honda_Jade_(motorcycle)

## Open issues

1. **Power and torque lines are swapped in the stored reference below 11,250 rpm.** The file is unchanged. The relabelled reading obeys power = torque × rpm within about 3%.
2. **Compression is 12.1 (Honda 2020) or 12.5 (Webike, Honda's later sheet).** We use 12.1.
3. **Gear ratios and final drive differ by source.** Our preset uses the older factbook values; the 2020 spec sheet values are unverified.
4. **Valve timing and lift for the 2020 K64/MC51 are not yet sourced.** Current values are estimates from the 2017 bike.
