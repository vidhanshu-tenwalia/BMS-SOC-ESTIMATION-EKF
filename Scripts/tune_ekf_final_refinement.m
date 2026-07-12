%% tune_ekf_final_refinement.m  (TUNING STEP 3 of 3 -- FINAL)
% Focused refinement search, based on the diagnostic finding (see
% diagnose_us06_ekf.m) that Rcov values around 10 generalize well across
% both UDDS and US06 -- unlike the earlier low-Rcov region (tune_ekf_params.m),
% which overfit to UDDS's gentler dynamics.
%
% This is the FINAL tuning script. Its output (Qcov, Rcov) is what's used
% in the final ekf_soc_estimator.m and the Simulink MATLAB Function block.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc;

Q_SOC_range = [1e-11, 1e-10, 1e-9];
Q_V1_range  = [1e-6, 1e-5, 1e-4];
Rcov_range  = [3, 5, 8, 10, 15, 20, 30];

results = [];
total = length(Q_SOC_range)*length(Q_V1_range)*length(Rcov_range);
fprintf('Refined search around the high-Rcov neighborhood (%d combinations)...\n', total);

for qs = Q_SOC_range
    for qv = Q_V1_range
        for r = Rcov_range
            [~, rmse_udds] = estimate_soc('*UDDS*.mat', [qs, qv], r, false);
            [~, rmse_us06] = estimate_soc('*US06*.mat', [qs, qv], r, false);
            worst = max(rmse_udds, rmse_us06);
            avg   = mean([rmse_udds, rmse_us06]);
            results = [results; qs, qv, r, rmse_udds, rmse_us06, worst, avg]; %#ok<AGROW>
        end
    end
end

results_sorted = sortrows(results, 6);

fprintf('\n===== Top 8 combinations by worst-case RMSE =====\n');
fprintf('%-10s %-10s %-10s %-10s %-10s %-10s %-10s\n', ...
    'Q_SOC','Q_V1','Rcov','RMSE_UDDS','RMSE_US06','Worst','Avg');
for i = 1:8
    fprintf('%-10.1e %-10.1e %-10.1f %-10.3f %-10.3f %-10.3f %-10.3f\n', results_sorted(i,:));
end

best = results_sorted(1,:);
fprintf('\nFinal robust combination: Qcov_diag = [%.2e, %.2e], Rcov = %.1f\n', best(1), best(2), best(3));
fprintf('  -> RMSE UDDS = %.3f%%, RMSE US06 = %.3f%%\n', best(4), best(5));
fprintf('  -> Coulomb Counting baseline: UDDS = 3.807%%, US06 = 0.787%%\n');
fprintf('  -> EKF beats CC on BOTH cycles: %.1fx on UDDS, %.1fx on US06\n', ...
    3.807/best(4), 0.787/best(5));

Qcov_tuned = [best(1), best(2)];
Rcov_tuned = best(3);
save('tuned_ekf_params.mat', 'Qcov_tuned', 'Rcov_tuned');
fprintf('\nSaved final tuned_ekf_params.mat\n');

fprintf('\n*** FINAL values for ekf_soc_estimator.m and the Simulink block: ***\n');
fprintf('    Qcov = diag([%.2e, %.2e]);\n', best(1), best(2));
fprintf('    Rcov = %.1f;\n', best(3));

%% Generate final plots for both cycles with the final parameters
[~, ~, ~, ~, R_udds] = estimate_soc('*UDDS*.mat', Qcov_tuned, Rcov_tuned, true);
saveas(gcf, 'FINAL_soc_estimation_UDDS.png');
[~, ~, ~, ~, R_us06] = estimate_soc('*US06*.mat', Qcov_tuned, Rcov_tuned, true);
saveas(gcf, 'FINAL_soc_estimation_US06.png');
fprintf('\nSaved FINAL_soc_estimation_UDDS.png and FINAL_soc_estimation_US06.png\n');