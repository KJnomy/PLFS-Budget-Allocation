# PLFS Data Analysis & Budget Allocation Optimization

## Overview

This project works with **Periodic Labour Force Survey (PLFS)** microdata to analyze employment patterns and optimally allocate a fixed training budget across demographic groups (area, state, caste, gender, etc.) with the objective of **maximizing employment outcomes**.

The workflow covers **raw data ingestion → cleaning & merging → feature construction → optimization modeling → results & reporting**. The project is designed to be reproducible, transparent, and extensible for policy analysis and research.

---

## Key Objectives

* Clean and process raw PLFS unit-level data files (CPERV1, CHHV1).
* Merge household- and person-level datasets correctly.
* Construct demographic and employment indicators.
* Estimate employment conversion rates.
* Allocate a fixed budget using **linear programming** to maximize employment.
* Impose policy-relevant constraints (caste, gender, area, state).

---

## Data Description

### Raw Data Files

* **CPERV1.TXT** – Person-level PLFS data
* **CHHV1.TXT** – Household-level PLFS data
* **Layout Excel File** – Column positions, variable names, and coding

> Note: Raw PLFS data are fixed-width text files and require layout-based parsing.

### Key Variables Used

* Demographics: Area, State, Caste, Gender, Age
* Employment Status
* Household Size
* Survey Weights (if applicable)


## Methodology

### 1. Data Reading & Cleaning

* Fixed-width files are read using layout specifications.
* Missing values, invalid codes, and inconsistencies are handled.

### 2. Data Merging

* Household-level data are merged with person-level data using:

  * Household identifiers
  * Household size information

### 3. Feature Engineering

* Creation of demographic groups:

  * Area × State × Caste × Gender
* Employment indicators and conversion rates.

### 4. Optimization Model

* **Objective**: Maximize total expected employment.
* **Decision Variables**: Budget allocation across demographic groups.
* **Constraints**:

  * Total budget ≤ B
  * Non-negativity
  * Optional caste/gender/area/state minimum or maximum shares

The optimization problem is solved using **linear programming (lpSolve in R)**.

---

## Tools & Technologies

* **R**
* Packages:

  * `readr`, `dplyr`, `tidyr`
  * `lpSolve`
  * `ggplot2`

---

## How to Run

1. Place raw PLFS files in `data/raw/`.
2. Update file paths in `read_data.R`.
3. Run scripts in order:

   1. `read_data.R`
   2. `clean_merge.R`
   3. `features.R`
   4. `optimization.R`
4. Results will be saved in `outputs/`.

---

## Outputs

* Optimal budget allocation table by demographic group
* Employment gain estimates
* Summary statistics and visualizations

---

## Assumptions & Limitations

* Conversion rates are assumed to be stable within demographic groups.
* Results depend on data quality and model constraints.
* The model is static and does not capture dynamic labor market effects.

---

## Future Extensions

* Incorporate uncertainty and robustness checks
* Add nonlinear or stochastic optimization
* Build an interactive dashboard
* Extend to time-series PLFS rounds

---
