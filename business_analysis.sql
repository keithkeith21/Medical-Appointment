-- =====================================================================
-- business_analysis.sql
-- Medical Appointment No-Shows: SQL business analysis
-- Run after the star schema is built (fact_appointments, dim_patient, dim_date).
-- =====================================================================


-- ---------------------------------------------------------------------
-- Business Question 1
-- Which patients have the highest number of missed appointments?
-- Techniques: CTE, COUNT, GROUP BY, RANK() window function
-- ---------------------------------------------------------------------
WITH patient_missed AS (
    SELECT
        patient_sk,
        COUNT(*) AS missed_appointments
    FROM fact_appointments
    WHERE no_show = 1
    GROUP BY patient_sk
),
patient_ranking AS (
    SELECT
        patient_sk,
        missed_appointments,
        RANK() OVER (
            ORDER BY missed_appointments DESC
        ) AS missed_rank
    FROM patient_missed
)
SELECT
    patient_sk,
    missed_appointments,
    missed_rank
FROM patient_ranking
ORDER BY missed_rank
LIMIT 10;


-- ---------------------------------------------------------------------
-- Business Question 2
-- How did a patient's previous appointment attendance compare
-- with their next appointment?
-- Technique: LAG() with PARTITION BY
-- ---------------------------------------------------------------------

-- 2a. Detail level
WITH patient_history AS (
    SELECT
        patient_sk,
        appointment_id,
        appointment_day,
        no_show,
        LAG(no_show) OVER (
            PARTITION BY patient_sk
            ORDER BY appointment_day, appointment_id
        ) AS previous_no_show
    FROM fact_appointments
)
SELECT
    patient_sk,
    appointment_id,
    appointment_day,
    CASE
        WHEN previous_no_show = 0 THEN 'Attended'
        WHEN previous_no_show = 1 THEN 'No Show'
        ELSE 'First Appointment'
    END AS previous_attendance,
    CASE
        WHEN no_show = 0 THEN 'Attended'
        WHEN no_show = 1 THEN 'No Show'
    END AS current_attendance
FROM patient_history
WHERE previous_no_show IS NOT NULL
ORDER BY patient_sk, appointment_day, appointment_id;


-- 2b. Aggregated transitions
WITH patient_history AS (
    SELECT
        patient_sk,
        no_show,
        LAG(no_show) OVER (
            PARTITION BY patient_sk
            ORDER BY appointment_day, appointment_id
        ) AS previous_no_show
    FROM fact_appointments
)
SELECT
    CASE
        WHEN previous_no_show = 0 AND no_show = 0
            THEN 'Attended -> Attended'
        WHEN previous_no_show = 0 AND no_show = 1
            THEN 'Attended -> No Show'
        WHEN previous_no_show = 1 AND no_show = 0
            THEN 'No Show -> Attended'
        WHEN previous_no_show = 1 AND no_show = 1
            THEN 'No Show -> No Show'
    END AS attendance_transition,
    COUNT(*) AS transition_count
FROM patient_history
WHERE previous_no_show IS NOT NULL
GROUP BY attendance_transition
ORDER BY transition_count DESC;


-- ---------------------------------------------------------------------
-- Business Question 3
-- How did the monthly no-show rate change compared with the previous month?
-- Technique: CTEs + LAG() over months
-- ---------------------------------------------------------------------
WITH monthly_summary AS (
    SELECT
        DATE_FORMAT(appointment_day, '%Y-%m') AS appointment_month,
        COUNT(*) AS total_appointments,
        SUM(
            CASE WHEN no_show = 1 THEN 1 ELSE 0 END
        ) AS missed_appointments,
        ROUND(AVG(no_show) * 100, 2) AS no_show_rate
    FROM fact_appointments
    GROUP BY DATE_FORMAT(appointment_day, '%Y-%m')
),
monthly_comparison AS (
    SELECT
        appointment_month,
        total_appointments,
        missed_appointments,
        no_show_rate,
        LAG(no_show_rate) OVER (
            ORDER BY appointment_month
        ) AS previous_month_rate
    FROM monthly_summary
)
SELECT
    appointment_month,
    total_appointments,
    missed_appointments,
    no_show_rate,
    previous_month_rate,
    ROUND(
        no_show_rate - previous_month_rate,
        2
    ) AS rate_difference
FROM monthly_comparison
ORDER BY appointment_month;


-- ---------------------------------------------------------------------
-- Sanity check: the fact table should have the same number of rows
-- as the staging table (110,527 for this dataset).
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM staging_appointments) AS staging_rows,
    (SELECT COUNT(*) FROM fact_appointments)    AS fact_rows;
