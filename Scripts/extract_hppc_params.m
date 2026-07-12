%% extract_hppc_params.m
% Extracts Thevenin equivalent circuit battery parameters from HPPC test data
% for the Panasonic 18650PF cell (Kollmeyer et al., Univ. of Wisconsin-Madison).
%
% Inputs required:
%   - HPPC .mat file: 03-11-17_08_47_25degC_5Pulse_HPPC_Pan18650PF.mat
%     (must contain struct 'meas' with fields: Voltage, Current, Ah, Time)
%
% Outputs:
%   - OCV_SOC_table.mat  -> [SOC, OCV] lookup table for Simulink
%   - battery_params.mat -> R0, R1, C1, tau
%
% Author: Vidhanshu | EV BMS SOC Estimation Project

clear; clc; close all;

%% --- Load data ---
data = load('03-11-17_08.47 25degC_5Pulse_HPPC_Pan18650PF.mat');
meas = data.meas;

V  = meas.Voltage(:);
I  = meas.Current(:);
Ah = meas.Ah(:);
T  = meas.Time(:);

Q_RATED = 2.9;  % Ah, nominal capacity of Panasonic 18650PF (confirmed against rest-point SOC spacing)

%% --- Step 1: Identify rest segments (current ~ 0) ---
is_rest = abs(I) < 0.02;
d = diff([0; is_rest; 0]);       % pad edges so transitions are detected cleanly
rest_starts = find(d == 1);
rest_ends   = find(d == -1) - 1;

durations = T(rest_ends) - T(rest_starts);

fprintf('Total rest segments found: %d\n', length(durations));
fprintf('Rest duration range: %.1f s to %.1f s\n', min(durations), max(durations));

%% --- Step 2: Extract OCV points from long rests (>1000s = fully relaxed) ---
long_rest_idx = find(durations > 1000);
fprintf('Long (fully relaxed) rests found: %d\n', length(long_rest_idx));

ocv_points = [];  % [SOC, OCV]
for k = 1:length(long_rest_idx)
    idx = long_rest_idx(k);
    e = rest_ends(idx);
    soc = 1 + Ah(e) / Q_RATED;
    ocv = V(e);
    ocv_points = [ocv_points; soc, ocv]; %#ok<AGROW>
end

%% --- Step 3: Snap to clean 5% SOC checkpoints for a usable lookup table ---
targets = [1.00 0.95 0.90 0.80 0.70 0.60 0.50 0.40 0.30 0.25 0.20 0.15 0.10 0.05 0.00];
clean_table = zeros(length(targets), 2);
used = false(size(ocv_points,1),1);

for k = 1:length(targets)
    diffs = abs(ocv_points(:,1) - targets(k));
    diffs(used) = Inf;
    [~, best_idx] = min(diffs);
    clean_table(k,:) = [targets(k), ocv_points(best_idx,2)];
    used(best_idx) = true;
end

fprintf('\n--- OCV-SOC Lookup Table ---\n');
fprintf('SOC(%%)   OCV(V)\n');
for k = 1:size(clean_table,1)
    fprintf('%6.1f   %.4f\n', clean_table(k,1)*100, clean_table(k,2));
end

SOC_breakpoints = clean_table(:,1);
OCV_values      = clean_table(:,2);
save('OCV_SOC_table.mat', 'SOC_breakpoints', 'OCV_values');

%% --- Step 4: Estimate R0 from instantaneous voltage jump at pulse onset ---
pulse_start_idx = find(abs(I(1:end-1)) < 0.02 & abs(I(2:end)) > 0.5) + 1;

R0_samples = [];
for k = 1:length(pulse_start_idx)
    idx = pulse_start_idx(k);
    if idx < 2 || idx > length(V)-1
        continue;
    end
    dV = V(idx) - V(idx-1);
    dI = I(idx) - I(idx-1);
    if abs(dI) > 0.5
        r0 = abs(dV/dI);
        if r0 > 0.001 && r0 < 1.0
            R0_samples = [R0_samples; r0]; %#ok<AGROW>
        end
    end
end

R0 = median(R0_samples);
fprintf('\n--- R0 Estimation ---\n');
fprintf('Samples used: %d\n', length(R0_samples));
fprintf('R0 = %.2f mOhm (median), %.2f mOhm (mean), std = %.2f mOhm\n', ...
    R0*1000, mean(R0_samples)*1000, std(R0_samples)*1000);

%% --- Step 5: Estimate R1, C1 from post-pulse relaxation curves ---
pulse_end_idx = find(abs(I(1:end-1)) > 3 & abs(I(2:end)) < 0.02) + 1;

taus = [];
R1_samples = [];

ft = fittype('v_inf - dv*exp(-t/tau)', 'independent', 't', ...
    'coefficients', {'v_inf','dv','tau'});

for k = 1:length(pulse_end_idx)
    idx = pulse_end_idx(k);
    if idx+60 > length(V) || idx < 2
        continue;
    end
    seg_t = T(idx:idx+59) - T(idx);
    seg_v = V(idx:idx+59);
    if seg_t(end) < 30
        continue;
    end
    try
        opts = fitoptions(ft);
        opts.StartPoint = [seg_v(end), seg_v(end)-seg_v(1), 20];
        opts.Lower = [0, 0, 1];
        opts.Upper = [5, 1, 300];
        fitres = fit(seg_t, seg_v, ft, opts);
        tau = fitres.tau;
        dv  = fitres.dv;
        i_before = I(idx-1);
        if tau > 1 && tau < 300 && dv > 0 && dv < 0.5 && abs(i_before) > 0.5
            r1 = dv / abs(i_before);
            if r1 > 0.001 && r1 < 0.5
                taus = [taus; tau]; %#ok<AGROW>
                R1_samples = [R1_samples; r1]; %#ok<AGROW>
            end
        end
    catch
        continue;
    end
end

tau_final = median(taus);
R1 = median(R1_samples);
C1 = tau_final / R1;

fprintf('\n--- R1 / C1 Estimation ---\n');
fprintf('Relaxation curves used: %d\n', length(taus));
fprintf('Tau = %.2f s (median)\n', tau_final);
fprintf('R1  = %.2f mOhm (median)\n', R1*1000);
fprintf('C1  = %.1f F (derived: tau/R1)\n', C1);

fprintf('\n*** NOTE: R1/C1 are noisier estimates (fewer samples, some outlier pulses). ***\n');
fprintf('*** Recommend re-checking these once the Simulink model is running end-to-end. ***\n');

save('battery_params.mat', 'R0', 'R1', 'C1', 'tau_final', 'Q_RATED');

fprintf('\nSaved: OCV_SOC_table.mat, battery_params.mat\n');
fprintf('These feed directly into the Simulink Thevenin battery model.\n');
