# 13. Sources

[Index](README.md) · Physics reference

## Primary sources
- Heywood, J. B., *Internal Combustion Engine Fundamentals*, McGraw-Hill. Chapters on valve flow, heat transfer, friction, combustion.
- Woschni, G. (1967). SAE 670931. https://doi.org/10.4271/670931
- Patton, K., Nitschke, R., Heywood, J. (1989). SAE 890836. https://doi.org/10.4271/890836
- Chen, S. K., Flynn, P. F. (1965). SAE 650733, "Development of a Single Cylinder Compression Ignition Research Engine" (International Harvester). The SAE record page was opened: abstract is about engine design; no friction equation appears on the page. The friction correlation is attributed to this paper by secondary sources; full text not reached. https://saemobilus.sae.org/papers/development-a-single-cylinder-compression-ignition-research-engine-650733
- Annand, W. J. D. (1963). Heat transfer in the cylinders of reciprocating internal combustion engines. (Cited; not reached.)
- Metghalchi, M., Keck, J. C. (1982). Burning velocities of mixtures of air with methanol, isooctane, and indolene at high pressure and temperature. Combustion and Flame 48, 191. Hosted at https://james-keck-memorial-collection.unibs.it/JCKeck-papers/MetghalchiKeck-CombustionFlame-48-191-1982.pdf (full text read; see section 7.3).
- Wiebe, I. I. (1970). Burn function. (Cited; not reached.)
- SAE J1349, correction factor standard (formula quoted by secondary sites only; SAE document not reached).
- DIN 70020, correction factor standard (formula not found in sources reached).
- Taylor, C. F., *The Internal Combustion Engine in Theory and Practice*, MIT Press. (Cited; not reached.)
- Pulkrabek, W. W., *Engineering Fundamentals of the Internal Combustion Engine*. (Textbook; not reached.)

## Secondary (checks only)
- SAE 820154, poppet valve static and dynamic flow coefficients. https://saemobilus.sae.org/papers/air-flow-poppet-inlet-valves-analysis-static-dynamic-flow-coefficients-820154
- SAE 962527, discharge coefficients and engine simulation accuracy. https://saemobilus.sae.org/content/962527
- SAE 2009-01-1984, Pipitone friction model. https://saemobilus.sae.org/content/2009-01-1984/
- SAE 2014 heat-transfer comparison. https://saemobilus.sae.org/papers/heat-transfer-evaluation-internal-combustion-engine-operating-wet-ethanol-fuel-part-b-2014-36-0357
- SAE 2020-01-0802, local heat flux and SI/HCCI heat transfer. https://saemobilus.sae.org/content/2020-01-0802
- Colorado State heat-transfer notes. https://www.engr.colostate.edu/~allan/heat_trans/page7a/page7a.html
- Purdue ICEC paper, heat transfer and Reynolds analogy. https://docs.lib.purdue.edu/cgi/viewcontent.cgi?article=1657&context=icec
- MIT 2.61 lecture notes, SI engine combustion. https://web.mit.edu/2.61/www/Lecture%20notes/Lec.%2009%20SI%20engine%20combustion%20I.pdf
- Burn-duration correlation study, SI engines. https://www.sciencedirect.com/science/article/abs/pii/S019689040300253X
- Thesis on volumetric efficiency modelling of four-stroke engines. https://mountainscholar.org/bitstreams/0d6c0993-76a7-4452-955d-772d600fc1df/download
- Simplified FMEP for fuel-consumption simulation. https://link.springer.com/article/10.1007/s42452-021-04892-y
- Taylor inlet Mach index, forum discussion. https://forums.autosport.com/topic/105336-intake-valve-sizing-formula-clash/
- Heywood flame-development values, GitHub discussion. https://github.com/pangtuwi/ESA.NET/pull/237
- ATG engine-sim source, fuel and combustion code (laminar flame correlation, turbulence and flame-speed model). Local copy at `D:\Projects\ATG Source\engine-sim\src\fuel.cpp` and `src\combustion_chamber.cpp`.

---

## Added in the fact-check pass (secondary unless noted)
- SAE 852090, The Optimum Combustion Phasing Angle, a convenient engine tuning criterion (CA50 about 7–8° ATDC). https://saemobilus.sae.org/content/852090
- SAE 2012-01-0902, CA50 near 8° ATDC for optimum efficiency. https://saemobilus.sae.org/content/2012-01-0902
- SAE 890759, MBT control using the crank angle of maximum pressure (12–14° ATDC at MBT). https://saemobilus.sae.org/content/890759
- Energy Reports (2021), rolling resistance of five motorcycle tyres under ISO 18164 (8.9 to 13.7 N/kN). https://doaj.org/article/1b10d8e62ed148258b4f1a3aa2948c83
- Engineering ToolBox, air composition and molar mass. https://engineeringtoolbox.com/air-composition-d_212.html
- IEA AMF, gasoline fuel properties (LHV 43 MJ/kg; density 720–775 kg/m³). https://iea-amf.org/content/fuel_information/diesel_gasoline/fuel_properties
- NPTEL, properties of liquid fuels (gasoline LHV 43.5 MJ/kg; heat of vaporisation 380 kJ/kg). https://archive.nptel.ac.in/content/storage2/courses/101104014/lecture3/3_4.htm
- Sandia ECN, fuel properties table (iso-octane density 690.3 kg/m³; enthalpy of vaporisation 308.4 kJ/kg). https://ecn.sandia.gov/?p=57
- Metghalchi and Keck (1982), full text read; PDF hosted by the James Keck memorial collection (power-law form, exponents and isooctane parameters). https://james-keck-memorial-collection.unibs.it/JCKeck-papers/MetghalchiKeck-CombustionFlame-48-191-1982.pdf
- Colorado State, engine heat transfer correlations (Annand form and coefficient range 0.35–0.8). https://www.engr.colostate.edu/~allan/heat_trans/page7aa/page7aa.html
- OpenModelica documentation, Annand (1963) citation, Proc. IMechE 177(36). https://build.openmodelica.org/Documentation/ThermoCycle.Components.Units.ExpansionAndCompressionMachines.Reciprocating.HeatTransfer.Annand1963.html
- x-engineer.org, rod ratio conventions and small-engine range 3–4. https://x-engineer.org/?p=2358
- Engine heat-transfer lecture notes (order of hottest components; 1–3 MW/m² peak heat flux). Found through search; university notes, not read in full.


## Read in full text (second and third passes)
- Qasemian, A. and Rezaei, M. (2020). Improving combustion chamber heat transfer correlation of an HCCI engine in order to achieve a more accurate thermodynamic model. IOP Conf. Ser.: Mater. Sci. Eng. 671, 012019 (open access). Local copy: `docs/papers/Qasemian_2020_IOP_Conf._Ser.__Mater._Sci._Eng._671_012019.pdf`. Read in full. Gives the Woschni equations, the per-phase C1 and C2 values, and the original constant table; the paper is about HCCI and modifies the constants.
- Metghalchi, M. and Keck, J. C. (1982). Burning velocities of mixtures of air with methanol, isooctane, and indolene at high pressure and temperature. Combustion and Flame 48, 191–210. Full text read: https://james-keck-memorial-collection.unibs.it/JCKeck-papers/MetghalchiKeck-CombustionFlame-48-191-1982.pdf
- Tadros, A. et al. (2025). Engine optimization model for accurate prediction of friction model in marine dual-fuel engine. Algorithms 18(7), 415 (open access). Read for its Chen–Flynn "standard" set (Table 4). https://www.mdpi.com/1999-4893/18/7/415
- Open-source engine-simulation issue #26 (Woschni heat-transfer implementation; no cited source). https://github.com/thegoodcorg/Engine-Simulation/issues/26

## Cited by Qasemian and Rezaei (2020), not read
- Chang, J., Guralp, O., Filipi, Z., Assanis, D. (2004). New heat transfer correlation for an HCCI engine derived from measurements of instantaneous surface heat flux. SAE 2004-01-2996. (Chang's HCCI Woschni variant.)
- Annand, W. J. D. and Ma, T. H. (1970–71). Instantaneous heat transfer rates to the cylinder head surface of a small compression-ignition engine. Proc. IMechE 185, 976–987.
- Hohenberg, G. F. (1979). Advanced approaches for heat transfer calculations. SAE 790825.
- Hensel, S., Sarikoc, F. et al. (2009). A new model to describe the heat transfer in HCCI gasoline engines. SAE Int. J. Engines 2, 33–47.
- Soyhan, H. S., Yasar, H. et al. (2008/2010). Evaluation of heat transfer correlations for HCCI engine modelling.
- Neshat, E. et al. (2015). Multi-zone HCCI model with a new convective heat-transfer relation.
- Fathi, M. et al. (2017). Single-zone and multi-zone modelling of DI-HCCI engines.

## Local copies in `docs/papers/` (read in full where stated)
- Heywood, J. B., *Internal Combustion Engine Fundamentals* (McGraw-Hill, 1988). Local copy `docs/papers/DE0047750EE23D1A6E5E3C1257832006912D0.pdf` is only the front matter and contents (9 pages). Useful for the chapter page map (chapter 9 p. 402; chapter 12 p. 668; chapter 13 p. 715+). The chapter text is not in the copy.
- Reitz, R. D. (2018). Internal combustion engines I: fundamentals and performance metrics. Princeton-Combustion Institute Summer School, Hour 3 (UW-Madison). Local copy `docs/papers/reitz_princeton-day1-hour3-2018.pdf`. Read in full. Gives the Chen–Flynn friction form and values (C = 0.25 bar, PF = 0.005, MPSF = 0.1, MPSSF = 0; units not stated), the Wiebe and Woschni model list, and cites Woschni (SAE 670931) and Chen–Flynn (SAE 650733).
- MIT OpenCourseWare, 2.61 Internal Combustion Engines (Spring 2017), reading list: https://ocw.mit.edu/courses/2-61-internal-combustion-engines-spring-2017/pages/readings/. All lecture readings are chapters of Heywood. Lecture 18 is heat transfer (Chapter 12); Lecture 19 is friction (Chapter 13); Lecture 9 is SI combustion (Chapter 9.1–9.5).
- MIT OpenCourseWare, corrections to Heywood (dated 10/29/01), read in full: https://ocw.mit.edu/courses/2-61-internal-combustion-engines-spring-2017/b787d2863a9a55bce2df6c4c8c8d5b16_corrections.pdf. Relevant items: isooctane enthalpies (p. 77), Fig. 12-5 conductivity scale (p. 679), Eq. 9.27 sign (p. 388).
- MIT OpenCourseWare annotated bibliography (not opened): https://ocw.mit.edu/courses/2-61-internal-combustion-engines-spring-2017/resources/ice_bibliography/
