# Project instructions

## Goal
Build a clean dataset of euro area (and eventually US) sovereign bond futures from ECB EMIR data.

## Repository contents
- `ESMA_guidelines.pdf`: ESMA reporting guidelines for EMIR
- `emir_futures.do`: Stata do file from a colleague with a first pass at cleaning the data
- `eurex_sovereign_futures_contracts.xlsx`: Excel file with ISINs for the futures
- `01_gov_futures_list.do`: builds `gov_fut.csv` (ISIN, country, expiration date of the euro area contracts)
- `02_creating_table.ipynb`: builds the DEVO table `lab_prj_emir_ecb.hermesf_fut`, cleaning applied inside the queries
- `cleaning_decisions.txt`: brief record of the scope and cleaning decisions
- `03_plot_net_positions_de.do`: plots net positions in German futures by selected sector groups

## Local setup
The user's local folder is `C:\Users\hermesf\Projects\Future_FX_cleaning`.

## Working rules
- Work step by step. Only do what the user asks. Do not add optional extras or do things that were not requested.
- Keep answers brief and concise so progress is quick.
- Always work directly on the `main` branch. Do not create feature branches or pull requests.
- When drafting text, avoid sentence breaks using semicolons, colons or dashes.
