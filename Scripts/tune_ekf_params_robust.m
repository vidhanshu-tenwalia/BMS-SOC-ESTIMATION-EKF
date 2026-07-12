%% tune_ekf_params_robust.m
% Grid search for EKF noise covariances, but tuned ACROSS BOTH drive cycles
% (UDDS and US06) jointly, instead of just one. This avoids overfitting to
% a single driving pattern -- see project notes: tuning on UDDS alone
% produced parameters that performed WORSE than Coulomb Counting on US06.
%
% Selection criterion: minimize the WORST-CASE (max) RMSE across the two
% cycles, not just the average -- this favors parameters that are reliably
% decent on both, rather than excellent on one and poor on the other.
%
% Requires: estimate_soc.m, battery_params.mat, OCV_SOC_table.mat, and both
% the UDDS and US06 .mat files in the current folder.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc;

Q_SOC_range  = [1e-11, 1e-10, 1e-9, 1e-8];
Q_V1_range   = [1e-7, 1e-6, 1e-5];
Rcov_range   = [1e-5, 1e-4, 1e-3];

results = [];
total = length(Q_SOC_range)*length(Q_V1_range)*length(Rcov_range);
fprintf('Running robust grid search across UDDS + US06 (%d combinations)...\n', total);

count = 0;
for qs = Q_SOC_range
    for qv = Q_V1_range
        for r = Rcov_range
            count = count + 1;
            [~, rmse_udds] = estimate_soc('*UDDS*.mat', [qs, qv], r, false);
            [~, rmse_us06] = estimate_soc('*US06*.mat', [qs, qv], r, false);
            worst = max(rmse_udds, rmse_us06);
            avg   = mean([rmse_udds, rmse_us06]);
            results = [results; qs, qv, r, rmse_udds, rmse_us06, worst, avg]; %#ok<AGROW>
        end
    end
end
fprintf('Done.\n\n');

% --- Sort by worst-case RMSE (robust selection) ---
results_sorted = sortrows(results, 6);

fprintf('===== Top 5 combinations by WORST-CASE RMSE (most robust) =====\n');
fprintf('%-10s %-10s %-10s %-10s %-10s %-10s %-10s\n', ...
    'Q_SOC','Q_V1','Rcov','RMSE_UDDS','RMSE_US06','Worst','Avg');
for i = 1:5
    fprintf('%-10.1e %-10.1e %-10.1e %-10.3f %-10.3f %-10.3f %-10.3f\n', results_sorted(i,:));
end

best = results_sorted(1,:);
fprintf('\nMost robust combination: Qcov_diag = [%.2e, %.2e], Rcov = %.2e\n', best(1), best(2), best(3));
fprintf('  -> RMSE UDDS = %.3f%%, RMSE US06 = %.3f%% (worst-case = %.3f%%)\n', best(4), best(5), best(6));

% --- Compare against the earlier single-cycle-tuned (overfit) result, if it exists ---
if isfile('tuned_ekf_params.mat')
    old = load('tuned_ekf_params.mat', 'Qcov_tuned', 'Rcov_tuned');
    [~, rmse_udds_old] = estimate_soc('*UDDS*.mat', old.Qcov_tuned, old.Rcov_tuned, false);
    [~, rmse_us06_old] = estimate_soc('*US06*.mat', old.Qcov_tuned, old.Rcov_tuned, false);
    fprintf('\nFor comparison, the UDDS-only-tuned params gave:\n');
    fprintf('  -> RMSE UDDS = %.3f%%, RMSE US06 = %.3f%% (worst-case = %.3f%%)\n', ...
        rmse_udds_old, rmse_us06_old, max(rmse_udds_old, rmse_us06_old));
end

Qcov_tuned = [best(1), best(2)];
Rcov_tuned = best(3);
save('tuned_ekf_params.mat', 'Qcov_tuned', 'Rcov_tuned');
fprintf('\nOverwrote tuned_ekf_params.mat with the robust (cross-cycle) values.\n');

fprintf('\n*** Final values to put in ekf_soc_estimator.m and the Simulink block: ***\n');
fprintf('    Qcov = diag([%.2e, %.2e]);\n', best(1), best(2));
fprintf('    Rcov = %.2e;\n', best(3));
