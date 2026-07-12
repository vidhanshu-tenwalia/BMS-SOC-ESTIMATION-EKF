# BMS SOC Estimation — Coulomb Counting vs. Extended Kalman Filter

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![MATLAB](https://img.shields.io/badge/MATLAB-R2026a-orange.svg)
![Simulink](https://img.shields.io/badge/Simulink-Model--Based%20Design-blue.svg)

State of Charge (SOC) estimation for a Panasonic 18650PF cell using a 1RC Thévenin equivalent circuit model, comparing a standard Coulomb Counting estimator against an Extended Kalman Filter (EKF), validated on the UDDS and US06 drive cycles in Simulink.

**[📄 Full Engineering Report (PDF)](report/BMS_SOC_Estimation_Report.pdf)**

---

## Motivation

Accurate State of Charge estimation is essential for electric vehicles because it directly influences range prediction, charging control, and battery protection. While Coulomb Counting is computationally efficient, accumulated sensor errors cause long-term drift. This project investigates whether an Extended Kalman Filter can provide more robust SOC estimation under different driving conditions.

---

## Key Features

- Extended Kalman Filter SOC Estimation
- Coulomb Counting Baseline
- 1RC Thévenin Battery Model
- HPPC Parameter Extraction
- MATLAB & Simulink Implementation
- UDDS + US06 Validation
- RMSE-Based Performance Evaluation
- Engineering Report Included

---

## Headline Result

| Drive Cycle | Coulomb Counting (RMSE) | EKF (RMSE) |
|---|---|---|
| UDDS (Gentle) | 3.81% | **0.93%** |
| US06 (Aggressive) | 0.79% | **0.95%** |

A jointly-tuned EKF holds SOC error to **0.93–0.95%** across both drive cycles, while Coulomb Counting swings **0.79–3.81%** depending on driving style. The EKF trades a small amount of best-case accuracy for a ~5x reduction in worst-case error — the property that actually matters for a BMS deployed in unpredictable, real-world conditions.

![RMSE Comparison](images/RMSE_Comparison.png)

---

## Why Coulomb Counting Isn't Enough

Coulomb Counting integrates measured current directly. It's simple and cheap, but every current sensor has bias and noise — and in open-loop integration, that error accumulates without bound over time, with no mechanism to correct it.

Unlike Coulomb Counting, the Extended Kalman Filter continuously fuses current integration with voltage measurements through a physics-based battery model, preventing long-term drift while remaining robust to sensor noise.

## Project Architecture

![Project Architecture](images/Project_Architecture.png)

HPPC characterization data feeds parameter extraction, which builds the 1RC Thévenin battery model. The same noisy current/voltage signals then drive both estimators — Coulomb Counting and the EKF — so the final RMSE comparison isolates the estimation algorithm as the only variable.

## Parameter Extraction (HPPC)

**Cell under test:**

| Cell | Chemistry | Capacity | Nominal Voltage |
|---|---|---|---|
| Panasonic 18650PF | NCA | 2.9 Ah | 3.6 V |

Parameters were extracted from real Hybrid Pulse Power Characterization (HPPC) test data using [`scripts/extract_hppc_params.m`](scripts/extract_hppc_params.m):

| Parameter | Value | Method |
|---|---|---|
| R0 | 25.48 mΩ (median, n=67) | Instantaneous voltage step at pulse onset |
| R1 | 4.48 mΩ (median, n=13) | Exponential relaxation curve fit |
| C1 | 2795.4 F | τ / R1 |
| τ | 12.52 s | Relaxation curve fit |
| OCV–SOC | 15-point LUT | 66 fully-relaxed rest periods (>1000 s) |

![HPPC Extraction](images/HPPC_Extraction.png)
![OCV-SOC Curve](images/OCV_SOC_Curve.png)

## EKF Formulation

The EKF treats SOC and RC-branch voltage V1 as a two-state system. Each cycle:

1. **Prediction** — project SOC and V1 forward using the current measurement and the battery model.
2. **Innovation** — compute the residual between predicted and measured terminal voltage.
3. **Kalman gain** — weigh model trust vs. measurement trust based on current uncertainty.
4. **Correction** — apply the weighted residual to update SOC, V1, and the error covariance.

![EKF Workflow](images/EKF_Workflow.png)

Full state-space equations and the OCV(SOC) Jacobian linearization are in the [PDF report](report/BMS_SOC_Estimation_Report.pdf).

## Filter Tuning

![Tuning Process](images/Tuning_Process.png)

Naively tuning Q/R against UDDS alone achieved 0.51% RMSE on UDDS but **diverged to 4.44%** on US06 — a classic overfitting failure. A joint-optimization routine minimizing worst-case RMSE across both cycles simultaneously (Q = diag([1e-11, 1e-6]), R = 10.0) traded a small amount of peak UDDS accuracy for stability across both cycles. See [`scripts/tune_ekf_params.m`](scripts/tune_ekf_params.m), [`scripts/diagnose_us06_ekf.m`](scripts/diagnose_us06_ekf.m), and [`scripts/tune_ekf_final_refinement.m`](scripts/tune_ekf_final_refinement.m) for the tuning progression.

## Results by Drive Cycle

<table>
<tr>
<td><img src="images/UDDS_Result.png" alt="UDDS Result"></td>
<td><img src="images/US06_Result.png" alt="US06 Result"></td>
</tr>
</table>

## Simulink Implementation

![Simulink Model](images/Simulink_Model.png)

Both estimators run inside a single model ([`model/BMS_SOC_Estimation.slx`](model/BMS_SOC_Estimation.slx)) against identical noisy current/voltage inputs, so the RMSE comparison isolates the estimation algorithm as the only variable.

## Repository Structure

```
BMS-SOC-Estimation-EKF/
│
├── model/
│   └── BMS_SOC_Estimation.slx          # Simulink model (CC + EKF, side by side)
│
├── scripts/
│   ├── estimate_soc.m                  # Core EKF SOC estimator
│   ├── validate_all_cycles.m           # Runs UDDS + US06 validation, computes RMSE
│   ├── tune_ekf_params.m               # Initial Q/R grid search
│   ├── diagnose_us06_ekf.m             # Diagnoses US06 instability from UDDS-only tuning
│   ├── tune_ekf_final_refinement.m     # Joint worst-case Q/R optimization
│   ├── load_for_simulink.m             # Loads drive-cycle + parameter data into the model
│   └── extract_hppc_params.m           # HPPC parameter extraction (R0, R1, C1, OCV-SOC LUT)
│
├── data/
│   ├── UDDS.mat                        # UDDS drive cycle data
│   ├── US06.mat                        # US06 drive cycle data
│   └── HPPC_Data.mat                   # Raw HPPC test data
│
├── images/                             # Diagrams and result plots used in this README/report
│
├── report/
│   └── BMS_SOC_Estimation_Report.pdf   # Full engineering report
│
├── README.md
├── LICENSE
└── .gitignore
```

## Software

- MATLAB R2026a
- Simulink
- Simulink core blocks + MATLAB Function block (no Simscape Electrical used in this model)

## Limitations & Future Work

- Results are specific to the Panasonic 18650PF cell; other chemistries require re-running HPPC extraction.
- Temperature effects on R0/OCV were not modeled.
- Planned: adaptive (fading-memory) Q/R tuning, validation on WLTP/HWFET cycles, pack-level SOC estimation with cell-to-cell variation.

---

## Key Takeaways

- Implemented a physics-based 1RC battery model.
- Extracted battery parameters from HPPC data.
- Compared Coulomb Counting with EKF under identical conditions.
- Identified and corrected overfitting through joint covariance tuning.
- Achieved robust SOC estimation (<1% RMSE) across UDDS and US06 drive cycles.

---

**Author:** Vidhanshu Tenwalia — [github.com/vidhanshu-tenwalia](https://github.com/vidhanshu-tenwalia)

