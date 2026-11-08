%% 
% 
% It loads the models saved at the lock (final_v3/model_v3.mat), checks that the locked export is unchanged,
% predicts the plans exactly as section 6 of final_model_v3.m, and writes
%   final_v3/MATLAB_output_validation_v3.txt   all results
%   final_v3/validation_predictions_v3.csv     (the earlier file is kept as validation_predictions_v3_T05_27cc.csv)
%   ../../02_SPSS/data_csv/validation.csv      input of SPSS Section 13
%   final_v3/reirradiation_predictions_v3.csv  the 4 excluded re-irradiations, scored for information only
% Then run 02_SPSS/Paper2_SPSS_S13_validation_v3.sps in SPSS.
% Press Run in this folder (05_MODEL/matlab). It takes a few seconds.
clear; clc;
outDir = 'final_v3';
logFile = fullfile(outDir, 'MATLAB_output_validation_v3.txt'); diary off; if exist(logFile, 'file'), delete(logFile); end; diary(logFile);
fprintf('validate_locked_v3.m run on %s with MATLAB %s\n', datestr(now), version);
schemes = {'SRS', '3FR', '5FR'}; order = {'SRS', '3FR', '5FR', 'BEYOND_5FR'}; LIMIT = [10 20 20]; RANGE = [18 34 40];
scen = {'CI', 'CR', 'PI', 'PR'}; scC = [1 1 0 0]; scI = [1 0 1 0];
lg = @(X) [log(X(:, 1)) X(:, 2:end)];

% 1. the locked model
LOCKED_SHA = '213b1b04b61c4da22025f561bd39d30fab4dcaa6c3fc6e57056d02f50b7c52dd';
fid = fopen(fullfile(outDir, 'model_v3_export.json'), 'r'); bytes = fread(fid, inf, '*uint8')'; fclose(fid);
sha = sha256bytes(bytes);
assert(strcmp(sha, LOCKED_SHA), 'model_v3_export.json differs from the locked model');
S = load(fullfile(outDir, 'model_v3.mat'), 'final'); final = S.final;
fprintf('Locked model v3 loaded (export SHA-256 %s): unchanged since the lock.\n', sha);

% 2. predictions for the validation plans (same code as section 6 of final_model_v3.m)
C  = readtable('scheme_classification.csv');
Vd = readtable('validation_cases.csv');
n = height(Vd); bp = nan(n, 3); pred = nan(n, 1); recc = nan(n, 1); qp = nan(n, 4);
for i = 1:n
    x = [Vd.volume(i) Vd.central(i) Vd.irregular(i)];
    for k = 1:3, bp(i, k) = exp(predict(final.brain{k}, lg(x))); end
    k = find(strcmp(schemes, Vd.scheme{i})); pred(i) = bp(i, k);
    for q = 1:4, qp(i, q) = predict(final.qual{k, q}, lg(x)); end
    j = find(scC == Vd.central(i) & scI == Vd.irregular(i));
    t = sortrows(C(strcmp(C.scenario, scen{j}), :), 'volume'); ix = find(t.volume >= Vd.volume(i), 1);
    if isempty(ix), tc = 3; else, tc = t.label_code(ix); end
    rc = 3; for kk = 1:3, if Vd.volume(i) <= RANGE(kk) && bp(i, kk) < LIMIT(kk), rc = kk - 1; break; end, end
    recc(i) = max(tc, rc);
end

% check: the plans whose data did not change get exactly the predictions of the first validation run
oldF = fullfile(outDir, 'validation_predictions_v3_T05_27cc.csv');
if ~exist(oldF, 'file'), copyfile(fullfile(outDir, 'validation_predictions_v3.csv'), oldF); end
Old = readtable(oldF);
[tf, io] = ismember(Vd.case_id, Old.case_id); assert(all(tf), 'the case list differs from the first validation run');
same = abs(Vd.volume - Old.volume(io)) < 1e-9 & Vd.central == Old.central(io) & Vd.irregular == Old.irregular(io);
fprintf('Plans with unchanged data: %d; largest difference from the first run %.2e cm3\n', sum(same), max(abs(pred(same) - Old.brain_pred(io(same)))));
for i = find(~same)'
    fprintf('Corrected plan %s (%s, %.1f cm3): predicted %.2f cm3 (first run %.2f cm3 at %.1f cm3); recommended %s\n', Vd.case_id{i}, Vd.scheme{i}, ...
        Vd.volume(i), pred(i), Old.brain_pred(io(i)), Old.volume(io(i)), order{recc(i) + 1});
end

% 3. results (same output as section 6 of final_model_v3.m)
fprintf('\nIndependent validation, %d clinical plans (locked model v3)\n', n);
dv = Vd.brain_meas - pred; sch = cellfun(@(s) find(strcmp(schemes, s)) - 1, Vd.scheme);
fprintf('Brain dose of the delivered scheme: MAE %.2f cm3 (median %.2f), mean difference %.2f, limits of agreement %.2f to %.2f cm3\n', ...
    mean(abs(dv)), median(abs(dv)), mean(dv), mean(dv) - 1.96 * std(dv), mean(dv) + 1.96 * std(dv));
for k = 1:3, s = sch == k - 1; fprintf('   %s: n = %d, MAE %.2f cm3, mean difference %.2f\n', schemes{k}, sum(s), mean(abs(dv(s))), mean(dv(s))); end
lmv = fitlm(pred, Vd.brain_meas);
fprintf('   calibration: measured = %.2f + %.2f x predicted;  Spearman rho %.2f\n', lmv.Coefficients.Estimate(1), lmv.Coefficients.Estimate(2), corr(pred, Vd.brain_meas, 'Type', 'Spearman'));
lim = reshape(LIMIT(sch + 1), [], 1);
fprintf('   compliance: predicted within limit %d/%d, measured within limit %d/%d, agreement %d/%d\n', sum(pred < lim), n, sum(Vd.brain_meas <= lim), n, sum((pred < lim) == (Vd.brain_meas <= lim)), n);
fprintf('   recommended (brain-based) vs delivered scheme: same %d, model longer %d, model shorter %d (of %d)\n', sum(recc == sch), sum(recc > sch), sum(recc < sch), n);
meas = [Vd.CI_meas Vd.PCI_meas Vd.GI_meas Vd.Q_meas];
fprintf('   plan quality MAE: CI %.3f  Paddick %.3f  GI %.3f  Q %.3f\n', mean(abs(meas - qp)));

% 4. files
VT = [Vd table(pred, bp(:, 1), bp(:, 2), bp(:, 3), recc, qp(:, 1), qp(:, 2), qp(:, 3), qp(:, 4), 'VariableNames', ...
    {'brain_pred', 'pred_SRS', 'pred_3FR', 'pred_5FR', 'rec_code', 'CI_pred', 'PCI_pred', 'GI_pred', 'Q_pred'})];
writetable(VT, fullfile(outDir, 'validation_predictions_v3.csv'));
loc = repmat({'peripheral'}, n, 1); loc(Vd.central == 1) = {'central'};
shp = repmat({'regular'}, n, 1); shp(Vd.irregular == 1) = {'irregular'};
rel = repmat({'same'}, n, 1); rel(recc > sch) = {'model longer'}; rel(recc < sch) = {'model shorter'};
SP = table(Vd.case_id, Vd.scheme, sch, Vd.volume, loc, shp, Vd.brain_meas, pred, dv, abs(dv), lim, 100 * Vd.brain_meas ./ lim, 100 * pred ./ lim, ...
    100 * dv ./ lim, 100 * abs(dv) ./ lim, double(Vd.brain_meas <= lim), double(pred < lim), reshape(order(recc + 1), [], 1), recc, rel, ...
    Vd.CI_meas, qp(:, 1), Vd.PCI_meas, qp(:, 2), Vd.GI_meas, qp(:, 3), Vd.Q_meas, qp(:, 4), 'VariableNames', ...
    {'case_id', 'scheme', 'scheme_code', 'volume', 'location', 'shape', 'brain_meas', 'brain_pred', 'diff', 'absdiff', 'limit', 'pct_meas', 'pct_pred', ...
     'diff_pct', 'absdiff_pct', 'meas_compliant', 'pred_compliant', 'rec_scheme', 'rec_code', 'rec_vs_delivered', ...
     'CI_meas', 'CI_pred', 'PCI_meas', 'PCI_pred', 'GI_meas', 'GI_pred', 'Q_meas', 'Q_pred'});
spssDir = fullfile('..', '..', '02_SPSS', 'data_csv');
assert(exist(spssDir, 'dir') == 7, 'Run this script in the folder PAPER 2 FINAL/05_MODEL/matlab');
spssCsv = fullfile(spssDir, 'validation.csv');
writetable(SP, spssCsv);
% 5. the four excluded re-irradiations, scored for information only (not part of the validation statistics):
%    the model does not consider the dose already given, so its recommendation can be too short for them
Rr = readtable('reirradiation_cases.csv'); nr = height(Rr); rr = nan(nr, 1); rp = nan(nr, 3);
for i = 1:nr
    x = [Rr.volume(i) Rr.central(i) Rr.irregular(i)];
    for k = 1:3, rp(i, k) = exp(predict(final.brain{k}, lg(x))); end
    j = find(scC == Rr.central(i) & scI == Rr.irregular(i));
    t = sortrows(C(strcmp(C.scenario, scen{j}), :), 'volume'); ix = find(t.volume >= Rr.volume(i), 1);
    if isempty(ix), tc = 3; else, tc = t.label_code(ix); end
    rc = 3; for kk = 1:3, if Rr.volume(i) <= RANGE(kk) && rp(i, kk) < LIMIT(kk), rc = kk - 1; break; end, end
    rr(i) = max(tc, rc);
end
rs = cellfun(@(s) find(strcmp(schemes, s)) - 1, Rr.scheme);
fprintf('\nExcluded re-irradiations (scheme set by cumulative dose), scored for information only:\n');
for i = 1:nr
    fprintf('   %s: %s delivered, %.1f cm3 (%s, %s): model recommends %s (predicted V20Gy for 3 fractions %.1f cm3)\n', Rr.case_id{i}, Rr.scheme{i}, ...
        Rr.volume(i), loc0(Rr.central(i)), shp0(Rr.irregular(i)), order{rr(i) + 1}, rp(i, 2));
end
fprintf('   recommended vs delivered: same %d, model shorter %d, model longer %d (of %d)\n', sum(rr == rs), sum(rr < rs), sum(rr > rs), nr);
writetable([Rr table(rp(:, 1), rp(:, 2), rp(:, 3), rr, 'VariableNames', {'pred_SRS', 'pred_3FR', 'pred_5FR', 'rec_code'})], ...
    fullfile(outDir, 'reirradiation_predictions_v3.csv'));

fprintf('\nWritten: %s, %s and %s\n', fullfile(outDir, 'validation_predictions_v3.csv'), logFile, spssCsv);
diary off;
fprintf('Done. Now run 02_SPSS/Paper2_SPSS_S13_validation_v3.sps in SPSS.\n');

function s = loc0(c), if c == 1, s = 'central'; else, s = 'peripheral'; end, end
function s = shp0(i), if i == 1, s = 'irregular'; else, s = 'regular'; end, end
function h = sha256bytes(b)
    md = java.security.MessageDigest.getInstance('SHA-256');
    d = typecast(int8(md.digest(b)), 'uint8'); h = lower(reshape(dec2hex(d, 2)', 1, []));
end
