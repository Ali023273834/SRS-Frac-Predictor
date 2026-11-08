# Model card: SRS/SRT fractionation predictor, model v3

| Item | Value |
|---|---|
| Version | Model v3, **locked on 7 November 2026** (before its predictions for the validation cases were computed). |
| Developer | Ali A. Eid, Radiation Oncology Department, National Cancer Institute, Cairo University |
| Data of record | MASTER_FINAL_v13. Atlas: 367 saturated plans. OAR cohort: 12 patients, 48 distance points. |
| Software | MATLAB R2025b (Statistics and Machine Learning Toolbox), script `final_model_v3.m`, seed 20261102 |
| Locked export | `model_v3_export.json`, SHA-256 `213b1b04b61c4da22025f561bd39d30fab4dcaa6c3fc6e57056d02f50b7c52dd` |
| Reporting | TRIPOD+AI |

## Intended use

**What it supports:**
- Choosing between single-fraction SRS, 3 and 5 fractions **before planning**, for an intracranial target treated with single-isocentre VMAT.
- Choosing the saturated atlas plan to start from.

**Who uses it:** medical physicists and radiation oncologists, in research and in prospective or multi-institutional validation.

**Out of scope:**
- clinical decisions without independent review;
- other delivery platforms or planning systems without local validation;
- re-irradiation (cumulative dose);
- multiple targets;
- OARs other than the brainstem and optic apparatus, unless used by analogy;
- targets larger than 40 cm³.

## Inputs and outputs

**Inputs:**
- PTV volume (cm³).
- Location: peripheral if 10–30% of the target circumference is in contact with the inner table of the skull; central if there is no contact with the inner table.
- Shape: regular or irregular (an irregular, lobulated contour; in the atlas, irregular contours were the regular contour deformed at the same volume).
- Optionally:
  - the nearest serial OAR, the PTV–OAR distance (mm) and the contact length or facing extent;
  - the target region (used only to show the arc class solution).

**Outputs:**
- Predicted normal-brain dose (whole brain minus target) for each scheme:

  | Scheme | Metric |
  |---|---|
  | SRS | V12Gy |
  | 27 Gy/3 | V20Gy |
  | 30 Gy/5 | V24Gy |

- The recommended scheme and the component that determined it.
- The nearest saturated atlas plan and the expected plan quality (CI_RTOG, Paddick CI, GI, Q_RTOG).
- The predicted OAR maximum dose for the brain-based scheme (% of the TG-101 limit).

## Training data

**Planning atlas:**
- 93 configurations: 65 clinically derived, 28 phantom-based; 0.092–40 cm³.
- Each configuration planned in four scenarios (central/peripheral × regular/irregular).
- Prescriptions:
  - SRS 18–24 Gy (dose graded by volume, RTOG 90-05 based);
  - 27 Gy in 3 fractions;
  - 30 Gy in 5 fractions.
- 367 plans in total: 248 SRS, 59 three-fraction, 60 five-fraction.
- Every plan optimised to saturation.
- Planning system: Elekta Versa HD (6 MV FFF), Monaco v5.5, Monte Carlo dose on a 1 mm grid, 1–2 mm GTV/CTV-to-PTV margin.

**Brain limits:**
- SRS V12Gy < 10 cm³
- 3 fractions V20Gy < 20 cm³
- 5 fractions V24Gy < 20 cm³

A value equal to the limit is marginal.

**OAR cohort:**
- 12 patients: 9 with targets abutting the brainstem, 3 abutting the chiasm.
- Each planned clinically at 0 mm.
- The original scheme was re-simulated on a phantom at 3, 6 and 10 mm (48 distance points).
- OAR limit: TG-101 maximum point dose.

## Choice of algorithms

Eight model families were compared in MATLAB, on the development data only:
- whole volumes held out for brain dose and scheme;
- whole patients held out for OAR dose.

The algorithm with the lowest held-out error was kept for each part.

| Part | Best algorithm | Held-out performance | Next best |
|---|---|---|---|
| Brain dose | Gaussian process | MAE 0.31 cm³ (all schemes) | SVM 0.35; neural network 0.43; boosted trees 0.49; random forest 0.57 |
| OAR dose | Random forest | R² 0.75 | Boosted trees 0.72; linear 0.71; Gaussian process 0.49 |
| Scheme | Decision rule | 0 too few fractions | Every classifier gave 5–33 too few fractions (random forest 6, SVM 8, neural network 16) |

The full comparison tables are reported with the article.

## Models

| Component | Method |
|---|---|
| Brain dose (per scheme) | Gaussian process regression (`fitrgp`): ARD squared-exponential kernel, constant basis, standardized predictors. Inputs: log volume, central, irregular. Response: log brain dose. |
| Plan quality (per scheme and metric) | Gaussian process regression, same settings, untransformed response. Trained on the same 367 atlas plans. |
| OAR dose (% of TG-101 limit) | Random forest (`fitrensemble`, bagging): 500 trees, minimum leaf 2, all predictors sampled at each split. Inputs: distance, chiasm vs brainstem, contact length, volume, original regimen (SRS 24 Gy, SRS 18 Gy, 27 Gy/3). |
| MTV table | Shortest scheme known to be compliant at each tested volume and scenario, inferred monotonically from the tested volumes. |
| Decision rule | Longest of the MTV-table scheme, the first scheme predicted below its limit within its tested volume range, and the OAR rule (see README). |

## Development performance (internal; whole volumes or whole patients held out)

**Brain dose (Gaussian process):**

| Scheme | n | R² | RMSE (cm³) | MAE (cm³) | Compliance status correct | Predicted within limit but violated |
|---|---|---|---|---|---|---|
| SRS | 248 | 0.990 | 0.29 | 0.22 | 245/248 | 0 |
| 3 fractions | 59 | 0.979 | 0.80 | 0.60 | 55/59 | 0 |
| 5 fractions | 60 | 0.984 | 0.54 | 0.37 | 57/60 | 0 |
| All | 367 | 0.996 | — | 0.31 | — | 0 |

The app shows these RMSEs as ±.

**Decision rule (320 volume × scenario cases):**
- 308 of 320 correct (96.3%), weighted κ 0.95.
- Too few fractions: 0.
- One step more: 12 (all at or just below a maximum tolerable volume).
- Each component alone also gave no case with too few fractions:
  - Gaussian process alone: 310 of 320 correct;
  - MTV table alone: 308 of 320 correct.

  Combining them is a safeguard: if either component fails, the other still applies.

**OAR dose (random forest):**
- R² 0.75, RMSE 11.5% of the limit, MAE 8.1%.
- The met/exceeded status was correct for 44 of 48 points.
- 2 points were predicted to meet the limit but exceeded it.

**Combined rule in the OAR cohort:** it chose the delivered scheme in 12 of 12 patients. The rule was derived from these patients, so this is not independent validation.

**Plan quality (Gaussian process, held-out R²):**

| Metric | SRS | 3 fractions | 5 fractions |
|---|---|---|---|
| CI_RTOG | 0.50 | 0.44 | 0.11 |
| Paddick CI | 0.75 | 0.10 | 0.20 |
| GI | 0.63 | 0.75 | 0.46 |
| Q_RTOG | 0.68 | 0.34 | 0.44 |

Use these predictions as a guide, not as goals.

## Independent validation (locked model v3)

**Cases:** 24 clinical plans not used in development:
- consecutive targets planned between November 2025 and August 2026 by the same two planners;
- started from the nearest atlas template and optimised to saturation;
- accepted for treatment at first review;
- four re-irradiations excluded, because their scheme was set by cumulative dose.

The case list was fixed before any prediction was computed.

**Earlier use of these cases:** they had already been used to test model v2 (random forest). To keep the test independent:
- the algorithms for v3 were chosen on development data only;
- v3 was locked before its predictions for these cases were computed.

**Corrections to the case records (7 November 2026, verified by the author):**
- the volume of one three-fraction plan was 17 cm³, not 27 cm³;
- three five-fraction plans were identified as re-irradiations and excluded like the first.

The locked model was then applied again, without any change.

| Delivered scheme | n | MAE (cm³) | Mean difference, measured − predicted (cm³) | Recommendation = delivered |
|---|---|---|---|---|
| SRS (V12Gy) | 16 | 0.65 | −0.17 | 16/16 |
| 3 fractions (V20Gy) | 4 | 2.92 | −1.91 | 4/4 |
| 5 fractions (V24Gy) | 4 | 0.93 | −0.74 | 4/4 |
| All | 24 | 1.08 (median 0.70) | −0.56 | 24/24 |

**Agreement and calibration (all plans):**
- 95% limits of agreement −3.63 to 2.52 cm³;
- calibration: measured = 0.42 + 0.90 × predicted;
- Spearman ρ 0.88.

**Compliance:** the predicted status agreed with the measured status in all 24 plans.

**Largest errors:** two central three-fraction targets of 17–18 cm³ received less brain dose than predicted (V20Gy 8.0 and 11.0 cm³ against 13.3 and 15.3 cm³). For these plans the model erred on the safe side.

**Plan quality (MAE):** CI_RTOG 0.052, Paddick CI 0.046, GI 0.69, Q_RTOG 0.057.

**Re-irradiation (outside the model):** the model does not consider the dose already given. For the four excluded re-irradiations:
- the central 31-cm³ target: five fractions recommended, as delivered;
- the three peripheral targets of 22–28 cm³: three fractions recommended, although they were treated with five because of their cumulative dose.

When re-irradiation is selected, the app shows a warning and gives its predictions for reference only.

**Not tested:** the OAR rule, because distance and contact were not recorded for these plans.

## Implementation in the app

**How the models are stored:**
- **Gaussian-process models:** the app evaluates the exact MATLAB prediction formula, pred = β + σf² Σⱼ αⱼ exp(−½ Σd ((zd − Aⱼd)/ℓd)²). It uses the exported parameters:
  - standardization: mean and SD;
  - length scales ℓ, signal SD σf and constant β;
  - active set A and weights α.

  For brain dose the prediction is then back-transformed with exp().
- **OAR forest:** a forest with two continuous inputs (distance and volume) plus discrete inputs is piecewise constant. It was stored as a distance × volume table between its split points for every combination of the other inputs. MATLAB trees send x < cut to the left, and the app uses the same rule.

**Checks:**
- Before export, MATLAB verified that the exported formula reproduces `predict()`: largest difference 1.8 × 10⁻¹³.
- The OAR tables reproduced `predict()` exactly at 2,000 points, including exact cut values.
- `tests/run_tests.js` compares the app with MATLAB in 28,057 checks, all within 10⁻⁹:
  - brain dose and plan quality at 1,580 inputs;
  - OAR dose at 1,952 points;
  - 800 combined brain and OAR decisions;
  - the recommended schemes of the 24 validation plans;
  - the re-irradiation warning.
- The validation workbook computes the same predictions with spreadsheet formulas.

## Limitations

- **Setting:** single institution, planning system, linac and technique. 28 of 93 configurations are phantom-based.
- **Discrete sampling:**
  - Volumes and OAR distances (0, 3, 6, 10 mm) were sampled at discrete values, so each threshold lies between the tested values.
  - Below a scheme's atlas range (3FR < 14 cm³, 5FR < 21 cm³), the app shows the brain dose at the smallest tested volume as an upper bound.
- **OAR model:**
  - It rests on 12 patients and two OAR types.
  - Each regimen was seen only over a narrow volume range: SRS 24 Gy 0.55–1.35 cm³, SRS 18 Gy 2.42–12.62 cm³, 27 Gy/3 16.35–17.7 cm³.
- **Not modelled:** cumulative dose (re-irradiation: the app warns), multiple targets, delineation uncertainty and deliverability.
- **Validation so far:** retrospective, single-institution and small (24 plans, only 8 of them fractionated). Prospective validation, in which the shorter scheme is also planned, and validation in other institutions are still needed.

## Updating

Any retraining creates a new model version and needs a new validation. To lock and release it:
1. Run `final_model_v3.m` (or its successor) in MATLAB. It records the SHA-256 checksum of the export.
2. Rebuild the app with `export_app_model_v3.py`.
3. Rerun the tests.
4. Publish a new release with its own DOI.
