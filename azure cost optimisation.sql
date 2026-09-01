

-- 1. What's total spend by month, and what's the MoM/YoY trend?--

WITH monthly_spend AS (
    SELECT
        DATE_TRUNC('month', "Usage_Date") AS month_start,
        SUM("Cost") AS total_spend
    FROM azure_billing
    WHERE "Usage_Date" IS NOT NULL
    GROUP BY DATE_TRUNC('month', "Usage_Date")
),
spend_trends AS (
    SELECT
        month_start,
        total_spend,
        LAG(total_spend) OVER (
            ORDER BY month_start
        ) AS previous_month_spend,
        LAG(total_spend, 12) OVER (
            ORDER BY month_start
        ) AS previous_year_spend
    FROM monthly_spend
)
SELECT
    TO_CHAR(month_start, 'YYYY-MM') AS month,
    ROUND(total_spend::numeric, 2) AS total_spend,
    ROUND(
        ((total_spend - previous_month_spend)
        / NULLIF(previous_month_spend, 0))::numeric * 100,
        2
    ) AS mom_growth_percent,
    ROUND(
        ((total_spend - previous_year_spend)
        / NULLIF(previous_year_spend, 0))::numeric * 100,
        2
    ) AS yoy_growth_percent
FROM spend_trends
ORDER BY month_start;

-- 2. Which subscriptions account for the top 80% of spend?--

WITH subscription_spend AS (
    SELECT
        "Subscription_Name",
        SUM("Cost") AS total_spend
    FROM azure_billing
    WHERE "Subscription_Name" IS NOT NULL
    GROUP BY "Subscription_Name"
),

ranked_subscriptions AS (
    SELECT
        "Subscription_Name",
        total_spend,
        SUM(total_spend) OVER (
            ORDER BY total_spend DESC
        ) AS cumulative_spend,
        SUM(total_spend) OVER () AS overall_spend
    FROM subscription_spend
)

SELECT
    "Subscription_Name",
    ROUND(total_spend::numeric, 2) AS total_spend,
    ROUND(
        (total_spend / NULLIF(overall_spend, 0) * 100)::numeric,
        2
    ) AS spend_percentage,
    ROUND(
        (cumulative_spend / NULLIF(overall_spend, 0) * 100)::numeric,
        2
    ) AS cumulative_percentage
FROM ranked_subscriptions
WHERE cumulative_spend - total_spend < overall_spend * 0.80
ORDER BY total_spend DESC;

--3. Which resource groups or teams are the biggest spenders?--
SELECT
    "Resource_Group",
    ROUND(SUM("Cost")::numeric, 2) AS total_spend,
    ROUND(
        (SUM("Cost") / SUM(SUM("Cost")) OVER () * 100)::numeric,
        2
    ) AS spend_percentage
FROM azure_billing
WHERE "Resource_Group" IS NOT NULL
GROUP BY "Resource_Group"
ORDER BY total_spend DESC
LIMIT 10;

--4. What's the projected annualized savings if we deleted/downsized every flagged idle resource?--
WITH date_range AS (
    SELECT
        MAX("Usage_Date")::date AS end_date,
        MAX("Usage_Date")::date - INTERVAL '89 days' AS start_date
    FROM azure_billing
),

resource_daily AS (
    SELECT
        "Resource_Id",
        "Usage_Date"::date AS usage_date,
        SUM("Usage_Quantity") AS daily_usage,
        SUM("Cost") AS daily_cost
    FROM azure_billing
    WHERE "Usage_Date"::date BETWEEN
          (SELECT start_date FROM date_range)
          AND
          (SELECT end_date FROM date_range)
    GROUP BY
        "Resource_Id",
        "Usage_Date"::date
),

flagged_resources AS (
    SELECT
        "Resource_Id",
        SUM(daily_cost) AS total_90_day_cost
    FROM resource_daily
    GROUP BY "Resource_Id"
    HAVING
        MAX(daily_usage) <= 0.3
        AND SUM(daily_cost) > 0
)

SELECT
    COUNT(*) AS flagged_resources,

    ROUND(
        COALESCE(SUM(total_90_day_cost), 0)::numeric,
        2
    ) AS total_90_day_cost,

    ROUND(
        (
            COALESCE(SUM(total_90_day_cost), 0)
            * 365.0 / 90
        )::numeric,
        2
    ) AS projected_annualized_savings

FROM flagged_resources;

--5. Which resources have near-zero usage quantity but non-zero cost, over the last 30 days?--
WITH recent_data AS (
    SELECT *
    FROM azure_billing
    WHERE "Usage_Date"::date >= (
        SELECT MAX("Usage_Date")::date - INTERVAL '29 days'
        FROM azure_billing
    )
)

SELECT
    "Resource_Id",
    "Resource_Group",
    "Service_Name",
    "Usage_Quantity",
    "Unit_Of_Measure",
    ROUND("Cost"::numeric, 4) AS cost,
    "Usage_Date"
FROM recent_data
WHERE
    "Usage_Quantity" <= 0.3
    AND "Usage_Quantity" > 0
    AND "Cost" > 0
ORDER BY "Cost" DESC;

--6. What's the total $ we've spent in the last 90 days on resources that show this idle pattern every single day (not just once)?--
WITH date_range AS (
    SELECT
        MAX("Usage_Date")::date AS end_date,
        MAX("Usage_Date")::date - INTERVAL '89 days' AS start_date
    FROM azure_billing
),

daily_resource AS (
    SELECT
        "Resource_Id",
        "Usage_Date"::date AS usage_date,
        SUM("Usage_Quantity") AS daily_usage,
        SUM("Cost") AS daily_cost
    FROM azure_billing
    WHERE "Usage_Date"::date BETWEEN
          (SELECT start_date FROM date_range)
          AND (SELECT end_date FROM date_range)
    GROUP BY
        "Resource_Id",
        "Usage_Date"::date
),

flagged_resources AS (
    SELECT
        "Resource_Id",
        COUNT(*) AS days_present,
        SUM(daily_cost) AS total_90_day_cost
    FROM daily_resource
    GROUP BY "Resource_Id"
    HAVING
        MAX(daily_usage) <= 0.3
        AND SUM(daily_cost) > 0
)

SELECT
    "Resource_Id",
    days_present,
    ROUND(total_90_day_cost::numeric, 2) AS total_90_day_cost
FROM flagged_resources
ORDER BY total_90_day_cost DESC;

--7. Which resource groups have the highest concentration of idle resources?--
WITH date_range AS (
    SELECT
        MAX("Usage_Date")::date AS end_date,
        MAX("Usage_Date")::date - INTERVAL '89 days' AS start_date
    FROM azure_billing
),

resource_summary AS (
    SELECT
        "Resource_Id",
        "Resource_Group",
        MAX("Usage_Quantity") AS max_usage,
        SUM("Cost") AS total_cost
    FROM azure_billing
    WHERE "Usage_Date"::date BETWEEN
          (SELECT start_date FROM date_range)
          AND (SELECT end_date FROM date_range)
    GROUP BY
        "Resource_Id",
        "Resource_Group"
),

resource_group_summary AS (
    SELECT
        "Resource_Group",

        COUNT(*) AS total_resources,

        COUNT(*) FILTER (
            WHERE max_usage <= 0.3
              AND total_cost > 0
        ) AS idle_resources

    FROM resource_summary
    WHERE "Resource_Group" IS NOT NULL
    GROUP BY "Resource_Group"
)

SELECT
    "Resource_Group",
    total_resources,
    idle_resources,

    ROUND(
        (
            idle_resources::numeric
            / NULLIF(total_resources, 0)
        ) * 100,
        2
    ) AS idle_resource_percentage

FROM resource_group_summary
WHERE idle_resources > 0
ORDER BY idle_resource_percentage DESC;

-- 8. What's the projected annualized savings if we deleted/downsized every flagged idle resource?--
WITH date_range AS (
    SELECT
        MAX("Usage_Date")::date AS end_date,
        MAX("Usage_Date")::date - INTERVAL '89 days' AS start_date
    FROM azure_billing
),

resource_summary AS (
    SELECT
        "Resource_Id",
        MAX("Usage_Quantity") AS max_usage,
        SUM("Cost") AS total_90_day_cost
    FROM azure_billing
    WHERE "Usage_Date"::date BETWEEN
          (SELECT start_date FROM date_range)
          AND (SELECT end_date FROM date_range)
    GROUP BY "Resource_Id"
),

flagged_resources AS (
    SELECT
        "Resource_Id",
        total_90_day_cost
    FROM resource_summary
    WHERE
        max_usage <= 0.3
        AND total_90_day_cost > 0
)

SELECT
    COUNT(*) AS flagged_idle_resources,

    ROUND(
        SUM(total_90_day_cost)::numeric,
        2
    ) AS total_90_day_idle_spend,

    ROUND(
        (SUM(total_90_day_cost) * 365.0 / 90)::numeric,
        2
    ) AS projected_annualized_savings

FROM flagged_resources;

--9. What % of total spend has no team tag / no cost center / malformed tags?--
SELECT
    "Tags",
    COUNT(*) AS record_count
FROM azure_billing
GROUP BY "Tags"
ORDER BY record_count DESC
LIMIT 30;

--10. Which resource groups have the worst tag compliance?--
WITH resource_group_tags AS (
    SELECT
        "Resource_Group",

        COUNT(*) AS total_records,

        COUNT(*) FILTER (
            WHERE
                "Tags" IS NOT NULL
                AND REPLACE("Tags", '''', '"')::jsonb ? 'team'
        ) AS compliant_records,

        COUNT(*) FILTER (
            WHERE
                "Tags" IS NULL
                OR NOT (
                    REPLACE("Tags", '''', '"')::jsonb ? 'team'
                )
        ) AS non_compliant_records,

        SUM("Cost") AS total_spend,

        SUM("Cost") FILTER (
            WHERE
                "Tags" IS NULL
                OR NOT (
                    REPLACE("Tags", '''', '"')::jsonb ? 'team'
                )
        ) AS non_compliant_spend

    FROM azure_billing
    WHERE "Resource_Group" IS NOT NULL
    GROUP BY "Resource_Group"
)

SELECT
    "Resource_Group",
    total_records,
    compliant_records,
    non_compliant_records,

    ROUND(
        (
            non_compliant_records::numeric
            / NULLIF(total_records, 0)
        ) * 100,
        2
    ) AS non_compliance_percentage,

    ROUND(total_spend::numeric, 2) AS total_spend,

    ROUND(
        COALESCE(non_compliant_spend, 0)::numeric,
        2
    ) AS non_compliant_spend

FROM resource_group_tags
ORDER BY non_compliance_percentage DESC;

-- 11. If we can attribute tagged spend, what does spend-by-team actually look like?--
WITH team_spend AS (
    SELECT
        REPLACE("Tags", '''', '"')::jsonb ->> 'team' AS team,
        SUM("Cost") AS total_spend
    FROM azure_billing
    WHERE
        "Tags" IS NOT NULL
        AND REPLACE("Tags", '''', '"')::jsonb ? 'team'
    GROUP BY
        REPLACE("Tags", '''', '"')::jsonb ->> 'team'
),

overall_spend AS (
    SELECT
        SUM("Cost") AS total_cost
    FROM azure_billing
)

SELECT
    team_spend.team,
    ROUND(team_spend.total_spend::numeric, 2) AS total_spend,
    ROUND(
        (
            team_spend.total_spend
            / NULLIF(overall_spend.total_cost, 0)
            * 100
        )::numeric,
        2
    ) AS percentage_of_total_spend
FROM team_spend
CROSS JOIN overall_spend
ORDER BY team_spend.total_spend DESC;

-- 12. Is untagged spend concentrated in a few resource groups (easy fix) or spread everywhere (harder fix)?--
WITH resource_group_spend AS (
    SELECT
        "Resource_Group",

        SUM("Cost") FILTER (
            WHERE
                "Tags" IS NULL
                OR NOT (
                    REPLACE("Tags", '''', '"')::jsonb ? 'team'
                )
        ) AS untagged_spend

    FROM azure_billing
    WHERE "Resource_Group" IS NOT NULL
    GROUP BY "Resource_Group"
),

ranked AS (
    SELECT
        "Resource_Group",
        COALESCE(untagged_spend, 0) AS untagged_spend,

        SUM(COALESCE(untagged_spend, 0)) OVER (
            ORDER BY COALESCE(untagged_spend, 0) DESC
        ) AS cumulative_untagged_spend,

        SUM(COALESCE(untagged_spend, 0)) OVER () AS total_untagged_spend

    FROM resource_group_spend
)

SELECT
    "Resource_Group",

    ROUND(untagged_spend::numeric, 2) AS untagged_spend,

    ROUND(
        (
            untagged_spend
            / NULLIF(total_untagged_spend, 0)
            * 100
        )::numeric,
        2
    ) AS percentage_of_untagged_spend,

    ROUND(
        (
            cumulative_untagged_spend
            / NULLIF(total_untagged_spend, 0)
            * 100
        )::numeric,
        2
    ) AS cumulative_percentage

FROM ranked
WHERE untagged_spend > 0
ORDER BY untagged_spend DESC;

--13. Which days had total spend more than X standard deviations above the trailing 30-day average?--
WITH daily_spend AS (
    SELECT
        "Usage_Date"::date AS spend_date,
        SUM("Cost") AS daily_cost
    FROM azure_billing
    WHERE "Usage_Date" IS NOT NULL
    GROUP BY "Usage_Date"::date
),

rolling_stats AS (
    SELECT
        spend_date,
        daily_cost,

        AVG(daily_cost) OVER (
            ORDER BY spend_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS trailing_30d_avg,

        STDDEV_SAMP(daily_cost) OVER (
            ORDER BY spend_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS trailing_30d_stddev

    FROM daily_spend
)

SELECT
    spend_date,
    ROUND(daily_cost::numeric, 2) AS daily_spend,
    ROUND(trailing_30d_avg::numeric, 2) AS trailing_30d_average,
    ROUND(trailing_30d_stddev::numeric, 2) AS trailing_30d_stddev,

    ROUND(
        (
            (daily_cost - trailing_30d_avg)
            / NULLIF(trailing_30d_stddev, 0)
        )::numeric,
        2
    ) AS standard_deviations_above_average

FROM rolling_stats
WHERE
    trailing_30d_avg IS NOT NULL
    AND trailing_30d_stddev IS NOT NULL
    AND daily_cost >
        trailing_30d_avg + (2 * trailing_30d_stddev)

ORDER BY spend_date;

-- 14. How much did the spike(s) we already know about cost us in total?--
WITH daily_spend AS (
    SELECT
        "Usage_Date"::date AS spend_date,
        SUM("Cost") AS daily_cost
    FROM azure_billing
    WHERE "Usage_Date" IS NOT NULL
    GROUP BY "Usage_Date"::date
),

rolling_stats AS (
    SELECT
        spend_date,
        daily_cost,

        AVG(daily_cost) OVER (
            ORDER BY spend_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS trailing_30d_avg,

        STDDEV_SAMP(daily_cost) OVER (
            ORDER BY spend_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS trailing_30d_stddev

    FROM daily_spend
),

spike_days AS (
    SELECT
        spend_date,
        daily_cost
    FROM rolling_stats
    WHERE
        trailing_30d_avg IS NOT NULL
        AND trailing_30d_stddev IS NOT NULL
        AND daily_cost >
            trailing_30d_avg + (2 * trailing_30d_stddev)
)

SELECT
    COUNT(*) AS number_of_spike_days,

    ROUND(
        SUM(daily_cost)::numeric,
        2
    ) AS total_spike_spend

FROM spike_days;

-- 15. What's a reasonable daily/weekly spend threshold to alert on going forward?--
WITH weekly_spend AS (
    SELECT
        DATE_TRUNC('week', "Usage_Date")::date AS week_start,
        SUM("Cost") AS weekly_cost
    FROM azure_billing
    GROUP BY DATE_TRUNC('week', "Usage_Date")::date
),

rolling_stats AS (
    SELECT
        week_start,
        weekly_cost,

        AVG(weekly_cost) OVER (
            ORDER BY week_start
            ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING
        ) AS avg_8w,

        STDDEV_SAMP(weekly_cost) OVER (
            ORDER BY week_start
            ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING
        ) AS stddev_8w

    FROM weekly_spend
)

SELECT
    week_start,
    ROUND(weekly_cost::numeric, 2) AS weekly_spend,
    ROUND(avg_8w::numeric, 2) AS trailing_8_week_average,
    ROUND(stddev_8w::numeric, 2) AS trailing_8_week_stddev,

    ROUND(
        (avg_8w + 2 * stddev_8w)::numeric,
        2
    ) AS weekly_alert_threshold

FROM rolling_stats
WHERE avg_8w IS NOT NULL
ORDER BY week_start DESC
LIMIT 1;

-- 16. What % of spend is OnDemand vs. Reservation vs. SavingsPlan vs. Spot, and how has that mix trended?--
WITH monthly_spend AS (
    SELECT
        DATE_TRUNC('month', "Usage_Date") AS month_start,
        "Pricing_Model",
        SUM("Cost") AS spend
    FROM azure_billing
    WHERE "Pricing_Model" IS NOT NULL
    GROUP BY
        DATE_TRUNC('month', "Usage_Date"),
        "Pricing_Model"
),

monthly_total AS (
    SELECT
        month_start,
        SUM(spend) AS total_monthly_spend
    FROM monthly_spend
    GROUP BY month_start
)

SELECT
    m.month_start,
    m."Pricing_Model",
    ROUND(m.spend::numeric, 2) AS spend,
    ROUND(
        (
            m.spend
            / NULLIF(t.total_monthly_spend, 0)
            * 100
        )::numeric,
        2
    ) AS spend_percentage
FROM monthly_spend m
JOIN monthly_total t
    ON m.month_start = t.month_start
ORDER BY
    m.month_start,
    spend_percentage DESC;

	-- 17. Which resources have consistent, steady daily usage over the full period (good commitment candidates) vs. spiky/intermittent usage (bad candidates)?
	WITH daily_usage AS (
    SELECT
        "Resource_Id",
        "Service_Name",
        "Resource_Group",
        "Unit_Of_Measure",
        "Usage_Date"::date AS usage_date,
        SUM("Usage_Quantity") AS daily_usage
    FROM azure_billing
    WHERE
        "Usage_Date" IS NOT NULL
        AND "Resource_Id" IS NOT NULL
    GROUP BY
        "Resource_Id",
        "Service_Name",
        "Resource_Group",
        "Unit_Of_Measure",
        "Usage_Date"::date
),

resource_stats AS (
    SELECT
        "Resource_Id",
        MAX("Service_Name") AS service_name,
        MAX("Resource_Group") AS resource_group,
        MAX("Unit_Of_Measure") AS unit_of_measure,

        COUNT(*) AS active_days,

        AVG(daily_usage) AS avg_daily_usage,

        STDDEV_SAMP(daily_usage) AS stddev_daily_usage,

        MIN(daily_usage) AS min_daily_usage,

        MAX(daily_usage) AS max_daily_usage

    FROM daily_usage
    GROUP BY "Resource_Id"
)

SELECT
    "Resource_Id",
    service_name,
    resource_group,
    unit_of_measure,
    active_days,

    ROUND(avg_daily_usage::numeric, 4) AS avg_daily_usage,

    ROUND(stddev_daily_usage::numeric, 4) AS stddev_daily_usage,

    ROUND(
        (
            stddev_daily_usage
            / NULLIF(avg_daily_usage, 0)
        )::numeric,
        4
    ) AS coefficient_of_variation,

    ROUND(min_daily_usage::numeric, 4) AS min_daily_usage,
    ROUND(max_daily_usage::numeric, 4) AS max_daily_usage,

    CASE
        WHEN avg_daily_usage = 0 THEN 'No Usage'

        WHEN
            stddev_daily_usage
            / NULLIF(avg_daily_usage, 0) <= 0.25
            THEN 'Steady - Good Commitment Candidate'

        WHEN
            stddev_daily_usage
            / NULLIF(avg_daily_usage, 0) <= 0.75
            THEN 'Moderately Variable'

        ELSE 'Spiky - Poor Commitment Candidate'
    END AS usage_pattern

FROM resource_stats
WHERE active_days >= 30
ORDER BY coefficient_of_variation ASC;

-- 18. For steady-state OnDemand resources, what would switching to a 1-year commitment save at a typical ~30-40% discount rate?
WITH environment_spend AS (
    SELECT
        COALESCE(
            LOWER(
                REPLACE("Tags", '''', '"')::jsonb ->> 'environment'
            ),
            'untagged'
        ) AS environment,
        SUM("Cost") AS total_spend
    FROM azure_billing
    GROUP BY
        COALESCE(
            LOWER(
                REPLACE("Tags", '''', '"')::jsonb ->> 'environment'
            ),
            'untagged'
        )
)

SELECT
    environment,
    ROUND(total_spend::numeric, 2) AS total_spend,
    ROUND(
        (
            total_spend
            / NULLIF(SUM(total_spend) OVER (), 0)
            * 100
        )::numeric,
        2
    ) AS spend_percentage
FROM environment_spend
ORDER BY total_spend DESC;

-- 18. Within non-prod environments, is there any usage-quantity signal suggesting these resources run uniformly across all 7 days (i.e., no one's turning them off)?
WITH nonprod_daily_usage AS (
    SELECT
        "Resource_Id",
        "Resource_Group",
        "Service_Name",
        "Unit_Of_Measure",
        "Usage_Date"::date AS usage_date,
        SUM("Usage_Quantity") AS daily_usage
    FROM azure_billing
    WHERE
        "Tags" IS NOT NULL
        AND LOWER(
            REPLACE("Tags", '''', '"')::jsonb ->> 'environment'
        ) IN ('dev', 'staging', 'sandbox')
        AND "Resource_Id" IS NOT NULL
    GROUP BY
        "Resource_Id",
        "Resource_Group",
        "Service_Name",
        "Unit_Of_Measure",
        "Usage_Date"::date
),

resource_week_pattern AS (
    SELECT
        "Resource_Id",
        MAX("Resource_Group") AS resource_group,
        MAX("Service_Name") AS service_name,
        MAX("Unit_Of_Measure") AS unit_of_measure,

        COUNT(DISTINCT EXTRACT(ISODOW FROM usage_date)) AS days_of_week_used,

        COUNT(DISTINCT usage_date) AS total_active_days,

        AVG(daily_usage) AS avg_daily_usage,

        MIN(daily_usage) AS min_daily_usage,

        MAX(daily_usage) AS max_daily_usage

    FROM nonprod_daily_usage
    GROUP BY "Resource_Id"
)

SELECT
    "Resource_Id",
    resource_group,
    service_name,
    unit_of_measure,

    days_of_week_used,
    total_active_days,

    ROUND(avg_daily_usage::numeric, 4) AS avg_daily_usage,
    ROUND(min_daily_usage::numeric, 4) AS min_daily_usage,
    ROUND(max_daily_usage::numeric, 4) AS max_daily_usage,

    CASE
        WHEN days_of_week_used = 7
            THEN 'Runs across all 7 days'
        WHEN days_of_week_used >= 5
            THEN 'Runs most days'
        ELSE
            'Intermittent'
    END AS usage_pattern

FROM resource_week_pattern
WHERE days_of_week_used = 7
ORDER BY avg_daily_usage DESC;

-- 19. If non-prod resources were shut down nights (e.g., 12 of 24 hrs) and weekends, what's the estimated savings?
WITH nonprod_daily AS (
    SELECT
        "Resource_Id",
        "Usage_Date"::date AS usage_date,
        SUM("Cost") AS daily_cost
    FROM azure_billing
    WHERE
        "Tags" IS NOT NULL
        AND LOWER(
            REPLACE("Tags", '''', '"')::jsonb ->> 'environment'
        ) IN ('dev', 'staging', 'sandbox')
        AND "Resource_Id" IS NOT NULL
    GROUP BY
        "Resource_Id",
        "Usage_Date"::date
),

always_on_resources AS (
    SELECT
        "Resource_Id"
    FROM nonprod_daily
    GROUP BY "Resource_Id"
    HAVING COUNT(DISTINCT EXTRACT(ISODOW FROM usage_date)) = 7
),

eligible_spend AS (
    SELECT
        SUM(d.daily_cost) AS total_spend
    FROM nonprod_daily d
    JOIN always_on_resources a
        ON d."Resource_Id" = a."Resource_Id"
)

SELECT
    ROUND(COALESCE(total_spend, 0)::numeric, 2)
        AS always_on_nonprod_spend,

    ROUND(
        (COALESCE(total_spend, 0) * 108.0 / 168)::numeric,
        2
    ) AS estimated_savings,

    ROUND(
        (COALESCE(total_spend, 0) * 60.0 / 168)::numeric,
        2
    ) AS remaining_spend

FROM eligible_spend;