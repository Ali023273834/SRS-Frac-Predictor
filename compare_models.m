%% PAPER 2 - Which algorithm predicts each output best? (MATLAB version of 04_SCRIPTS/compare_algorithms.py)
% Development data only (the 27 validation plans are not used). Same grouped validation as the locked model:
%   brain dose per scheme and scheme classification: whole volumes held out; OAR dose: whole patients held out.
% This is the grouped equivalent of "Train All" in the Regression / Classification Learner apps (the apps cannot
% hold out whole volumes, so their random k-fold results are optimistic for near-duplicate scenarios).
% Press Run. The output is saved to MATLAB_output_compare_models.txt in this folder. Needs R2021a or later (fitrnet/fitcnet).
clear; clc; rng(20261102);
diary off; outFile = 'MATLAB_output_compare_models.txt'; if exist(outFile, 'file'), delete(outFile); end; diary(outFile);
fprintf('compare_models.m run on %s with MATLAB %s\n', datestr(now), version);
LIMIT = [10 20 20]; RANGE = [18 34 40]; schemes = {'SRS', '3FR', '5FR'};
lg = @(X) [log(X(:,1)) X(:,2:end)];                                   % log(volume) for the smooth learners
REG = {
  'Random forest (locked)',   @(X,y) fitrensemble(X, y, 'Method','Bag', 'NumLearningCycles',300, 'Learners',templateTree('MinLeafSize',2,'NumVariablesToSample','all')), 0
  'Boosted trees (LSBoost)',  @(X,y) fitrensemble(X, y, 'Method','LSBoost', 'NumLearningCycles',300, 'LearnRate',0.05, 'Learners',templateTree('MaxNumSplits',7)), 0
  'Single tree (medium)',     @(X,y) fitrtree(X, y, 'MinLeafSize',4), 0
  'Linear',                   @(X,y) fitlm(X, y), 0
  'Log-linear (power law)',   @(X,y) fitlm(lg(X), log(y)), 1
  'Gaussian process (GPR)',   @(X,y) fitrgp(lg(X), log(y), 'KernelFunction','ardsquaredexponential', 'Standardize',true), 1
  'SVM (Gaussian)',           @(X,y) fitrsvm(lg(X), log(y), 'KernelFunction','gaussian', 'KernelScale','auto', 'Standardize',true, 'BoxConstraint',10, 'Epsilon',0.02), 1
  'Neural network (narrow)',  @(X,y) fitrnet(lg(X), log(y), 'LayerSizes',10, 'Activations','tanh', 'Standardize',true, 'Lambda',1e-3), 1 };

%% A. Brain dose by scheme (whole volumes held out)
B = readtable('brain_regression.csv');
fprintf('\nA. Brain dose, whole volumes held out\n%-26s %8s %8s %8s %8s %8s %8s %8s\n', 'algorithm', 'SRS R2', 'SRS RMSE', '3FR R2', '3FR RMSE', '5FR R2', '5FR RMSE', 'all MAE');
for a = 1:size(REG, 1)
    res = zeros(1, 7); allp = []; ally = [];
    for k = 1:3
        d = B(strcmp(B.scheme, schemes{k}), :); X = [d.volume d.central d.irregular]; y = d.brain; p = nan(size(y));
        for v = unique(d.volume)'
            te = d.volume == v; m = REG{a, 2}(X(~te,:), y(~te));
            if REG{a, 3}, p(te) = exp(predict(m, lg(X(te,:)))); else, p(te) = predict(m, X(te,:)); end
        end
        res(2*k-1) = 1 - sum((p-y).^2)/sum((y-mean(y)).^2); res(2*k) = sqrt(mean((p-y).^2)); allp = [allp; p]; ally = [ally; y]; %#ok<AGROW>
    end
    res(7) = mean(abs(allp - ally));
    fprintf('%-26s %8.3f %8.2f %8.3f %8.2f %8.3f %8.2f %8.2f\n', REG{a, 1}, res);
end

%% B. Scheme classification (shortest compliant scheme), whole volumes held out
C = readtable('scheme_classification.csv'); X = [log(C.volume) C.central C.irregular]; y = C.label_code;
CLS = {
  'Random forest',            @(X,y) fitcensemble(X, y, 'Method','Bag', 'NumLearningCycles',300, 'Learners',templateTree('MinLeafSize',2,'NumVariablesToSample','all'))
  'Boosted trees (AdaBoost)', @(X,y) fitcensemble(X, y, 'Method','AdaBoostM2', 'NumLearningCycles',200, 'LearnRate',0.1)
  'Single tree (medium)',     @(X,y) fitctree(X, y, 'MinLeafSize',4)
  'KNN (k = 5)',              @(X,y) fitcknn(X, y, 'NumNeighbors',5, 'Standardize',true)
  'SVM (Gaussian)',           @(X,y) fitcecoc(X, y, 'Learners',templateSVM('KernelFunction','gaussian','KernelScale','auto','Standardize',true,'BoxConstraint',10))
  'Naive Bayes',              @(X,y) fitcnb(X, y, 'DistributionNames', {'normal', 'mvmn', 'mvmn'})
  'Linear discriminant',      @(X,y) fitcdiscr(X, y, 'DiscrimType','pseudolinear')
  'Neural network (narrow)',  @(X,y) fitcnet(X, y, 'LayerSizes',10, 'Activations','tanh', 'Standardize',true, 'Lambda',1e-3) };
fprintf('\nB. Scheme classification, whole volumes held out (decision rule of the locked model: 306/320, too few 0)\n%-26s %10s %8s %9s\n', 'algorithm', 'correct', 'too few', 'too many');
for a = 1:size(CLS, 1)
    p = nan(size(y));
    for g = unique(C.group)'
        te = C.group == g; ytr = y(~te);
        if numel(unique(ytr)) < 2, p(te) = ytr(1); continue; end
        m = CLS{a, 2}(X(~te,:), ytr); p(te) = predict(m, X(te,:));
    end
    fprintf('%-26s %6d/%3d %8d %9d\n', CLS{a, 1}, sum(p==y), numel(y), sum(p<y), sum(p>y));
end

%% C. OAR dose (% of TG-101 limit), whole patients held out
O = readtable('oar_regression.csv', 'VariableNamingRule', 'preserve');
X = [O.oar_dist O.chiasm O.contact_code O.volume O.srs24 O.fr3]; y = O.oar_pct_limit;
OREG = {
  'Random forest (locked)',   @(X,y) fitrensemble(X, y, 'Method','Bag', 'NumLearningCycles',500, 'Learners',templateTree('MinLeafSize',2,'NumVariablesToSample','all'))
  'Boosted trees (LSBoost)',  @(X,y) fitrensemble(X, y, 'Method','LSBoost', 'NumLearningCycles',200, 'LearnRate',0.05, 'Learners',templateTree('MaxNumSplits',3))
  'Single tree (medium)',     @(X,y) fitrtree(X, y, 'MinLeafSize',4)
  'Linear',                   @(X,y) fitlm(X, y)
  'Gaussian process (GPR)',   @(X,y) fitrgp(X, y, 'KernelFunction','ardsquaredexponential', 'Standardize',true)
  'SVM (Gaussian)',           @(X,y) fitrsvm(X, y, 'KernelFunction','gaussian', 'KernelScale','auto', 'Standardize',true, 'BoxConstraint',100, 'Epsilon',1)
  'Neural network (narrow)',  @(X,y) fitrnet(X, y, 'LayerSizes',10, 'Activations','tanh', 'Standardize',true, 'Lambda',1e-2) };
fprintf('\nC. OAR dose, whole patients held out (n = %d points)\n%-26s %6s %8s %12s %14s\n', numel(y), 'algorithm', 'R2', 'RMSE %', 'met correct', 'met/exceeded');
for a = 1:size(OREG, 1)
    p = nan(size(y));
    for g = unique(O.group)'
        te = O.group == g; m = OREG{a, 2}(X(~te,:), y(~te)); p(te) = predict(m, X(te,:));
    end
    fprintf('%-26s %6.2f %8.1f %8d/%2d %14d\n', OREG{a, 1}, 1 - sum((p-y).^2)/sum((y-mean(y)).^2), sqrt(mean((p-y).^2)), sum((p<=100)==(y<=100)), numel(y), sum(p<=100 & y>100));
end
diary off;
fprintf('\nDone. The output above was saved to %s in this folder.\n', outFile);
