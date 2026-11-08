# MATLAB code: development, lock and validation of model v3

This folder documents how the model behind the app was developed, trained, locked and validated in **MATLAB R2025b** (Statistics and Machine Learning Toolbox).

## Files

| File | What it does |
|---|---|
| `compare_models.m` | Chooses the algorithms. Compares up to eight model families on the development data only, with grouped cross-validation: whole volumes held out for brain dose and scheme, whole patients for OAR dose. |
| `final_model_v3.m` | Builds the final models. It: (1) validates them with whole volumes or patients held out; (2) trains them on all development data; (3) exports and **locks** them (SHA-256 of the export); (4) writes the test vectors used by the app; (5) scores the validation plans. |
| `validate_locked_v3.m` | Scores the validation plans again with the **locked** model, without retraining. It was run after two corrections to the case records: one volume corrected, and three more re-irradiations excluded. It also scores the four excluded re-irradiations, for information only. |
| `model_v3_export.json` | The locked model exactly as exported by MATLAB: Gaussian-process parameters, OAR forest tables and MTV labels. |
| `logs/` | The MATLAB output of each script, with date, MATLAB version and all results. |
| `SHA256SUMS.txt` | SHA-256 checksums of the files above. |

The scripts were run in this order: `compare_models.m` (6 Nov 2026), `final_model_v3.m` (7 Nov 2026), `validate_locked_v3.m` (7 Nov 2026).

In `compare_models.m`, "locked" refers to the earlier random-forest version of the model (v2). The final model v3 was chosen from this comparison: Gaussian process regression for brain dose and plan quality, and random forest for OAR dose.

## From MATLAB to the app

The chain from training to the app can be checked:

1. **At the lock**, `final_model_v3.m` printed the SHA-256 of `model_v3_export.json` in `logs/MATLAB_output_final_model_v3.txt`:

   `213b1b04b61c4da22025f561bd39d30fab4dcaa6c3fc6e57056d02f50b7c52dd` (7 Nov 2026, 19:10:26)

   The file in this folder has the same checksum.
2. **The app's model** (`model/model_v3_tables.json`, also embedded in `index.html`) carries the same parameters, unchanged. Only the key names are relabelled (for example F3 → 3FR, CI → c1i1).
3. **`tests/run_tests.js`** checks this. It confirms the checksum and that every Gaussian-process parameter, OAR table and MTV label in the app equals the MATLAB export. It also checks that the app reproduces the MATLAB predictions to 10⁻⁹:
   - brain dose and plan quality at 1,580 inputs;
   - OAR dose at 1,952 points;
   - the recommendations for the validation plans.

## Running the scripts

The scripts read these de-identified input tables from the same folder. The tables are **not included** here; they will be published with the article.

| Input file | Content | Rows |
|---|---|---|
| `brain_regression.csv` | scheme, configuration, volume, location, shape, brain dose | 367 atlas plans |
| `atlas_quality.csv` | the same plans with CI_RTOG, Paddick CI, GI and Q_RTOG | 367 |
| `scheme_classification.csv` | shortest compliant scheme per tested volume and scenario | 320 |
| `oar_regression.csv` | OAR cohort: distance, OAR type, contact, volume, original scheme, OAR dose (% of TG-101 limit) | 48 points, 12 patients |
| `validation_cases.csv` | independent validation plans | 24 |
| `reirradiation_cases.csv` | excluded re-irradiations (scored for information only) | 4 |

**Notes:**
- `final_model_v3.m` takes 10–20 minutes. The others take seconds to minutes.
- `validate_locked_v3.m` also writes the input of the SPSS validation analysis to the project folder `../../02_SPSS/data_csv`. This step needs the project's folder structure.

## Note on the log of `compare_models.m`

The naive Bayes classifier produced 80 identical MATLAB warnings ("'CategoricalPredictors' will be updated to include all 'mvmn' predictors"). They are harmless, but they listed local file paths, so they were removed from `logs/MATLAB_output_compare_models.txt`. No result line was changed. The other logs are unedited.
