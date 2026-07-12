function [rmse_cc, rmse_ekf, maxerr_cc, maxerr_ekf, R] = estimate_soc(cycle_pattern, Qcov_diag, Rcov, make_plot)
% ESTIMATE_SOC  Standalone MATLAB implementation of the Coulomb Counting +
% EKF SOC estimation pipeline. Mathematically identical to the Simulink
% model (BMS_SOC_Estimation.slx), but runs as a plain for-loop -- much
% faster for parameter tuning and for validating on multiple drive cycles.
%
% Usage:
%   [rmse_cc, rmse_ekf] = estimate_soc('*UDDS*.mat', [1e-10, 1e-6], 1e-4, true);
%   [rmse_cc, rmse_ekf] = estimate_soc('*US06*.mat', [1e-10, 1e-6], 1e-4, true);
%
% Inputs:
%   cycle_pattern - wildcard pattern to find the drive cycle .mat file,
%                   e.g. '*UDDS*.mat' or '*US06*.mat'
%   Qcov_diag     - 1x2 vector, EKF process noise covariance diagonal [SOC, V1]
%   Rcov          - scalar, EKF measurement noise covariance (voltage)
%   make_plot     - true/false, whether to generate the comparison figure
%
% Outputs:
%   rmse_cc, rmse_ekf       - RMSE in % SOC for each estimator
%   maxerr_cc, maxerr_ekf   - max absolute error in % SOC
%   R                       - struct with full time series (t, SOC_true,
%                             SOC_cc, SOC_ekf) for further analysis/plotting
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

if nargin < 4
    make_plot = false;
end

%% --- Load battery params + OCV table (must exist from extract_hppc_params.m) ---
load('battery_params.mat', 'R0', 'R1', 'C1', 'Q_RATED');
load('OCV_SOC_table.mat', 'SOC_breakpoints', 'OCV_values');
tau = R1 * C1;

%% --- Load drive cycle and build true SOC + noisy current (same as prepare_drive_cycle_data.m) ---
files = dir(cycle_pattern);
if isempty(files)
    error('No file matching pattern "%s" found in current folder.', cycle_pattern);
end
data = load(files(1).name);
meas = data.meas;

t = meas.Time(:);
I_true = meas.Current(:);
V_meas = meas.Voltage(:);
Ah = meas.Ah(:);

SOC_true = min(max(1 + Ah / Q_RATED, 0), 1);

rng(42);  % same seed as prepare_drive_cycle_data.m for consistency
CURRENT_BIAS = 0.03;
CURRENT_NOISE_STD = 0.02;
I_noisy = I_true + CURRENT_BIAS + CURRENT_NOISE_STD * randn(size(I_true));

n = length(t);
dt_vec = [diff(t); mean(diff(t))];  % per-step dt (handles any slight sampling variation)

%% --- Coulomb Counting (matches Simulink Integrator + Gain) ---
SOC_cc = zeros(n, 1);
SOC_cc(1) = SOC_true(1);
for k = 1:n-1
    SOC_cc(k+1) = SOC_cc(k) + (dt_vec(k) / (Q_RATED * 3600)) * I_noisy(k);
end
SOC_cc = min(max(SOC_cc, 0), 1);

%% --- EKF (matches ekf_soc_estimator.m exactly) ---
x = [SOC_true(1); 0];
P = diag([1e-4, 1e-4]);
SOC_ekf = zeros(n, 1);
SOC_ekf(1) = x(1);

for k = 1:n-1
    dt = dt_vec(k);
    a = exp(-dt / tau);
    Idis = -I_noisy(k);

    % Predict
    SOC_pred = x(1) - (dt / (Q_RATED * 3600)) * Idis;
    V1_pred  = a * x(2) + R1 * (1 - a) * Idis;
    x_pred = [SOC_pred; V1_pred];

    F = [1, 0; 0, a];
    Qc = diag(Qcov_diag);
    P_pred = F * P * F' + Qc;

    % Update
    OCV_pred = interp1(SOC_breakpoints, OCV_values, x_pred(1), 'linear', 'extrap');
    dSOC = 1e-4;
    OCV_p = interp1(SOC_breakpoints, OCV_values, x_pred(1) + dSOC, 'linear', 'extrap');
    OCV_m = interp1(SOC_breakpoints, OCV_values, x_pred(1) - dSOC, 'linear', 'extrap');
    dOCV_dSOC = (OCV_p - OCV_m) / (2 * dSOC);

    H = [dOCV_dSOC, -1];
    Vt_pred = OCV_pred - Idis * R0 - x_pred(2);

    y = V_meas(k+1) - Vt_pred;
    S = H * P_pred * H' + Rcov;
    K = P_pred * H' / S;

    x_upd = x_pred + K * y;
    P_upd = (eye(2) - K * H) * P_pred;
    x_upd(1) = min(max(x_upd(1), 0), 1);

    x = x_upd;
    P = P_upd;
    SOC_ekf(k+1) = x(1);
end

%% --- Metrics ---
err_cc  = (SOC_cc  - SOC_true) * 100;
err_ekf = (SOC_ekf - SOC_true) * 100;

rmse_cc  = sqrt(mean(err_cc.^2));
rmse_ekf = sqrt(mean(err_ekf.^2));
maxerr_cc  = max(abs(err_cc));
maxerr_ekf = max(abs(err_ekf));

R.t = t; R.SOC_true = SOC_true; R.SOC_cc = SOC_cc; R.SOC_ekf = SOC_ekf;

if make_plot
    figure('Color', 'w');
    subplot(2,1,1);
    plot(t/60, SOC_true*100, 'k-', t/60, SOC_cc*100, t/60, SOC_ekf*100);
    legend('True SOC', 'Coulomb Counting', 'EKF'); ylabel('SOC (%)');
    title(sprintf('%s : RMSE CC=%.2f%%, EKF=%.2f%%', files(1).name, rmse_cc, rmse_ekf));
    grid on;
    subplot(2,1,2);
    plot(t/60, err_cc, t/60, err_ekf); yline(0,'k--');
    legend('CC error', 'EKF error'); xlabel('Time (min)'); ylabel('Error (%)');
    grid on;
end
end
