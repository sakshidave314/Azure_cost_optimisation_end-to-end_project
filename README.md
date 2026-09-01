# Azure Cost Optimisation — End-to-End FinOps Analysis

Turning a messy 21K-row Azure billing export into an executive dashboard that identifies idle-resource waste, reservation opportunities, and untagged spend — using Python, SQL, and Power BI.



## 📌 TL;DR

Cloud spend grows quietly until Finance asks "why is the Azure bill up 30%?" and nobody has a clean answer. This project simulates that exact FinOps scenario end-to-end:

Cleaned a raw, deliberately messy 21,024-row Azure billing export (inconsistent date formats, missing IDs, duplicate rows, unstandardized service names) using Python/Pandas.
Analyzed it with 19 advanced PostgreSQL queries — window functions, CTEs, JSON tag parsing, and statistical outlier detection — to answer the exact questions a CFO, FinOps lead, or engineering manager would ask.
Visualized the findings in a 2-page Power BI dashboard built for executives: one page for the headline numbers, one page for the actionable findings.



## The Business Problem

A mid-size company's Azure spend has been rising month over month, and leadership has no reliable way to answer basic financial questions about it:

Spend is scattered across subscriptions, resource groups, and teams with no single source of truth.
A large share of resources are suspected to be idle (provisioned, billed, barely used) — but nobody has quantified the waste.
Most workloads are still on On-Demand pricing, with reservations/savings plans used inconsistently.
Tagging is incomplete, so spend can't be reliably attributed to a team or cost center for chargeback.
There's no defined process for catching cost spikes before the invoice arrives.

### The goal of this project: build the analysis and reporting layer a FinOps analyst would deliver in their first 30 days — quantify the waste, rank it by impact, and hand leadership a dashboard they can act on.

## ❓ Stakeholder Questions This Project Answers

These are the actual questions the SQL layer (azure_cost_optimisation.sql) was written to answer, grouped by the stakeholder who'd ask them:

### CFO / Finance

What's our total spend by month, and what's the MoM / YoY trend?
Which subscriptions account for the top 80% of spend (Pareto analysis)?
Which days spiked more than 2 standard deviations above the trailing 30-day average, and what did those spikes cost us in total?
What's a reasonable daily/weekly spend threshold to alert on going forward?

### Engineering / Resource Owners

Which resource groups or teams are the biggest spenders?
Which resources have near-zero usage but non-zero cost over the last 30 days?
Which resources show that idle pattern every single day (not just once), and what's the projected annualized savings if we deleted or downsized them?
Which resource groups have the highest concentration of idle resources?

### FinOps / Procurement

What % of spend is OnDemand vs. Reservation vs. Savings Plan vs. Spot, and how has that mix trended?
Which resources show steady, predictable daily usage (good Reserved Instance / Savings Plan candidates) vs. spiky, intermittent usage (bad candidates)?
For steady-state On-Demand resources, what would switching to a 1-year commitment save at a typical 30–40% discount rate?

### Governance / FinOps Maturity

What % of total spend has no team tag, no cost center, or a malformed tag?
Which resource groups have the worst tag compliance, and is the untagged spend concentrated in a few resource groups (easy fix) or spread everywhere (harder fix)?
If we can attribute tagged spend, what does spend-by-team actually look like?
Are non-prod (dev/staging/sandbox) resources running uniformly across all 7 days — i.e., is anyone turning them off? What would shutting them down nights and weekends save?

## 🏗️ Project Architecture

Data flow: Raw messy CSV (Azure Cost Management export, 21,024 rows) → Data Cleaning → Analysis Layer → Reporting Layer

1. Data Cleaning — Azure_cost_optimisation_end_to_end_analysis.ipynb (Python + Pandas)
Standardize column names & casing
Impute missing values (mode-based)
Remove duplicate records
Normalize region & service-name spellings



2. Analysis Layer — azure_cost_optimisation.sql (PostgreSQL)
19 queries covering trend analysis, Pareto ranking, idle-resource detection, tag-compliance audit, anomaly detection (stddev-based), pricing-mix analysis, and commitment/RI candidacy scoring
   
3. Reporting Layer — Microsoft_azure_cost_optimisation_analysis.pbix (Power BI)
Executive Overview page (KPIs & trends)
Findings & Actions page (waste & savings)


### Why this stack: Pandas handles the messy, row-level cleaning that's painful in SQL. PostgreSQL does the heavy lifting — window functions (LAG, cumulative SUM() OVER), CTEs, and JSON tag parsing — that would be slow or awkward in Power Query. Power BI turns the query outputs into something a non-technical stakeholder can actually use in a meeting.

## 🧹 Data Cleaning (Python / Pandas)

1. The source file (azure_billing_export_messy.csv, 21,024 rows × 14 columns) was intentionally messy to mirror a real-world export. Key cleaning steps in the notebook:

2. Inconsistent column naming (UsageDate, SubscriptionId, …) → renamed to a consistent Snake_Case schema.

3. Missing values across Service_Name, Subscription_Name, Resource_Group, Tags, etc. → categorical fields imputed with mode; ID fields imputed with 'Unknown'.

4. 274 exact duplicate rows → identified and dropped.

5. Inconsistent region naming (westeurope, eastus2, southeastasia, …) → standardized to display names (West Europe, East US, …).

6. Inconsistent service-name casing/spelling (cosmos db, SQL database , …) → trimmed, title-cased, and mapped to a canonical service list (Cosmos DB, SQL Database, Azure Kubernetes Service, …).

7. Mixed date formats (2026-03-24 vs 04/11/2026) → standardized during load for reliable date-based analysis downstream.

8. The cleaned dataset (azure_billing) is the single source of truth feeding both the SQL analysis and the Power BI model.

## 🔍 SQL Analysis Highlights

19 production-style queries in azure_cost_optimisation.sql, organized around five themes:

1. Spend trends — monthly spend with MoM/YoY growth via LAG() window functions; Pareto (80/20) ranking of subscriptions and resource groups using cumulative-sum windows.

2. Idle-resource waste — flags resources with usage ≤ 0.3 units but non-zero cost over a rolling 90-day window, then annualizes the projected savings (90-day cost × 365/90) if those resources were deleted or rightsized.

3. Anomaly detection — a rolling 30-day mean/std-dev model flags days where spend exceeds the trailing average by more than 2 standard deviations, and quantifies the total cost of those spike days.

4. Tag governance — parses the Tags JSON column to measure tag-compliance rate by resource group, quantify untagged spend, and produce a real spend-by-team breakdown wherever tags exist.

5. Commitment strategy — a coefficient-of-variation model classifies each resource's daily usage as Steady, Moderately Variable, or Spiky to flag good vs. bad Reserved Instance / Savings Plan candidates, and estimates savings from a non-prod nights-and-weekends shutdown schedule.

## 📊 Dashboard Screenshots


### Page 1 — Executive Overview


KPI cards for Total Spend, MoM Spend Change %, OnDemand Spend %, and Total Identified Savings Opportunity, alongside a spend trend line, a spend-vs-OnDemand area chart, an environment/service spend funnel, and a subscription × service pivot matrix. Filterable by date, service, subscription, and pricing model.

markdown
![Executive Overview](https://github.com/sakshidave314/Azure_cost_optimisation_end-to-end_project/blob/8c06f3390315c95f7344f60b07f03c50747a5813/Executive%20Overview.png)

### Page 2 — Findings & Actions


KPI cards for Idle Resource Cost, Annualized Idle Waste, Non-Prod Spend, and Estimated Reservation Savings, a pricing-mix donut chart, idle-cost-by-subscription bar chart, and an idle-vs-committed matrix by service and resource group — the page built to drive action items in a stakeholder review.

markdown
![Findings and Actions](assets/findings-and-actions.png)

## 💡 Key Findings

A note on these numbers: the dataset behind this project totals 20,750 cleaned billing records ($75,103.16 total spend) spanning Feb 1 – Jul 28, 2026 (178 days). Of those, 4,240 records (20.4%) have a missing Usage_Date — a gap the cleaning notebook doesn't currently handle — so every date-based query below (trends, anomalies, idle windows) correctly filters those out per the SQL's WHERE "Usage_Date" IS NOT NULL clause, and runs against the remaining 16,510 dated records ($60,105.53). Flagging this here rather than smoothing it over on purpose — it's exactly the kind of caveat a real stakeholder review would surface.

💰 $23,604 in identified savings across the two clearest levers found — ~31% of total analyzed spend — made up of a $23,349 non-prod shutdown opportunity and $255/year in annualized idle-resource waste (breakdown below).

🧟 17 resources show usage that never exceeds 0.3 units on any day within the most recent 90-day window while still accruing cost — $62.93 over that window, or $255.23/year annualized if left unaddressed. Small in absolute terms, but a useful early-warning signal since none of them were caught by manual review.

📊 Pricing mix is already fairly balanced — 25.98% On-Demand, 27.34% Savings Plan, 23.08% Reservation, 23.60% Spot. Notably, a coefficient-of-variation analysis found zero of the 140 actively-used resources qualify as "Steady" commitment candidates (136 are Moderately Variable, 4 are Spiky) — so the honest recommendation is to hold on new 1-year commitments until usage patterns stabilize, rather than force a reservation purchase the data doesn't support.

🏷️ 20.26% of records (21.33% of spend — $16,020.84) carry no team tag. That untagged spend isn't evenly spread: just 5 resource groups (rg-analytics, rg-webapp-prod, rg-webapp-dev, Unknown, rg-networking) account for ~83% of it — a genuinely quick governance fix.

🌙 67 non-prod resources (dev/staging/sandbox) run all 7 days a week, totaling $36,320.80 over the 178-day window. A nights + weekends shutdown schedule (108 of 168 weekly hours off) would recover $23,349.08 (64.3%), leaving $12,971.71 in unavoidable non-prod spend.

📈 11 spike days exceeded 2 standard deviations above the trailing 30-day average, together costing $7,700.74. Based on the trailing 8-week average and volatility, a ~$2,779/week alert threshold is a reasonable go-forward budget alert.

## 🧠 Insights & Recommendations

Turning the query outputs into decisions is the point of the exercise — here's how each finding translates into an action, ranked roughly by how quickly it can be actioned. Replace the [ ] placeholders with your real numbers once you've run the queries.

Here's how each finding translates into an action, ranked roughly by how quickly it can be actioned:

1. Idle resources — 17 flagged, $255.23/year annualized 17 resources never exceed 0.3 usage units on any day within the most recent 90-day window, yet still accrued $62.93 in cost over that window ($255.23/year annualized).

Recommendation: Delete or downsize the flagged resources; set up a monthly "idle resource" report using the same 90-day logic so this doesn't silently reaccumulate.
Owner: Engineering / Resource Owners
Priority: 🔴 High — fastest, lowest-risk savings

2. Tag compliance — 20.26% of records, $16,020.84 untagged 20.26% of records ($16,020.84, 21.33% of spend) carry no team tag — and it's concentrated, not spread out: 5 resource groups (rg-analytics, rg-webapp-prod, rg-webapp-dev, Unknown, rg-networking) account for ~83% of all untagged spend.

Recommendation: Enforce tagging at resource-creation time via Azure Policy (deny/append team and environment tags); backfill those 5 resource groups first since that's where 83% of the problem lives.
Owner: Cloud Governance / Platform Team
Priority: 🔴 High — unlocks accurate chargeback

3. Non-prod always-on resources — 67 resources, $23,349.08 recoverable 67 non-prod resources (dev/staging/sandbox) run all 7 days a week, representing $36,320.80 in spend over the 178-day analysis window.

Recommendation: Implement an auto-shutdown schedule (nights + weekends) for these 67 resources via Azure Automation or built-in VM auto-shutdown; this recovers an estimated $23,349.08 (64.3%) with no functionality loss.
Owner: Engineering
Priority: 🟠 Medium — quick to implement, needs a rollout window

4. Reservation/Savings Plan candidacy — 0 of 140 resources qualify Pricing mix is already balanced (25.98% On-Demand / 27.34% Savings Plan / 23.08% Reservation / 23.60% Spot), and a coefficient-of-variation analysis found 0 of 140 actively-used resources qualify as low-variance "Steady" commitment candidates — 136 are Moderately Variable, 4 are Spiky.

Recommendation: Don't force new 1-year commitments right now — committing spiky or moderately variable usage locks in capacity you won't fully use. Re-run this classification quarterly and move resources to Reservations/Savings Plans only once they show consistently low variance.
Owner: FinOps / Procurement
Priority: 🟢 Low — correctly identified as "not yet," not a missed opportunity

5. Subscription concentration — 3 of 8 subscriptions drive 80%+ of spend 3 subscriptions — Sandbox (38.26%), Development (28.09%), Production (16.93%) — account for the top 80% of spend (83.28% cumulative), out of 8 total subscription-name variants in the data.

Recommendation: Prioritize cost-review meetings and optimization effort on these 3 subscriptions rather than spreading attention evenly across all 8 — it's where the leverage is. Also worth noting: 8 variants for what's likely 4 actual environments suggests a subscription-naming/casing cleanup is overdue.
Owner: FinOps Lead
Priority: 🟡 Ongoing — informs where to focus, not a one-time fix

6. Spend anomalies — 11 spike days, $7,700.74 total 11 days spiked more than 2 standard deviations above the trailing 30-day average, together costing $7,700.74.

Recommendation: Set the calculated ~$2,779/week alert threshold (trailing 8-week average + 2σ) as a budget alert in Azure Cost Management so spikes are caught within a day, not at month-end invoice review.
Owner: FinOps / Engineering
Priority: 🟡 Ongoing — prevention, not remediation

### Overall recommendation: address rows 1–2 first — they're the highest-savings, lowest-effort items and don't require a purchasing or architecture decision. Row 3 needs a short implementation project but is still low-risk and is the single largest lever found ($23,349). Row 4 is a "no action, revisit later" call rather than a missed opportunity — the data doesn't currently support new commitments, and pretending otherwise would waste budget. Rows 5–6 aren't one-time fixes; they're the operating model this dashboard is meant to support going forward — a monthly review against these two views (Executive Overview for the trend, Findings & Actions for the backlog) turns this from a one-off audit into an ongoing cost-governance process.

## 🛠️ Tech Stack
Data cleaning & wrangling — Python, Pandas, Jupyter Notebook
Analysis & aggregation — PostgreSQL (window functions, CTEs, JSON parsing)
Reporting & visualization — Power BI Desktop
Source data — Simulated Azure Cost Management billing export (CSV)

## 📂 Repository Structure
├── Azure_cost_optimisation_end_to_end_analysis.ipynb   # Data cleaning (Python/Pandas)
├── azure_cost_optimisation.sql                          # 19 analysis queries (PostgreSQL)
├── Microsoft_azure_cost_optimisation_analysis.pbix       # Power BI dashboard (2 pages)
├── assets/                                               # Dashboard screenshots (add your own)
└── README.md

## 🚀 What This Project Demonstrates
End-to-end FinOps workflow: raw export → cleaning → analysis → executive-ready reporting.

Advanced SQL: window functions (LAG, SUM() OVER, STDDEV_SAMP() OVER), CTEs, JSON parsing, statistical anomaly detection, cumulative-percentage (Pareto) analysis.

Data cleaning judgment: sensible imputation strategy per column type, deduplication, categorical standardization.
Business framing: every query maps directly to a question a real stakeholder (CFO, engineering manager, FinOps lead) would ask — not just a technical exercise.

Dashboard design: a two-page structure that separates "what's the headline number" (Executive Overview) from "what do we do about it" (Findings & Actions).

## 📬 Contact

[Sakshi Dave] — · sakshidave115@gmail.com

If you're a recruiter or hiring manager and want to talk through the design decisions behind this project, I'd love to chat.
