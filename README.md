# SRS/SRT Fractionation Predictor — TRIAL COPY

> **Trial copy (10 Nov 2026). Do not upload.** It adds a cited note on published clinical outcomes for targets of about 2 cm or more (see CHANGELOG). The published app is in `08_APP/SRS-Frac-Predictor`.

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24051812.svg)](https://doi.org/10.5281/zenodo.24051812)

**A research and validation tool for brain SRS/SRT planning. Not for clinical decision-making.**

You enter a target's volume, location and shape, and optionally the nearest serial OAR. The tool then predicts:

- the **normal-brain dose** expected after full optimisation, for each scheme:

  | Scheme | Metric |
  |---|---|
  | Single-fraction SRS | V12Gy |
  | 27 Gy in 3 fractions | V20Gy |
  | 30 Gy in 5 fractions | V24Gy |

- the **shortest scheme** that meets both the brain limit and the OAR limit (TG-101);
- the **saturated atlas plan to start from**: the nearest configuration with its measured dose and plan quality, plus the arc class solution for the target region;
- for an OAR within 10 mm, the **OAR maximum dose** expected if the target is planned in the scheme chosen for the brain.

The app runs the locked **MATLAB model v3** directly in the browser. You don't need MATLAB or Python. The MATLAB code that developed and trained the model is in [`matlab/`](matlab/).

**Live tool:** https://ali023273834.github.io/SRS-Frac-Predictor/  
**Source:** https://github.com/ali023273834/SRS-Frac-Predictor  
**Archived version (v1.1.0):** https://doi.org/10.5281/zenodo.24051812

> **Status: model v3, developed in MATLAB R2025b and locked on 7 November 2026.**
> - Tested on 24 independent clinical plans at the developing institution (re-irradiations excluded): brain-dose MAE 1.1 cm³; the recommended scheme matched the delivered scheme in all 24.
> - Not yet validated in other institutions.
> - Use it for research and validation.

---

## Quick start

1. Open `index.html` in any modern browser. Everything runs locally: no installation, no internet connection, and no data is sent or stored.
2. Enter the PTV volume (cm³). Choose the location and the shape:
   - **Location:** peripheral = 10–30% of the circumference in contact with the inner table; central = no contact.
   - **Shape:** regular or irregular.
3. Optionally, choose the nearest serial OAR and the PTV–OAR distance. Below 6 mm, also choose the contact length or facing extent.
4. If the region was irradiated before, tick *Re-irradiation*: the model does not consider prior dose, so its scheme is then for reference only.
5. Read the recommendation and the reasons for it. Then read the predicted brain dose per scheme, the OAR panel and the template.
6. Use **Copy summary** to attach the prediction to your planning or validation record.

## The model (v3, MATLAB R2025b)

The algorithm for each part was chosen among eight model families. The comparison used grouped cross-validation on the development data only: whole volumes held out, or whole patients for the OAR model.

| Part | Algorithm |
|---|---|
| Brain dose per scheme | Gaussian process regression (fitrgp, ARD squared-exponential kernel, standardized predictors; inputs log volume, central, irregular; response log dose) |
| Expected plan quality (CI_RTOG, Paddick CI, GI, Q_RTOG) | Gaussian process regression, same settings |
| OAR maximum dose (% of TG-101 limit) | Random forest (500 bagged trees, minimum leaf 2) |

**Recommended scheme:** the longest of three answers.

| Component | Rule |
|---|---|
| MTV table | Shortest compliant scheme at the nearest tested atlas volume at or above the target. |
| Brain-dose model | First scheme predicted below its limit within its tested volume range. |
| OAR rule | ≥ 10 mm: no restriction. 6 to < 10 mm: scheme unchanged; check the OAR dose. < 6 mm: point contact → SRS 18 Gy; contact < 5 mm → one scheme longer than the brain-based scheme; contact > 5 mm → 5 fractions. |

**Development (MATLAB, whole volumes held out):**
- Brain-dose R²: 0.990 (SRS), 0.979 (3 fractions), 0.984 (5 fractions); MAE 0.31 cm³.
- No plan was predicted within its limit that actually violated it.
- The rule chose the shortest compliant scheme in 308 of 320 cases, with **0 too few fractions**.
- OAR dose, whole patients held out: R² 0.75, RMSE 11.5% of the limit.

**Independent validation (locked model, 24 clinical plans):**
- Brain-dose MAE 1.08 cm³ (SRS 0.65 cm³).
- Recommended scheme = delivered scheme in all 24.

**Re-irradiation is outside the model:** it does not consider the dose already given. For three of four re-irradiated targets it recommended fewer fractions than were delivered because of their cumulative dose. Tick *Re-irradiation* in the app to see this warning.

## Exactness

- The Gaussian-process models are evaluated with their own MATLAB formula and parameters.
- The OAR forest is stored as interval tables between its split points. It follows the MATLAB split rule: x < cut goes left.
- `tests/run_tests.js` first checks that the app's model is the locked MATLAB export in `matlab/`. The checksum and every parameter must match.
- It then checks the app against MATLAB on about 28,000 values, all of which must agree to 10⁻⁹:
  - brain dose and plan quality at 1,580 inputs;
  - OAR dose at 1,952 inputs;
  - 800 combined brain and OAR decisions;
  - the recommended schemes of the 24 validation plans;
  - the re-irradiation warning.

```
node tests/run_tests.js
```

## Repository contents

| Path | Content |
|---|---|
| `index.html` | The complete app: one file with the model embedded. |
| `model/model_v3_tables.json` | Model parameters, tables and metadata (the same data embedded in `index.html`). |
| `docs/MODEL_CARD.md` | Data, methods, performance, intended use and limitations. |
| `matlab/` | The MATLAB code that chose, trained, locked and validated the model, with its output logs, the locked export and checksums (see `matlab/README.md`). |
| `tests/` | MATLAB reference values and the test runner. |
| `validation/` | Workbook for prospective or multi-institutional validation, with instructions. |
| `DISCLAIMER.md`, `LICENSE`, `CITATION.cff`, `CHANGELOG.md` | Terms, MIT licence, citation, versions. |

## Publishing (GitHub Pages and Zenodo)

1. Create the repository **SRS-Frac-Predictor** and upload all files and folders.
   - `index.html` must be at the top level of the repository.
   - Include `.nojekyll`.
2. Under Settings → Pages, choose *Deploy from a branch*, then **main** and **/ (root)**. After a minute or two the tool is live at the address above.
3. Zenodo:
   1. In Zenodo → GitHub, switch the repository on.
   2. Create a GitHub release.
   3. Zenodo then archives it and issues a DOI. The metadata are read from `CITATION.cff`.

   Release v1.1.0 is archived as https://doi.org/10.5281/zenodo.24051812. For a new version:
   1. Raise `version` in `CITATION.cff` and add an entry to `CHANGELOG.md`.
   2. Create a new release. Zenodo issues a new DOI for it.

## Companion tool

Score the finished plan with the **vPQM plan quality metric**: https://ali023273834.github.io/vPQM-SRS-SRT/ (doi:10.5281/zenodo.24052464).

## Citation

**Software:** Eid, A. A., Attalla, E. M., Fathy, M. M., & Elgebaly, R. H. (2026). *SRS/SRT Fractionation Predictor: brain-dose, OAR and template prediction for stereotactic radiosurgery and radiotherapy* (Version v1.1.0) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.24051812

**Article:** Eid AA, Attalla EM, Fathy MM, Elgebaly RH. *Machine learning–guided fractionation and template selection for stereotactic radiosurgery and radiotherapy based on volume- and location-stratified maximum tolerable volumes* (manuscript in preparation). See `CITATION.cff`.
