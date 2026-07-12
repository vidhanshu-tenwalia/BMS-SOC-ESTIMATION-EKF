%% prepare_drive_cycle_data.m
% Prepares a drive cycle test file (UDDS or US06) for use in the Simulink
% SOC estimation model. Generates:
%   - True reference SOC (from precise lab Ah measurement, assumes start at 100%)
%   - A realistically noisy/biased current signal (what a real BMS current
%     sensor would report) -- this is what the estimators actually see
%   - The real measured voltage (used as feedback by the EKF only)
%
% Run extract_hppc_params.m FIRST -- this script needs battery_params.mat
% and OCV_SOC_table.mat to exist in the same folder.
%
% Output: drive_cycle_data.mat, containing a struct 'dc' with fields:
%   dc.t        -- time vector (s)
%   dc.I_true   -- true current from lab equipment (A)
%   dc.I_noisy  -- current as a real BMS sensor would report it (A)
%   dc.V_meas   -- measured terminal voltage (V)
%   dc.SOC_true -- reference SOC computed from true Ah integration (0-1)
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc; close all;

if ~isfile('battery_params.mat') || ~isfile('OCV_SOC_table.mat')
    error(['Missing battery_params.mat / OCV_SOC_table.mat.\n' ...
           'Run extract_hppc_params.m first, in this same folder.']);
end
load('battery_params.mat', 'Q_RATED');

%% --- Auto-locate a drive cycle file (UDDS preferred, falls back to US06) ---
dc_files = dir('*UDDS*.mat');
if isempty(dc_files)
    dc_files = dir('*US06*.mat');
end
if isempty(dc_files)
    error('No UDDS or US06 .mat file found in current folder.');
end
fprintf('Loading drive cycle file: %s\n', dc_files(1).name);
data = load(dc_files(1).name);
meas = data.meas;

t  = meas.Time(:);
I_true = meas.Current(:);     % A (negative = discharge, per dataset convention)
V_meas = meas.Voltage(:);
Ah = meas.Ah(:);

%% --- True reference SOC ---
% Test starts at a fully charged rest, so SOC(0) = 1. Integrate measured Ah
% (already computed by the lab equipment at high precision) to get ground truth.
SOC_true = 1 + Ah / Q_RATED;
SOC_true = min(max(SOC_true, 0), 1);   % clip to [0,1] for safety

%% --- Simulate a realistic current sensor (bias + noise) ---
% Real BMS current sensors (Hall-effect or shunt-based) have:
%   - A small constant offset/bias (e.g. 20-50 mA), which is what makes
%     pure Coulomb counting drift over time
%   - Gaussian measurement noise on top of that
rng(42);  % reproducible noise
CURRENT_BIAS = 0.03;     % A, constant sensor offset
CURRENT_NOISE_STD = 0.02; % A, sensor noise std dev

I_noisy = I_true + CURRENT_BIAS + CURRENT_NOISE_STD * randn(size(I_true));

%% --- Package and save ---
dc.t = t;
dc.I_true = I_true;
dc.I_noisy = I_noisy;
dc.V_meas = V_meas;
dc.SOC_true = SOC_true;

save('drive_cycle_data.mat', 'dc');

fprintf('\nSaved drive_cycle_data.mat\n');
fprintf('Duration: %.1f minutes\n', (t(end)-t(1))/60);
fprintf('SOC range covered: %.1f%% to %.1f%%\n', min(SOC_true)*100, max(SOC_true)*100);
fprintf('Current sensor bias injected: %.0f mA, noise std: %.0f mA\n', ...
    CURRENT_BIAS*1000, CURRENT_NOISE_STD*1000);

%% --- Quick sanity plot ---
figure('Name','Drive Cycle Data Check');
subplot(3,1,1);
plot(t/60, I_true, 'b'); hold on; plot(t/60, I_noisy, 'r:');
legend('True current','Noisy current (sensor)'); ylabel('Current (A)');
title('Drive cycle current: true vs sensor-corrupted');

subplot(3,1,2);
plot(t/60, V_meas, 'k');
ylabel('Voltage (V)'); title('Measured terminal voltage');

subplot(3,1,3);
plot(t/60, SOC_true*100, 'g');
ylabel('SOC (%)'); xlabel('Time (min)'); title('True reference SOC');
