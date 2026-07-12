%% diagnose_us06_ekf.m  (TUNING STEP 2 of 3 -- see tune_ekf_params.m header)
% Diagnostic: sweeps Rcov across a MUCH wider range (essentially testing
% "what if the EKF trusts the voltage measurement less and less") to see
% whether US06's poor EKF performance is a tuning issue or a structural
% model-mismatch issue (1RC model + charge/discharge asymmetry not
% captured by HPPC-derived R1/C1).
%
% If US06 RMSE keeps improving as Rcov grows toward Coulomb-Counting-like
% behavior, it's a tuning/weighting issue. If it never comes close to CC's
% RMSE even at very high Rcov, the model itself doesn't fit US06 well.
%
% Result: RMSE steadily improved as Rcov grew, confirming this was a
% tuning/weighting issue (not an unfixable model mismatch) -- see
% tune_ekf_final_refinement.m for the resulting robust parameter search.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc;

Qcov_fixed = [1e-10, 1e-5];  % hold process noise fixed at a reasonable value
Rcov_sweep = [1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1, 10];

fprintf('Coulomb Counting baseline on US06 (for reference):\n');
[rmse_cc_us06] = estimate_soc('*US06*.mat', Qcov_fixed, 1e-4, false);
fprintf('  RMSE CC (US06) = %.3f%%\n\n', rmse_cc_us06);

fprintf('%-12s %-12s\n', 'Rcov', 'RMSE_EKF_US06(%)');
for r = Rcov_sweep
    [~, rmse_ekf] = estimate_soc('*US06*.mat', Qcov_fixed, r, false);
    fprintf('%-12.1e %-12.3f\n', r, rmse_ekf);
end

fprintf('\nFor comparison, same sweep on UDDS:\n');
fprintf('%-12s %-12s\n', 'Rcov', 'RMSE_EKF_UDDS(%)');
for r = Rcov_sweep
    [~, rmse_ekf] = estimate_soc('*UDDS*.mat', Qcov_fixed, r, false);
    fprintf('%-12.1e %-12.3f\n', r, rmse_ekf);
end