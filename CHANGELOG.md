# Changelog

## 1.2.0 (2026-11-11)

- The template panel and the copied summary show the **Monaco template name** for the case: scheme (SRS / SRT3FR / SRT5FR; the prescription is stored inside the template, not in its name), PTV volume bin (0–0.5, 0.5–2, 2–4, 4–10, then 5-cm³ bins to 40), location and shape (CR/CIR/PR/PIR), then the arc set code of the chosen region — e.g. SRS-(0.5-2cc)-CIR-OCC_L. A placeholder is shown until a region is chosen; no name when the recommendation is beyond five fractions.
- For targets with an equivalent PTV diameter of about 2 cm or more, an information note gives published clinical outcomes of single-fraction versus fractionated SRS (Minniti 2016: radionecrosis 20% vs 8%, 1-year local control 77% vs 91%; Lehrer 2019: 23.1% vs 7.3%, local control not significantly different). These are clinical series, not a prediction for the patient.
- No change to the model, the recommendation or the arc tables: the locked MATLAB export and all 28,097 checks are unchanged.

## 1.1.0 (2026-11-08): archived at Zenodo, https://doi.org/10.5281/zenodo.24051812

- `matlab/`: the MATLAB code that chose, trained, locked and validated the model, with its logs, the locked export and checksums. The tests confirm that the app's model equals that export.
- `.gitattributes`, so that GitHub recognises the `.m` files as MATLAB.
- The DOI was added to `README.md` and `CITATION.cff`.
- Test suite: 28,097 checks, including the comparison of the app's model with the MATLAB export.

## 1.0.0 (2026-11-08): first public release

**Model v3**, developed in MATLAB R2025b and locked on 7 November 2026. It replaces the scikit-learn random forests of model v2.

**Choice of algorithms:** eight model families were compared on the development data only, with grouped cross-validation.

| Part | Algorithm |
|---|---|
| Brain dose and plan quality | Gaussian process regression (ARD squared-exponential kernel) |
| OAR dose | Random forest (500 bagged trees) |
| Scheme | Decision rule, unchanged |

**Development (whole volumes held out):**
- Brain-dose MAE 0.31 cm³ (v2: 0.52).
- The rule was correct in 308 of 320 cases (v2: 306), with no case of too few fractions.

**Independent validation (24 clinical plans):**
- Brain-dose MAE 1.08 cm³.
- The recommended scheme matched the delivered scheme in all 24.
- Case records corrected on 7 November 2026: one volume (17, not 27 cm³); three more re-irradiations identified and excluded (four in total).

**App:**
- Evaluates the Gaussian-process formula exactly; the OAR forest is stored as interval tables.
- Test suite: 28,057 checks against MATLAB, all within 1e-9.
- New *Re-irradiation* input: shows a warning that the model does not consider prior dose, and marks the predictions as reference only.
- The classifier view was removed. The details panel now shows the MATLAB development and validation performance.
- Below a scheme's atlas range, the app shows the brain dose at the smallest tested volume as an upper bound.


## Development history (not released)

### Model v2 locked (2026-11-06)

- **Model v2 locked** on 6 November 2026, before the independent validation cases were scored. Its tables are unchanged from 0.9.0.
- **Independent validation on 27 clinical plans:**
  - brain-dose MAE 1.62 cm³, with no systematic bias;
  - the recommended scheme matched the delivered scheme in 22 of 27.
- **Target definitions updated:**
  - peripheral = 10–30% of the circumference in contact with the inner table;
  - central = no contact;
  - irregular = deformed (lobulated) contour.
- **Status banner** shows the locked status.
- **Exports are bit-identical** between runs (sequential averaging).

### Candidate model v2 (2026-11-05)

First release of the browser app. It contains candidate model v2, which is not yet validated on new patients.

**Model components:**
- brain-dose random forests for SRS, 3 and 5 fractions;
- plan-quality forests;
- MTV table;
- OAR random forest;
- OAR distance rule;
- classifier, shown for transparency only.

**Implementation:**
- The model is exported to exact interval tables and embedded in `index.html`.
- Test suite: 91,920 values from 6,180 inputs reproduce the Python model to 1e-9.
- The validation workbook uses the same tables as the app.

## Planned

- Prospective validation in which the shorter scheme is also planned.
- Validation in other institutions.
