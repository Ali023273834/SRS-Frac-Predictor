# Validation of the fractionation model

`VALIDATION_new_cases_fractionation_model_v3.xlsx` collects new patients for prospective or multi-institutional validation of the locked model v3 (MATLAB).

It calculates its predictions with spreadsheet formulas from the same locked model as the app:
- the Gaussian-process brain-dose models (parameters in the GPR sheet);
- the MTV table (TABLES sheet);
- the OAR rule.

For the same inputs, the recommended scheme in the workbook and in `index.html` is identical. A check on 300 random cases found all 2,100 values in agreement.

1. **Before planning, enter in the yellow columns:** case ID, volume, location, shape, OAR, distance and contact. Contact is needed below 6 mm. The blue columns then show:
   - the brain-based scheme;
   - the predicted brain dose;
   - the recommended scheme.

   The app shows the same values with explanations.
2. **Plan the recommended scheme.** Where possible, also plan the next shorter scheme, so that the shortest compliant scheme is known.
3. **After planning, enter in the green columns:** the scheme planned, the brain dose, the OAR Dmax and the shortest scheme that met both the brain and the OAR limits.
4. **Read the SUMMARY sheet:**
   - agreement;
   - too few fractions (the safety error);
   - too many fractions;
   - brain-dose error.

**Do not enter re-irradiations.** The model does not consider the dose already given, so its scheme can be too short. Re-irradiation is outside its scope.

**Pre-specified acceptance:**
- no "too few" with a brain or OAR limit exceeded;
- agreement ≥ 85%.

**Multi-institutional use:** departments using other systems can submit their anonymised rows, with the planning system and technique stated, to the corresponding author.
