--1. Overdue / At-Risk Milestones 
SELECT milestone_id, project_id, milestone_name, planned_date, status
FROM milestone
WHERE status IN ('Delayed', 'At Risk')
ORDER BY planned_date;

--2. Top 5 Highest-Severity Open Risks 
SELECT risk_id, project_id, description, "likelihood Risk", "impact on Project", risk_score
FROM risklog
WHERE risk_state = 'Open'
ORDER BY risk_score DESC
LIMIT 5;

--3.Open Risk Count per Project
select p.project_id, p.project_name, COUNT(r.risk_id) AS open_risk_count
FROM projects p left  JOIN risklog r
ON p.project_id = r.project_id and  r.risk_state = 'Open'
GROUP BY p.project_id, p.project_name
ORDER by open_risk_count DESC;
 
--4. Milestone Completion Rate by Project
select p.project_id, p.project_name,
COUNT(m.milestone_id) AS total_milestones,
SUM(CASE WHEN m.status = 'Completed' THEN 1 ELSE 0 END) AS completed_milestones,
ROUND(
        100.0 * SUM(CASE WHEN m.status = 'Completed' THEN 1 ELSE 0 END) / COUNT(m.milestone_id),
        1) AS completion_pct
FROM projects p
JOIN milestone m ON p.project_id = m.project_id
GROUP BY p.project_id, p.project_name
ORDER BY completion_pct ASC;
 

--5.Resource Over-Allocation Flagging
SELECT
    name,
    SUM(allocation_pct) AS total_allocation
FROM resources
GROUP BY name
HAVING SUM(allocation_pct) > 100
ORDER BY total_allocation DESC;
 

--6. Top 3 Riskiest Projects per Team
WITH project_risk AS (
    select p.project_id, p.project_name, p.team,
SUM(r.risk_score) AS total_risk_score
    FROM projects p 
    JOIN risklog r ON p.project_id = r.project_id
    WHERE r.risk_state = 'Open'
    GROUP BY p.project_id, p.project_name, p.team
),
ranked AS (
    SELECT*,
        RANK() OVER (PARTITION BY team ORDER BY total_risk_score DESC) AS risk_rank
    FROM project_risk)

SELECT project_id, project_name, team, total_risk_score, risk_rank
FROM ranked
WHERE risk_rank <= 3
ORDER BY team, risk_rank;




--7. Weekly Budget Burn Trend (Running Change)
select project_id, week_ending, actual_spend_to_date, actual_spend_to_date - LAG(actual_spend_to_date) OVER (

        PARTITION BY project_id ORDER BY week_ending

    ) AS week_over_week_change,

    ROUND(

        AVG(budget_variance_pct) OVER (

            PARTITION BY project_id ORDER BY week_ending

            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW

        ), 2

    ) AS rolling_3wk_avg_variance

FROM weeklystatus

WHERE project_id = 'P001'

ORDER BY week_ending;


--8.Correlated Subquery — Projects Spending Above Their Team's Average
SELECT
    p1.project_id,
    p1.project_name,
    p1.team,
    p1.actual_spend
FROM projects p1
WHERE p1.actual_spend > (
    SELECT AVG(p2.actual_spend)
    FROM projects p2
    WHERE p2.team = p1.team          -- correlation: recalculated per outer row's team
)
ORDER BY p1.team, p1.actual_spend DESC;


--9. Automated Escalation Rule Engine
SELECT
    p.project_id,
    p.project_name,
    p.status,
    p.budget_variance_pct,
    COALESCE(risk.high_open_risks, 0) AS high_open_risks,
    CASE
        WHEN p.status = 'Red' AND COALESCE(risk.high_open_risks, 0) > 0
            THEN 'Escalate to Executive Sponsor'
        WHEN p.status = 'Red'
            THEN 'Escalate to PMO Director'
        WHEN p.status = 'Amber' AND p.budget_variance_pct > 5
            THEN 'Flag for Steering Committee'
        WHEN p.status = 'Amber'
            THEN 'Monitor'
        ELSE 'No Action'
    END AS escalation_action
FROM projects p
LEFT JOIN (
    SELECT project_id, COUNT(*) AS high_open_risks
    FROM risklog
    WHERE risk_state = 'Open' AND "impact on Project" = 'High'
    GROUP BY project_id
) risk ON p.project_id = risk.project_id
ORDER BY
    CASE p.status WHEN 'Red' THEN 1 WHEN 'Amber' THEN 2 ELSE 3 END;


--10. Portfolio Forecast — Projected Overrun at Completion
WITH latest_snapshot AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY week_ending DESC) AS rn
    FROM weeklystatus
)
SELECT
    p.project_id,
    p.project_name,
    p.budget,
    ls.actual_spend_to_date,
    ls.budget_variance_pct AS latest_variance_pct,
    ROUND((p.budget * (1 + ls.budget_variance_pct / 100.0))::numeric, 0) AS projected_spend_at_completion,
    ROUND((p.budget * (ls.budget_variance_pct / 100.0))::numeric, 0) AS projected_overrun_amount
FROM projects p
JOIN latest_snapshot ls ON p.project_id = ls.project_id AND ls.rn = 1
ORDER BY projected_overrun_amount DESC;


















