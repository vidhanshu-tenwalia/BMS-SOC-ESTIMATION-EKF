%% tune_ekf_params.m  (TUNING STEP 1 of 3 -- see tuning_notes.md)
%
% *** THIS SCRIPT'S RESULT WAS FOUND TO OVERFIT -- KEPT INTENTIONALLY ***
% This was the FIRST tuning pass: a grid search using ONLY the UDDS cycle.
% It found parameters giving an excellent 0.51% RMSE on UDDS -- but those
% same parameters performed WORSE than plain Coulomb Counting on the US06
% cycle (4.44% vs 0.79%). This script is kept in the repo, unmodified, as
% the documented starting point of that finding.
%
% See, in order:
%   1. tune_ekf_params.m            (this file)      -- UDDS-only, overfits
%   2. diagnose_us06_ekf.m                            -- diagnoses why
%   3. tune_ekf_final_refinement.m                    -- final, robust result
%
% ---------------------------------------------------------------------
% Grid search over EKF process/measurement noise covariances to find the
% combination that minimizes SOC RMSE on the UDDS cycle. Uses estimate_soc.m
% (fast, pure-MATLAB loop) so this runs in seconds instead of re-running
% Simulink dozens of times.
%
% Requires: estimate_soc.m, battery_params.mat, OCV_SOC_table.mat, and the
% UDDS .mat file, all in the current folder.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc;

% --- Baseline (current values used in ekf_soc_estimator.m) ---
fprintf('Baseline (current Simulink settings):\n');
[rmse_cc0, rmse_ekf0] = estimate_soc('*UDDS*.mat', [1e-10, 1e-6], 1e-4, false);
fprintf('  RMSE: CC=%.3f%%, EKF=%.3f%%\n\n', rmse_cc0, rmse_ekf0);

% --- Grid search ranges ---
% Q_SOC:  how much we trust the process model's SOC prediction (smaller = trust more)
% Q_V1:   same, for the RC branch voltage state
% Rcov:   how much we trust the voltage measurement (smaller = trust measurement more,
%         which pulls the EKF harder toward correcting via voltage feedback)
Q_SOC_range  = [1e-11, 1e-10, 1e-9, 1e-8];
Q_V1_range   = [1e-7, 1e-6, 1e-5];
Rcov_range   = [1e-5, 1e-4, 1e-3];

results = [];
fprintf('Running grid search (%d combinations)...\n', ...
    length(Q_SOC_range)*length(Q_V1_range)*length(Rcov_range));

for qs = Q_SOC_range
    for qv = Q_V1_range
        for r = Rcov_range
            [rmse_cc, rmse_ekf] = estimate_soc('*UDDS*.mat', [qs, qv], r, false);
            results = [results; qs, qv, r, rmse_ekf]; %#ok<AGROW>
        end
    end
end

% --- Sort by best (lowest) EKF RMSE ---
results = sortrows(results, 4);

fprintf('\n===== Top 5 parameter combinations (lowest RMSE) =====\n');
fprintf('%-12s %-12s %-12s %-10s\n', 'Q_SOC', 'Q_V1', 'Rcov', 'RMSE(%)');
for i = 1:5
    fprintf('%-12.2e %-12.2e %-12.2e %-10.3f\n', results(i,1), results(i,2), results(i,3), results(i,4));
end

best = results(1,:);
fprintf('\nBest combination: Qcov_diag = [%.2e, %.2e], Rcov = %.2e\n', best(1), best(2), best(3));
fprintf('Best EKF RMSE: %.3f%% (vs baseline %.3f%%)\n', best(4), rmse_ekf0);

fprintf('\n*** Update these 2 lines inside ekf_soc_estimator.m (both the .m file ***\n');
fprintf('*** AND the pasted code inside your Simulink MATLAB Function block): ***\n');
fprintf('    Qcov = diag([%.2e, %.2e]);\n', best(1), best(2));
fprintf('    Rcov = %.2e;\n', best(3));

Qcov_tuned = [best(1), best(2)];
Rcov_tuned = best(3);
save('tuned_ekf_params.mat', 'Qcov_tuned', 'Rcov_tuned');
fprintf('\nSaved tuned_ekf_params.mat (auto-loaded by validate_all_cycles.m)\n');

% --- Final comparison plot with tuned parameters ---
fprintf('\nGenerating final plot with tuned parameters...\n');
[rmse_cc_f, rmse_ekf_f] = estimate_soc('*UDDS*.mat', [best(1), best(2)], best(3), true);
saveas(gcf, 'ekf_tuning_result_UDDS.png');
fprintf('Saved: ekf_tuning_result_UDDS.png\n');