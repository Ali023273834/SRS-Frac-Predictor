 %% PAPER 2 - FINAL MODEL v3 (MATLAB):
% Algorithms were chosen by compare_models.m on development data only (the 27 validation plans were not used):
%   brain dose per scheme ...... Gaussian process regression (ARD squared-exponential kernel, standardized predictors;
%                                inputs log(volume), central, irregular; response log(brain dose))
%   expected plan quality ....... the same GPR settings for CI_RTOG, Paddick CI, GI and Q_RTOG (response not logged)
%   OAR dose (% of TG-101 limit)  random forest (500 bagged trees, minimum leaf 2, all predictors at each split)
%   scheme ...................... decision rule = longest of (MTV table, first scheme predicted below its limit, OAR rule)
% Press Run in this folder. Takes about 10-20 minutes. Everything is written to the sub-folder final_v3:
%   MATLAB_output_final_model_v3.txt (all results), model_v3.mat, model_v3_export.json (for the app; its SHA-256 is printed),
%   dev_brain_predictions.csv, dev_rule.csv, dev_quality.csv, dev_oar_predictions.csv, validation_predictions_v3.csv,
%   test_vectors_brain.csv, test_vectors_oar.csv.   Send the folder (or just tell me "done").
clear; clc; rng(20261102);
outDir = 'final_v3'; if ~exist(outDir, 'dir'), mkdir(outDir); end
logFile = fullfile(outDir, 'MATLAB_output_final_model_v3.txt'); diary off; if exist(logFile, 'file'), delete(logFile); end; diary(logFile);
fprintf('final_model_v3.m run on %s with MATLAB %s\n', datestr(now), version);
schemes = {'SRS', '3FR', '5FR'}; LIMIT = [10 20 20]; RANGE = [18 34 40];
scen = {'CI', 'CR', 'PI', 'PR'}; scC = [1 1 0 0]; scI = [1 0 1 0];
qn = {'CI', 'PCI', 'GI', 'Q'};
lg = @(X) [log(X(:, 1)) X(:, 2:end)];
gprFit = @(X, y) fitrgp(lg(X), y, 'KernelFunction', 'ardsquaredexponential', 'Standardize', true);
rfFit = @(X, y) fitrensemble(X, y, 'Method', 'Bag', 'NumLearningCycles', 500, 'Learners', templateTree('MinLeafSize', 2, 'NumVariablesToSample', 'all'));

B  = readtable('brain_regression.csv');
QD = readtable('atlas_quality.csv');
C  = readtable('scheme_classification.csv');
O  = readtable('oar_regression.csv', 'VariableNamingRule', 'preserve');
Vd = readtable('validation_cases.csv');
labVols = unique(C.volume);

%% 1. DEVELOPMENT: brain dose (GPR), whole volumes held out, and the decision rule
fprintf('\n1. Brain dose, GPR, whole volumes held out\n');
predAt = cell(1, 3); dev = table();
for k = 1:3
    d = B(strcmp(B.scheme, schemes{k}), :); X = [d.volume d.central d.irregular]; y = d.brain;
    full = gprFit(X, log(y)); P = nan(numel(labVols), 4); pPlan = nan(size(y));
    for iv = 1:numel(labVols)
        v = labVols(iv); te = abs(d.volume - v) < 1e-9;
        if any(te), m = gprFit(X(~te, :), log(y(~te))); else, m = full; end
        P(iv, :) = exp(predict(m, lg([repmat(v, 4, 1) scC' scI'])))';
        if any(te), pPlan(te) = exp(predict(m, lg(X(te, :)))); end
    end
    predAt{k} = P;
    ok = y <= LIMIT(k); pok = pPlan < LIMIT(k);
    fprintf('%s: n=%d  R2=%.3f  RMSE=%.2f  MAE=%.2f cm3  compliance agreement %d/%d  predicted within limit but violated %d\n', schemes{k}, numel(y), ...
        1 - sum((pPlan - y).^2) / sum((y - mean(y)).^2), sqrt(mean((pPlan - y).^2)), mean(abs(pPlan - y)), sum(ok == pok), numel(y), sum(pok & ~ok));
    dev = [dev; table(repmat(schemes(k), numel(y), 1), d.config_id, d.volume, d.central, d.irregular, y, pPlan, ...
        'VariableNames', {'scheme', 'config_id', 'volume', 'central', 'irregular', 'brain_meas', 'brain_pred'})]; %#ok<AGROW>
end
e = dev.brain_pred - dev.brain_meas;
fprintf('All: R2=%.3f  MAE=%.2f cm3\n', 1 - sum(e.^2) / sum((dev.brain_meas - mean(dev.brain_meas)).^2), mean(abs(e)));
writetable(dev, fullfile(outDir, 'dev_brain_predictions.csv'));

rule = nan(height(C), 1); tcode = rule; rcode = rule;
for r = 1:height(C)
    v = C.volume(r); j = find(strcmp(scen, C.scenario{r})); iv = find(abs(labVols - v) < 1e-9);
    tr = C(abs(C.volume - v) > 1e-9 & strcmp(C.scenario, C.scenario{r}), :); tr = sortrows(tr, 'volume');
    ix = find(tr.volume >= v, 1); if isempty(ix), tcode(r) = 3; else, tcode(r) = tr.label_code(ix); end
    rcode(r) = 3;
    for k = 1:3, if v <= RANGE(k) && predAt{k}(iv, j) < LIMIT(k), rcode(r) = k - 1; break; end, end
    rule(r) = max(tcode(r), rcode(r));
end
y = C.label_code;
fprintf('\nDecision rule (MTV table + GPR brain dose), whole volumes held out: %d/%d correct (%.1f%%), weighted kappa %.2f, too few %d, too many %d\n', ...
    sum(rule == y), numel(y), 100 * mean(rule == y), wkappa(y, rule, 4), sum(rule < y), sum(rule > y));
fprintf('   GPR regression alone: %d/%d correct, too few %d;  MTV table alone: %d/%d correct, too few %d\n', sum(rcode == y), numel(y), sum(rcode < y), sum(tcode == y), numel(y), sum(tcode < y));
writetable([C table(tcode, rcode, rule)], fullfile(outDir, 'dev_rule.csv'));

%% 2. DEVELOPMENT: expected plan quality (GPR), whole volumes held out
fprintf('\n2. Plan quality, GPR, whole volumes held out (R2 / MAE)\n');
devq = table();
for k = 1:3
    d = QD(strcmp(QD.scheme, schemes{k}), :); X = [d.volume d.central d.irregular];
    for q = 1:4
        y = d.(qn{q}); p = nan(size(y));
        for v = unique(d.volume)'
            te = abs(d.volume - v) < 1e-9; m = gprFit(X(~te, :), y(~te)); p(te) = predict(m, lg(X(te, :)));
        end
        fprintf('%s %-3s R2=%.2f  MAE=%.3f\n', schemes{k}, qn{q}, 1 - sum((p - y).^2) / sum((y - mean(y)).^2), mean(abs(p - y)));
        devq = [devq; table(repmat(schemes(k), numel(y), 1), repmat(qn(q), numel(y), 1), d.volume, d.central, d.irregular, y, p, ...
            'VariableNames', {'scheme', 'metric', 'volume', 'central', 'irregular', 'measured', 'predicted'})]; %#ok<AGROW>
    end
end
writetable(devq, fullfile(outDir, 'dev_quality.csv'));

%% 3. DEVELOPMENT: OAR dose (random forest), whole patients held out
XO = [O.oar_dist O.chiasm O.contact_code O.volume O.srs24 O.fr3]; yO = O.oar_pct_limit; pO = nan(size(yO));
for g = unique(O.group)'
    te = O.group == g; m = rfFit(XO(~te, :), yO(~te)); pO(te) = predict(m, XO(te, :));
end
fprintf('\n3. OAR dose, random forest, whole patients held out: R2=%.2f  RMSE=%.1f%%  MAE=%.1f%%  met/exceeded correct %d/%d  predicted met but exceeded %d\n', ...
    1 - sum((pO - yO).^2) / sum((yO - mean(yO)).^2), sqrt(mean((pO - yO).^2)), mean(abs(pO - yO)), sum((pO <= 100) == (yO <= 100)), numel(yO), sum(pO <= 100 & yO > 100));
writetable(table(O.group, XO(:, 1), XO(:, 2), XO(:, 3), XO(:, 4), XO(:, 5), XO(:, 6), yO, pO, 'VariableNames', ...
    {'group', 'oar_dist', 'chiasm', 'contact_code', 'volume', 'srs24', 'fr3', 'oar_pct_measured', 'oar_pct_predicted'}), fullfile(outDir, 'dev_oar_predictions.csv'));

%% 4. FINAL MODELS on all development data, EXPORT and LOCK (before any validation case is scored)
fprintf('\n4. Final models\n');
ex = struct(); ex.meta = struct('model', 'SRS/SRT fractionation model v3 (MATLAB)', 'trained', datestr(now, 'yyyy-mm-ddTHH:MM:SS'), 'matlab', version, ...
    'data', 'MASTER_FINAL_v13 (367 atlas plans; OAR cohort 12 patients, 48 distance points)', ...
    'brain', 'fitrgp ardsquaredexponential, Standardize, inputs [log(volume) central irregular], response log(brain)', ...
    'quality', 'fitrgp ardsquaredexponential, Standardize, inputs [log(volume) central irregular], response raw', ...
    'oar', 'fitrensemble Bag 500, MinLeafSize 2, NumVariablesToSample all; inputs [oar_dist chiasm contact_code volume srs24 fr3]');
final = struct('brain', {cell(1, 3)}, 'qual', {cell(3, 4)});
ex.brain = struct(); ex.quality = struct(); key = {'SRS', 'F3', 'F5'};   % JSON keys (3FR -> F3, 5FR -> F5)
for k = 1:3
    d = B(strcmp(B.scheme, schemes{k}), :); X = [d.volume d.central d.irregular];
    final.brain{k} = gprFit(X, log(d.brain)); ex.brain.(key{k}) = gprExport(final.brain{k}, lg(X), schemes{k}, 'log');
    d = QD(strcmp(QD.scheme, schemes{k}), :); X = [d.volume d.central d.irregular];
    for q = 1:4, final.qual{k, q} = gprFit(X, d.(qn{q})); ex.quality.([key{k} '_' qn{q}]) = gprExport(final.qual{k, q}, lg(X), [schemes{k} '_' qn{q}], 'raw'); end
end
rfO = rfFit(XO, yO);
cuts = cell(1, 6);
for t = 1:numel(rfO.Trained)
    tr = rfO.Trained{t}; idx = tr.CutPredictorIndex; cp = tr.CutPoint;
    for p = 1:6, cuts{p} = [cuts{p}; cp(idx == p)]; end
end
for p = 1:6, cuts{p} = unique(cuts{p})'; end
rep = @(c) [c(1) - 1, (c(1:end-1) + c(2:end)) / 2, c(end) + 1];
rd = rep(cuts{1}); rv = rep(cuts{4});
REG = {'SRS24', 1, 0; 'SRS18', 0, 0; '3FR', 0, 1};
ex.oar = struct('dist_cuts', cuts{1}, 'vol_cuts', cuts{4}, 'rule', 'x >= cut goes to the next interval (MATLAB trees send x < cut left)');
tabs = struct();
for ch = 0:1
    for cc = 1:3
        for r = 1:3
            [DD, VV] = ndgrid(rd, rv);
            Xg = [DD(:), repmat(ch, numel(DD), 1), repmat(cc, numel(DD), 1), VV(:), repmat(REG{r, 2}, numel(DD), 1), repmat(REG{r, 3}, numel(DD), 1)];
            tabs.(sprintf('ch%d_cc%d_%s', ch, cc, strrep(REG{r, 1}, '3FR', 'F3'))) = reshape(predict(rfO, Xg), numel(rd), numel(rv));
        end
    end
end
ex.oar.tables = tabs;
% self-check: the exported OAR tables reproduce predict() at random points, including exact cut values
nt = 2000; dT = [rand(nt/2, 1) * 12; cuts{1}(randi(numel(cuts{1}), nt/2, 1))']; vT = exp(log(0.1) + rand(nt, 1) * (log(45) - log(0.1)));
vT(1:200) = cuts{4}(randi(numel(cuts{4}), 200, 1))';
chT = randi([0 1], nt, 1); ccT = randi([1 3], nt, 1); rT = randi([1 3], nt, 1);
XT = [dT chT ccT vT cell2mat(REG(rT, 2)) cell2mat(REG(rT, 3))]; pT = predict(rfO, XT); pTab = nan(nt, 1);
for i = 1:nt
    T = tabs.(sprintf('ch%d_cc%d_%s', chT(i), ccT(i), strrep(REG{rT(i), 1}, '3FR', 'F3')));
    pTab(i) = T(sum(dT(i) >= cuts{1}) + 1, sum(vT(i) >= cuts{4}) + 1);
end
fprintf('OAR forest exported as interval tables: max |table - predict| = %.2e over %d test points\n', max(abs(pTab - pT)), nt);
assert(max(abs(pTab - pT)) < 1e-9, 'OAR table export does not reproduce predict()');
% labels of the MTV table (data) for the rule
for j = 1:4
    t = sortrows(C(strcmp(C.scenario, scen{j}), :), 'volume'); ex.labels.(scen{j}) = struct('vol', t.volume', 'code', t.label_code');
end
txt = jsonencode(ex);
fid = fopen(fullfile(outDir, 'model_v3_export.json'), 'w'); fwrite(fid, txt, 'char'); fclose(fid);
sha = sha256hex(txt);
save(fullfile(outDir, 'model_v3.mat'), 'final', 'rfO', 'ex');
fprintf('LOCKED model v3: model_v3_export.json SHA-256 %s  (%s)\n', sha, datestr(now, 'yyyy-mm-dd HH:MM:SS'));

%% 5. TEST VECTORS for the app (MATLAB predictions)
nb = 1500; vb = exp(log(0.05) + rand(nb, 1) * (log(50) - log(0.05))); vb = [vb; unique(B.volume)];
cb = randi([0 1], numel(vb), 1); ib = randi([0 1], numel(vb), 1); TV = table(vb, cb, ib, 'VariableNames', {'volume', 'central', 'irregular'});
for k = 1:3
    TV.(['brain_' schemes{k}]) = exp(predict(final.brain{k}, lg([vb cb ib])));
    for q = 1:4, TV.([qn{q} '_' schemes{k}]) = predict(final.qual{k, q}, lg([vb cb ib])); end
end
writetable(TV, fullfile(outDir, 'test_vectors_brain.csv'));
writetable(table(dT, chT, ccT, vT, cell2mat(REG(rT, 2)), cell2mat(REG(rT, 3)), pT, 'VariableNames', {'oar_dist', 'chiasm', 'contact_code', 'volume', 'srs24', 'fr3', 'oar_pct'}), ...
    fullfile(outDir, 'test_vectors_oar.csv'));
fprintf('Test vectors written (%d brain/quality, %d OAR)\n', height(TV), nt);

%% 6. INDEPENDENT VALIDATION of the locked model v3 on the 27 clinical plans (scored once)
fprintf('\n6. Independent validation, 27 clinical plans\n');
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
dv = Vd.brain_meas - pred; sch = cellfun(@(s) find(strcmp(schemes, s)) - 1, Vd.scheme);
fprintf('Brain dose of the delivered scheme: MAE %.2f cm3 (median %.2f), mean difference %.2f, limits of agreement %.2f to %.2f cm3\n', ...
    mean(abs(dv)), median(abs(dv)), mean(dv), mean(dv) - 1.96 * std(dv), mean(dv) + 1.96 * std(dv));
for k = 1:3, s = sch == k - 1; fprintf('   %s: n = %d, MAE %.2f cm3, mean difference %.2f\n', schemes{k}, sum(s), mean(abs(dv(s))), mean(dv(s))); end
lmv = fitlm(pred, Vd.brain_meas);
fprintf('   calibration: measured = %.2f + %.2f x predicted;  Spearman rho %.2f\n', lmv.Coefficients.Estimate(1), lmv.Coefficients.Estimate(2), corr(pred, Vd.brain_meas, 'Type', 'Spearman'));
lim = LIMIT(sch + 1)';
fprintf('   compliance: predicted within limit %d/%d, measured within limit %d/%d, agreement %d/%d\n', sum(pred < lim), n, sum(Vd.brain_meas <= lim), n, sum((pred < lim) == (Vd.brain_meas <= lim)), n);
fprintf('   recommended (brain-based) vs delivered scheme: same %d, model longer %d, model shorter %d (of %d)\n', sum(recc == sch), sum(recc > sch), sum(recc < sch), n);
meas = [Vd.CI_meas Vd.PCI_meas Vd.GI_meas Vd.Q_meas];
fprintf('   plan quality MAE: CI %.3f  Paddick %.3f  GI %.3f  Q %.3f\n', mean(abs(meas - qp)));
VT = [Vd table(pred, bp(:, 1), bp(:, 2), bp(:, 3), recc, qp(:, 1), qp(:, 2), qp(:, 3), qp(:, 4), 'VariableNames', ...
    {'brain_pred', 'pred_SRS', 'pred_3FR', 'pred_5FR', 'rec_code', 'CI_pred', 'PCI_pred', 'GI_pred', 'Q_pred'})];
writetable(VT, fullfile(outDir, 'validation_predictions_v3.csv'));
diary off;
fprintf('\nDone. All results are in the folder %s (log: %s).\n', outDir, logFile);

%% ------------------------------------------------------------------ local functions
function s = gprExport(m, Xlg, name, target)
    % Exports a fitrgp model so that  pred = Beta + sf^2 * exp(-0.5 * sum(((z - A) ./ ell).^2, 2))' * alpha,
    % with z = (x - mu) ./ sd  (x = [log(volume) central irregular]); target 'log' means brain = exp(pred).
    kp = m.KernelInformation.KernelParameters(:)';
    s = struct('name', name, 'target', target, 'mu', m.PredictorLocation(:)', 'sd', m.PredictorScale(:)', 'ell', kp(1:end-1), 'sf', kp(end), ...
               'beta', m.Beta, 'alpha', m.Alpha(:)', 'A', []);
    Zt = (Xlg - s.mu) ./ s.sd; Aset = m.ActiveSetVectors;
    cand = {Aset, (Aset - s.mu) ./ s.sd, Zt};                   % the stored active set may be raw or standardized
    xr = Xlg(round(linspace(1, size(Xlg, 1), min(40, size(Xlg, 1)))), :) + [0.05 0 0];
    ref = predict(m, xr); best = inf;
    for c = 1:numel(cand)
        A = cand{c}; if size(A, 1) ~= numel(s.alpha), continue; end
        z = (xr - s.mu) ./ s.sd; D = zeros(size(z, 1), size(A, 1));
        for dd = 1:numel(s.ell), D = D + ((z(:, dd) - A(:, dd)') / s.ell(dd)).^2; end
        pm = s.beta + s.sf^2 * exp(-0.5 * D) * s.alpha(:); err = max(abs(pm - ref));
        if err < best, best = err; s.A = A; end
    end
    fprintf('   %-10s GPR exported: n = %d, max |manual - predict| = %.2e\n', name, numel(s.alpha), best);
    assert(best < 1e-6, 'GPR export does not reproduce predict()');
end

function kw = wkappa(a, b, K)
    Om = accumarray([a(:) b(:)] + 1, 1, [K K]); n = sum(Om(:)); W = 1 - abs((0:K-1)' - (0:K-1)) / (K - 1);
    E = sum(Om, 2) * sum(Om, 1) / n; po = sum(W(:) .* Om(:)) / n; pe = sum(W(:) .* E(:)) / n; kw = (po - pe) / (1 - pe);
end

function h = sha256hex(txt)
    md = java.security.MessageDigest.getInstance('SHA-256');
    b = typecast(int8(md.digest(uint8(txt))), 'uint8'); h = lower(reshape(dec2hex(b, 2)', 1, []));
end
