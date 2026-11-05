# Honda CBR150R K45R (2021-2026) Engine Research Notes

Scope: K45R only (2021-2026, Indonesian AHM market). Figures from K45G (2016-2018 launch era) or K45N (2018-2020) are flagged as such. Labels: **Verified** = read from a fetched page with URL; **Unverified** = search snippet only, or a claim without a primary source; **Gap** = not found.

Source note: honda official AHM pages and astra-honda.com returned HTTP 403 or were not reachable. The dealer pages used below (hondacengkareng.com, hondamandalajayaabadi.com) are dealer-published, not AHM-issued, and neither page labels its spec block with a K-code. Treat dealer spec blocks as strong secondary evidence, not as AHM official data.

## Key Question 1: Official bore x stroke and compression ratio for K45R

### Takeaway
Dealer spec blocks and secondary press agree on 57.3 x 57.8 mm, 149.16 cc, and 11.3:1 compression for the 2021 engine. No AHM primary document was retrieved to confirm this.

### Cited Findings
- Bore x stroke 57.3 x 57.8 mm; displacement 149.16 cc; compression ratio 11.3:1; 4-stroke DOHC, 4 valves, liquid-cooled — **Verified (dealer)**: [Honda Cengkareng CBR 150R page](https://www.hondacengkareng.com/motor/honda-cbr-150r/)
- Same values: 57.3 x 57.8 mm, 149.16 cc, 11.3:1, PGM-FI, "Liquid Cooled with Auto Fan" — **Verified (dealer)**: [Honda Mandala Jaya Abadi spec page](https://www.hondamandalajayaabadi.com/spesifikasi-honda-cbr150r.html)
- Same values with the 2021 model called "All New": 149.16 cc, 57.3 x 57.8 mm, 11.3:1 — **Verified (secondary)**: [Autofun spec article](https://www.autofun.co.id/berita-motor/Simak-Spesifikasi-All-New-Honda-CBR150R-2021-Kena-Update-Fitur-dan-Desain-Makin-Agresif-22412) (fetch returned 403; figures are from the search snippet, so **Unverified** for this exact page)
- Wikipedia spec table lists 57.3 x 57.8 mm and 11.3:1 for the 2021-present column, but also lists 63.5 x 47.2 mm and 11.0:1 for older columns; the table is merged and does not map cleanly to K45R — **Verified (fetch), with column ambiguity**: [Wikipedia Honda CBR150R](https://en.wikipedia.org/wiki/Honda_CBR150R)
- Dyno article repeats 57.3 x 57.8 mm, 149.2 cc, DOHC 4-valve, 11.3:1 as stated specs — **Verified (secondary, manufacturer claims)**: [Otomotifnet dyno article](https://otomotifnet.gridoto.com/read/232535641/all-new-honda-cbr150r-dites-dyno-ternyata-tenaga-on-wheel-segini?page=all)

### Contradictions
- **Bore x stroke / CR / displacement in Wikipedia's merged table:** older columns (63.5 x 47.2 mm, 11.0:1, 149.5 cc) conflict with the 57.3 x 57.8 mm and 11.3:1 set. The 63.5 x 47.2 mm figures are not K45R data.
- **Wikipedia prose** describes the earlier engine as short-stroke, which conflicts with its own 63.5 x 47.2 mm (long-stroke) table entry. Not resolved; not used.

### Inferences
- The 57.3 x 57.8 mm / 11.3:1 set is consistent across four independent sources (two dealers, two press). Confidence is good but still secondary.

### Gaps
- No AHM or Honda primary spec sheet fetched. Honda Indonesia pages were not reachable.

## Key Question 2: Published power and torque curve, or intermediate rpm data

### Takeaway
Only peak values are published. Peak claim is 17.1 PS at 9,000 rpm and 14.4 Nm at 7,000 rpm. An independent dyno (Otomotifnet, Jan 2021) measured lower peaks (15.10 PS at 9,040 rpm; 13.29 Nm at 7,560 rpm). No rpm-by-rpm curve was found.

### Cited Findings
- Claimed max power 12.6 kW (17.1 PS) at 9,000 rpm; claimed max torque 14.4 Nm (1.47 kgf.m) at 7,000 rpm — **Verified (dealer)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/); [Honda Mandala Jaya Abadi](https://www.hondamandalajayaabadi.com/spesifikasi-honda-cbr150r.html)
- Otomotifnet dyno (Dynojet 250i, Sportisi Motorsport, Rawamangun, East Jakarta): on-wheel peak power 15.10 dk (PS) at 9,040 rpm; peak torque 13.29 Nm at 7,560 rpm; power and torque begin rising around 5,000 rpm; power falls after 9,000 rpm; limiter around 10,600 rpm — **Verified (fetch)**: [Otomotifnet dyno article](https://otomotifnet.gridoto.com/read/232535641/all-new-honda-cbr150r-dites-dyno-ternyata-tenaga-on-wheel-segini?page=all). Test date not stated in body; published 31 Jan 2021. Gear, ambient conditions, and correction factors not stated. Dyno is on-wheel, so it is not directly comparable to crank claims.
- Dealer 2016 launch article (K45G era) gives 12.6 kW (17.1 PS) at 9,000 rpm and 13.7 Nm at 7,000 rpm — **K45G-era, do not use as K45R** — [Honda Cengkareng 2016 article](https://www.hondacengkareng.com/ahm-rilis-all-new-honda-cbr-150r/)
- Wikipedia lists 18 hp, 14.4 Nm, 151 kg curb weight, no rpm — **Verified (fetch), but no rpm and likely a different market/era; treat as contradiction**: [Wikipedia](https://en.wikipedia.org/wiki/Honda_CBR150R)
- Bikesrepublic and Paultan report 17.1 PS at 9,000 rpm; Rushlane reports 139 kg (Malaysian review) — **Unverified (search snippets only)**: [Bikesrepublic](https://www.bikesrepublic.com/news/bulletin/2021-honda-cbr150r-launched-indonesia-17hp-rm11k/), [Rushlane](https://www.rushlane.com/2021-honda-cbr150r-updates-new-yamaha-r15-rival-12412005.html)

### Contradictions
- **Claimed vs measured peak power:** 17.1 PS (claim) vs 15.10 PS (Otomotifnet dyno). Gap of about 2 PS (roughly 12%). Likely drivetrain loss plus conditions, but the article does not state the correction factor, so the cause is not confirmed.
- **Claimed vs measured peak torque:** 14.4 Nm (claim) vs 13.29 Nm (dyno). Gap about 8%.
- **Peak rpm:** power peak 9,000 rpm claimed vs 9,040 rpm measured (consistent). Torque peak 7,000 rpm claimed vs 7,560 rpm measured (inconsistent by about 560 rpm).
- **Wikipedia 18 hp / 14.4 Nm / 151 kg** vs 17.1 PS and 139-ish kg in other sources. Unresolved.
- **Bikeadvice (search snippet)** reports 17.1 PS at 10,500 rpm and 13 Nm at 7,500 rpm. This conflicts with the dealer and dyno power rpm, and was not fetched. Treat as **Unverified**.

### Inferences
- The gap between claim and dyno is consistent with the ~12% drivetrain loss commonly cited for small bikes, but this is not confirmed for this bike.

### Gaps
- No rpm-by-rpm power or torque curve found.
- No rear-wheel dyno from a magazine with correction factors. Motoplus, Oto, and Motorplus dyno tests were suggested but not searched.
- Otomotifnet article does not state test date, gear, or conditions.

## Key Question 3: Throttle body bore

### Takeaway
Not found for K45R. The only throttle-body figure in the results belongs to the CB150R (a sibling model), not the CBR150R.

### Cited Findings
- CB150R throttle body has a 30 mm venturi; an aftermarket kit reamed it to 33 mm — **Verified (fetch, sibling model, not K45R)**: [Gridoto throttle reamer article](https://www.gridoto.com/read/222473816/honda-pcx-dan-adv150-pasang-throttle-body-reamer-segini-harganya)

### Gaps
- K45R throttle body bore not found. Honda parts catalogue (hondacengkareng.com) lists K45G parts catalogue only; the K45R catalogue was not located.

## Key Question 4: Intake and exhaust valve diameters and lift

### Takeaway
Not found. Engine is 4 valves per cylinder, DOHC, which is confirmed. Valve sizes and lift are not published in any source retrieved.

### Cited Findings
- 4-valve DOHC, single cylinder — **Verified (dealer)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/)

### Gaps
- Intake valve diameter, exhaust valve diameter, max valve lift: **Gap**.
- Cam timing and duration: **Gap**.
- Autofun mentions intake and exhaust were changed for sound and efficiency in the 2021 update, but gives no dimensions: **Unverified**: [Autofun spec article](https://www.autofun.co.id/berita-motor/Simak-Spesifikasi-All-New-Honda-CBR150R-2021-Kena-Update-Fitur-dan-Desain-Makin-Agresif-22412)

## Key Question 5: Idle speed and redline

### Takeaway
Neither idle speed nor official redline was found. The dyno article gives a limiter near 10,600 rpm, which is the only rpm ceiling reported.

### Cited Findings
- Limiter around 10,600 rpm (dyno article) — **Verified (fetch, as reported by the article; not an official Honda figure)**: [Otomotifnet dyno article](https://otomotifnet.gridoto.com/read/232535641/all-new-honda-cbr150r-dites-dyno-ternyata-tenaga-on-wheel-segini?page=all)

### Gaps
- Idle speed: **Gap**. Dealer sources do not list it; service manual needed.
- Official redline: **Gap**. The 10,600 rpm figure is a limiter from a press article, not a manufacturer redline.

## Other engine facts (fuel, ignition, oil, cooling, electrics)

- Fuel system: PGM-FI (programmed fuel injection) — **Verified (dealer)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/)
- Injector spec, throttle body size: **Gap** (see Q3).
- Ignition: full transistorized — **Verified (dealer)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/); ignition timing (degrees BTDC): **Gap**
- Spark plug: NGK MR9C-9N or ND U27EPR-N9 — **Verified (dealer)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/)
- Engine oil capacity: 1.1 L — **Verified (dealer, two pages)**: [Honda Cengkareng](https://www.hondacengkareng.com/motor/honda-cbr-150r/); [Honda Mandala Jaya Abadi](https://www.hondamandalajayaabadi.com/spesifikasi-honda-cbr150r.html). Oil grade not found: **Gap**.
- Cooling: liquid-cooled with auto fan — **Verified (dealer)**. **Contradiction:** an Autofun search snippet describes the 2021 model as air-cooled; the Autofun page was 403 and the snippet is secondary. Dealer data takes precedence; flagged, not adopted.
- Clutch: wet, 6-speed manual, shift pattern 1-N-2-3-4-5-6 — **Verified (dealer)**
- Starter: electric — **Verified (dealer)**
- Battery: MF wet 12 V 5 Ah — **Verified (dealer)**

## Source list

- [Honda Cengkareng CBR 150R](https://www.hondacengkareng.com/motor/honda-cbr-150r/) (dealer spec block, lists K45R 2021-2026 in model list; spec block not K-coded)
- [Honda Mandala Jaya Abadi CBR150R](https://www.hondamandalajayaabadi.com/spesifikasi-honda-cbr150r.html) (dealer spec block, no K-code)
- [Honda Cengkareng AHM launch 2016](https://www.hondacengkareng.com/ahm-rilis-all-new-honda-cbr-150r/) (K45G era, not K45R)
- [Otomotifnet dyno test](https://otomotifnet.gridoto.com/read/232535641/all-new-honda-cbr150r-dites-dyno-ternyata-tenaga-on-wheel-segini?page=all) (independent on-wheel dyno, Jan 2021)
- [Wikipedia Honda CBR150R](https://en.wikipedia.org/wiki/Honda_CBR150R) (merged table, contradictions noted)
- [Autofun spec article](https://www.autofun.co.id/berita-motor/Simak-Spesifikasi-All-New-Honda-CBR150R-2021-Kena-Update-Fitur-dan-Desain-Makin-Agresif-22412) (403, snippet only)
- [Gridoto CB150R throttle reamer](https://www.gridoto.com/read/222473816/honda-pcx-dan-adv150-pasang-throttle-body-reamer-segini-harganya) (CB150R, not K45R)

## Recommended next steps (not done)
- Pull the AHM or Honda Indonesia K45R owner's manual or service manual PDF (valve clearance, idle, cam, ignition timing, throttle body, valve sizes).
- Fetch the full Otomotifnet dyno article for test date and conditions (the paginated fetch had none).
- Search Motoplus, Oto, or Motorplus for a K45R dyno with correction factors.
