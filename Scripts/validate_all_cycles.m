%% validate_all_cycles.m
% Validates the (tuned) EKF SOC estimator across BOTH drive cycles (UDDS
% and US06), using the standalone estimate_soc.m pipeline. This is the
% cross-cycle robustness check for the project report -- confirms the
% estimator wasn't just tuned to fit one specific driving pattern.
%
% Requires tuned_ekf_params.mat (run tune_ekf_params.m first). Falls back
% to baseline values if that file isn't found.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc; close all;

if isfile('tuned_ekf_params.mat')
    load('tuned_ekf_params.mat', 'Qcov_tuned', 'Rcov_tuned');
    fprintf('Using tuned EKF parameters from tuned_ekf_params.mat\n\n');
else
    Qcov_tuned = [1e-10, 1e-6];
    Rcov_tuned = 1e-4;
    fprintf('No tuned_ekf_params.mat found -- using baseline defaults.\n');
    fprintf('(Run tune_ekf_params.m first for the best result.)\n\n');
end

cycles = {'*UDDS*.mat', '*US06*.mat'};
cycle_names = {'UDDS', 'US06'};

fprintf('%-10s %-14s %-14s %-14s %-14s\n', 'Cycle', 'RMSE CC(%)', 'RMSE EKF(%)', 'MaxErr CC(%)', 'MaxErr EKF(%)');
summary = zeros(length(cycles), 4);

for i = 1:length(cycles)
    [rmse_cc, rmse_ekf, maxerr_cc, maxerr_ekf] = estimate_soc(cycles{i}, Qcov_tuned, Rcov_tuned, true);
    summary(i,:) = [rmse_cc, rmse_ekf, maxerr_cc, maxerr_ekf];
    fprintf('%-10s %-14.3f %-14.3f %-14.3f %-14.3f\n', cycle_names{i}, rmse_cc, rmse_ekf, maxerr_cc, maxerr_ekf);
    saveas(gcf, sprintf('soc_estimation_%s.png', cycle_names{i}));
end

fprintf('\nSaved soc_estimation_UDDS.png and soc_estimation_US06.png\n');
fprintf('\nAverage EKF RMSE across both cycles: %.3f%%\n', mean(summary(:,2)));
fprintf('Average improvement factor (CC RMSE / EKF RMSE): %.2fx\n', mean(summary(:,1)./summary(:,2)));
