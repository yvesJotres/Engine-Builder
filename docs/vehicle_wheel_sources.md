# Vehicle wheel dimensions

The wheelbase is in millimetres; tyre sizes are width/aspect-ratio-rim. Values describe the cited variants, which may differ across model years and markets. Tyre outside radii are nominal geometry, not measured rolling radii.

| Preset | Wheelbase mm | Front | Rear | Source and applicability |
| --- | ---: | --- | --- | --- |
| CBR150R K45N | 1309 | 100/80-17 | 130/70-17 | [Honda 2018 K45N owner's manual](https://2rom-prd-data.hondamotopub.com/om/AHJ/CBR150R/2018/BPP_CBR150R%20WEB.pdf), specifications page 112. |
| CBR250RR 2017 Japan | 1390 | 110/70-17 | 140/70-17 | [Honda 2017 release](https://global.honda/jp/news/2017/2170418-cbr250rr.html). |
| CBR250RR SP QS 2023 Indonesia | 1385 | 110/70-17 | 140/70-17 | [Honda 2023 owner manual](https://2rom-prd-data.hondamotopub.com/om/AHJ/CBR250RR/2023/CBR250RR_4HK64NM01_0.pdf), specifications page 118; covers SP ABS-QS Indonesia. |
| CBR1000RR-R Fireblade SP 2020 | 1455 | 120/70-17 | 200/55-17 | [Honda 2020 SC82 specification](https://global.honda/jp/news/2020/2200305-cbr1000rr-r.html); Japan model corroborates wheelbase for the European preset. |
| ZX-25R / SE | 1380 | 110/70-17 | 150/60-17 | [Kawasaki brochure](https://cdn.kawasaki.com.my/file/product/1726713400.3kopc.pdf); brochure is a later Malaysian version, 2020 trim requires confirmation. |
| MT-07 | 1400 | 120/70-17 | 180/55-17 | [Yamaha 2022 factsheet](https://cdn2.yamaha-motor.eu/prod/product-assets/2022/MT07/Factsheets/2022-MT07_en-GB.pdf). |
| YZF-R1M 2015 | 1405 | 120/70-17 | 200/55-17 | [Yamaha 2015 European specifications](https://global.yamaha-motor.com/news/2014/1104/yzf-r1.html). |
| Panigale V4 1103 | 1469 | 120/70-17 | 200/60-17 | [Ducati 2018 product document](https://www.ducatidanmark.dk/globalassets/ducati-tekniskdata/2018/my18_ducati_panigale-produkt.pdf) and [2018 technical sheet](https://cdn.imagearchive.com/ducatiforum/data/attach/20/20833-2018-ducati-panigale-v4-technical-specifications.pdf). |
| RD350 1983 | 1385 | 90/90-18 | 110/80-18 | [Yamaha 1983 RD350LC YPVS brochure](https://davesbikebrochures.weebly.com/uploads/4/8/4/5/4845046/_rd350ypvs1983brochure.pdf); preset does not name a precise variant. |

The generic Sportster 883 lacks a year and trim; the V3R 900 has no confirmed production dimensions; TRX520 is a four-wheel ATV; and several Mercedes/F1 entries specify engines rather than identifiable vehicles. They retain fallback geometry until their vehicle configurations are identified and, for the ATV, a four-wheel model exists. The Centodieci has existing car dimensions; its tyre specifications require a separate verification.

Wheelbase positions the visual wheel centres along the ground plane. It is not yet used for steering, pitch, wheelie or weight-transfer physics. The automated dimensions test checks every loaded preset, including fallbacks, and separately asserts the ten sourced motorcycle values above. It cannot prove a fallback is the specification of an unidentified model. Legacy saved builds with their own wheelbase retain that saved value.
