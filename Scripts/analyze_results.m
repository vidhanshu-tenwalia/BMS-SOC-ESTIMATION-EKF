%% analyze_results.m
% Computes RMSE for Coulomb Counting vs EKF SOC estimation, and produces
% a publication-quality comparison plot for the GitHub repo / report.
%
% Run this AFTER running the Simulink model (BMS_SOC_Estimation.slx) with
% the three To Workspace blocks wired in.
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clc; close all;

if ~exist('out', 'var')
    error(['Variable "out" not found. Run the Simulink model first ' ...
           '(BMS_SOC_Estimation.slx), then run this script.']);
end

%% --- Extract signals robustly (handles both plain array and timeseries output) ---
SOC_CC   = extract_signal(out.SOC_CC_sim);
SOC_EKF  = extract_signal(out.SOC_EKF_sim);
SOC_true = extract_signal(out.SOC_true_sim);

% Time vector: prefer out.tout if available, else reconstruct from length
if isfield(out, 'tout') || isprop(out, 'tout')
    t = out.tout;
else
    t = (0:length(SOC_true)-1)';  % fallback: sample index
end

% Trim to matching lengths just in case of off-by-one from logging
n = min([length(SOC_CC), length(SOC_EKF), length(SOC_true), length(t)]);
SOC_CC = SOC_CC(1:n); SOC_EKF = SOC_EKF(1:n); SOC_true = SOC_true(1:n); t = t(1:n);

%% --- Compute error metrics ---
err_CC  = SOC_CC  - SOC_true;
err_EKF = SOC_EKF - SOC_true;

rmse_CC  = sqrt(mean(err_CC.^2))  * 100;   % in % SOC
rmse_EKF = sqrt(mean(err_EKF.^2)) * 100;

maxerr_CC  = max(abs(err_CC))  * 100;
maxerr_EKF = max(abs(err_EKF)) * 100;

fprintf('\n===== SOC Estimation Accuracy =====\n');
fprintf('Coulomb Counting : RMSE = %.2f%%  |  Max error = %.2f%%\n', rmse_CC, maxerr_CC);
fprintf('EKF              : RMSE = %.2f%%  |  Max error = %.2f%%\n', rmse_EKF, maxerr_EKF);
fprintf('Improvement      : %.1fx lower RMSE with EKF\n', rmse_CC/rmse_EKF);
fprintf('====================================\n\n');

%% --- Plot 1: SOC comparison ---
figure('Name','SOC Estimation Comparison','Color','w','Position',[100 100 900 600]);

subplot(2,1,1);
plot(t/60, SOC_true*100, 'k-', 'LineWidth', 1.5); hold on;
plot(t/60, SOC_CC*100, 'Color', [0.85 0.55 0.1], 'LineWidth', 1.2);
plot(t/60, SOC_EKF*100, 'Color', [0.1 0.5 0.4], 'LineWidth', 1.2);
xlabel('Time (min)'); ylabel('SOC (%)');
title('SOC Estimation: Coulomb Counting vs EKF (UDDS drive cycle, 25\circC)');
legend('True SOC (reference)', 'Coulomb Counting', 'EKF', 'Location', 'northeast');
grid on;

subplot(2,1,2);
plot(t/60, err_CC*100, 'Color', [0.85 0.55 0.1], 'LineWidth', 1.2); hold on;
plot(t/60, err_EKF*100, 'Color', [0.1 0.5 0.4], 'LineWidth', 1.2);
yline(0, 'k--');
xlabel('Time (min)'); ylabel('SOC error (%)');
title(sprintf('Estimation error   |   RMSE: CC = %.2f%%, EKF = %.2f%%', rmse_CC, rmse_EKF));
legend('Coulomb Counting error', 'EKF error', 'Location', 'best');
grid on;

saveas(gcf, 'soc_estimation_comparison.png');
fprintf('Saved plot: soc_estimation_comparison.png\n');

%% --- Helper function ---
function y = extract_signal(sig)
    if isa(sig, 'timeseries')
        y = sig.Data(:);
    elseif isstruct(sig) && isfield(sig, 'signals')
        y = sig.signals.values(:);
    else
        y = sig(:);
    end
end
