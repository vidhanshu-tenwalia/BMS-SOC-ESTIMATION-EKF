%% load_for_simulink.m
% Run this before opening/running the Simulink model. It loads
% drive_cycle_data.mat and reshapes each signal into the [time, value]
% matrix format that Simulink's "From Workspace" block expects.
%
% IMPORTANT: also computes SIM_TIMESTEP automatically from the actual data
% sampling rate. Different drive cycle files can have different sampling
% rates (the HPPC file here is ~1s, but UDDS/US06 are ~0.1s) -- this
% caused a real bug during development where the Simulink solver's
% fixed-step size, each block's individual Sample Time, and the EKF's
% "dt" input all need to match the ACTUAL data rate, not an assumed one.
% Always use SIM_TIMESTEP (not a hardcoded 1) for:
%   - Model Settings -> Solver -> Fixed-step size
%   - Every block's individual Sample Time (From Workspace blocks,
%     Discrete-Time Integrator, the MATLAB Function block)
%   - The Constant block feeding the EKF's "dt" input

clear; clc;
load('drive_cycle_data.mat', 'dc');
load('battery_params.mat', 'R0', 'R1', 'C1', 'tau_final', 'Q_RATED');
load('OCV_SOC_table.mat', 'SOC_breakpoints', 'OCV_values');

% [time, value] matrices for From Workspace blocks
I_noisy_ts = [dc.t, dc.I_noisy];
V_meas_ts  = [dc.t, dc.V_meas];
SOC_true_ts = [dc.t, dc.SOC_true];

SIM_STOP_TIME = dc.t(end);
SOC_INIT = dc.SOC_true(1);
SIM_TIMESTEP = median(diff(dc.t));  % actual sampling interval of THIS data file

fprintf('Workspace ready for Simulink.\n');
fprintf('Variables available: I_noisy_ts, V_meas_ts, SOC_true_ts\n');
fprintf('SIM_STOP_TIME = %.1f s, SOC_INIT = %.4f\n', SIM_STOP_TIME, SOC_INIT);
fprintf('SIM_TIMESTEP = %.3f s  <-- use this everywhere in Simulink, not a hardcoded value\n', SIM_TIMESTEP);
fprintf('Battery params in workspace: R0=%.5f, R1=%.5f, C1=%.1f, Q_RATED=%.2f\n', ...
    R0, R1, C1, Q_RATED);