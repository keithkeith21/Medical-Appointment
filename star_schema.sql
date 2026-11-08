-- =====================================================================
-- star_schema.sql
-- Builds the star schema for the Medical Appointment No-Shows project.
--
-- Source : staging_appointments  (loaded by python/02_load_to_mysql.py)
-- Run    : top to bottom. Safe to re-run: tables are dropped first,
--          in reverse dependency order.
-- Result : appointments_clean, dim_date, dim_patient, fact_appointments
-- =====================================================================

DROP TABLE IF EXISTS fact_appointments;
DROP TABLE IF EXISTS dim_patient;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS appointments_clean;


-- ---------------------------------------------------------------------
-- 1. APPOINTMENTS_CLEAN
-- Keeps only rows whose PatientId is a whole number.
-- NOTE: this removes rows whose PatientId has a decimal part.
-- Check how many rows that is (expected: 5 for this dataset):
--     SELECT COUNT(*) FROM staging_appointments
--     WHERE PatientId <> FLOOR(PatientId);
-- ---------------------------------------------------------------------
CREATE TABLE appointments_clean AS
SELECT *
FROM staging_appointments
WHERE PatientId = FLOOR(PatientId);


-- ---------------------------------------------------------------------
-- 2. DIM_DATE
-- One row per calendar day from 2015-11-01 to 2016-06-30,
-- generated with a recursive CTE. Created before the fact table
-- because the fact table has foreign keys pointing to it.
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key             INT PRIMARY KEY,
    full_date            DATE NOT NULL UNIQUE,
    day_number           TINYINT NOT NULL,
    month_number         TINYINT NOT NULL,
    month_name           VARCHAR(15) NOT NULL,
    quarter_number       TINYINT NOT NULL,
    year_number          SMALLINT NOT NULL,
    day_of_week_number   TINYINT NOT NULL,
    day_of_week_name     VARCHAR(15) NOT NULL,
    is_weekend           TINYINT NOT NULL
);

INSERT INTO dim_date (
    date_key,
    full_date,
    day_number,
    month_number,
    month_name,
    quarter_number,
    year_number,
    day_of_week_number,
    day_of_week_name,
    is_weekend
)
WITH RECURSIVE calendar AS (
    SELECT DATE('2015-11-01') AS calendar_date

    UNION ALL

    SELECT DATE_ADD(calendar_date, INTERVAL 1 DAY)
    FROM calendar
    WHERE calendar_date < '2016-06-30'
)
SELECT
    CAST(DATE_FORMAT(calendar_date, '%Y%m%d') AS UNSIGNED),
    calendar_date,
    DAY(calendar_date),
    MONTH(calendar_date),
    MONTHNAME(calendar_date),
    QUARTER(calendar_date),
    YEAR(calendar_date),
    DAYOFWEEK(calendar_date),
    DAYNAME(calendar_date),
    CASE
        WHEN DAYOFWEEK(calendar_date) IN (1, 7) THEN 1
        ELSE 0
    END
FROM calendar;


-- ---------------------------------------------------------------------
-- 3. DIM_PATIENT
-- One row per unique PatientId. ROW_NUMBER() ... PARTITION BY PatientId
-- keeps the patient's first appointment (lowest AppointmentID), so the
-- attributes below are a snapshot from that first appointment.
-- patient_sk is a surrogate key generated with ROW_NUMBER().
-- ---------------------------------------------------------------------
CREATE TABLE dim_patient (
    patient_sk    BIGINT UNSIGNED PRIMARY KEY,
    patient_id    BIGINT NOT NULL,
    gender        CHAR(1),
    scholarship   TINYINT,
    hipertension  TINYINT,
    diabetes      TINYINT,
    alcoholism    TINYINT,
    handcap       TINYINT
);

INSERT INTO dim_patient (
    patient_sk,
    patient_id,
    gender,
    scholarship,
    hipertension,
    diabetes,
    alcoholism,
    handcap
)
SELECT
    ROW_NUMBER() OVER (ORDER BY PatientId) AS patient_sk,
    PatientId,
    Gender,
    Scholarship,
    Hipertension,
    Diabetes,
    Alcoholism,
    Handcap
FROM (
    SELECT
        CAST(PatientId AS DECIMAL(20,0)) AS PatientId,
        Gender,
        Scholarship,
        Hipertension,
        Diabetes,
        Alcoholism,
        Handcap,
        ROW_NUMBER() OVER (
            PARTITION BY PatientId
            ORDER BY AppointmentID
        ) AS rn
    FROM staging_appointments
    -- NOTE: reads from staging_appointments, so it also includes the
    -- patients whose rows were excluded from appointments_clean.
    -- To keep the dimension consistent with the fact table, change
    -- this line to: FROM appointments_clean
) p
WHERE rn = 1;


-- ---------------------------------------------------------------------
-- 4. FACT_APPOINTMENTS
-- One row per appointment. Two date keys point to the same dim_date
-- (role-playing dimension): scheduled date and appointment date.
-- ---------------------------------------------------------------------
CREATE TABLE fact_appointments (
    appointment_id        BIGINT NOT NULL PRIMARY KEY,
    patient_sk            BIGINT UNSIGNED NOT NULL,
    scheduled_day         DATETIME,
    appointment_day       DATETIME,
    age                   INT,
    neighbourhood         VARCHAR(100),
    sms_received          TINYINT,
    no_show               TINYINT,
    scheduled_date_key    INT,
    appointment_date_key  INT,

    CONSTRAINT fk_fact_patient
        FOREIGN KEY (patient_sk)
        REFERENCES dim_patient(patient_sk),

    CONSTRAINT fk_fact_scheduled_date
        FOREIGN KEY (scheduled_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT fk_fact_appointment_date
        FOREIGN KEY (appointment_date_key)
        REFERENCES dim_date(date_key)
);

INSERT INTO fact_appointments (
    appointment_id,
    patient_sk,
    scheduled_day,
    appointment_day,
    age,
    neighbourhood,
    sms_received,
    no_show
)
SELECT
    a.AppointmentID,
    p.patient_sk,
    STR_TO_DATE(
        REPLACE(LEFT(a.ScheduledDay, 19), 'T', ' '),
        '%Y-%m-%d %H:%i:%s'
    ),
    STR_TO_DATE(
        REPLACE(LEFT(a.AppointmentDay, 19), 'T', ' '),
        '%Y-%m-%d %H:%i:%s'
    ),
    a.Age,
    a.Neighbourhood,
    a.SMS_received,
    CASE
        WHEN a.`No-show` = 'No'  THEN 0
        WHEN a.`No-show` = 'Yes' THEN 1
        ELSE NULL
    END
FROM appointments_clean AS a
JOIN dim_patient AS p
    ON a.PatientId = p.patient_id;

-- Populate the date keys (yyyymmdd) that point to dim_date
UPDATE fact_appointments
SET
    scheduled_date_key =
        CAST(DATE_FORMAT(scheduled_day, '%Y%m%d') AS UNSIGNED),
    appointment_date_key =
        CAST(DATE_FORMAT(appointment_day, '%Y%m%d') AS UNSIGNED)
WHERE appointment_id > 0;


-- ---------------------------------------------------------------------
-- 5. SANITY CHECKS
-- fact_rows should equal clean_rows. Any gap vs staging_rows is the
-- set of rows excluded in step 1.
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM staging_appointments) AS staging_rows,
    (SELECT COUNT(*) FROM appointments_clean)   AS clean_rows,
    (SELECT COUNT(*) FROM fact_appointments)    AS fact_rows,
    (SELECT COUNT(*) FROM dim_patient)          AS patient_rows,
    (SELECT COUNT(*) FROM fact_appointments
      WHERE scheduled_date_key IS NULL
         OR appointment_date_key IS NULL)       AS rows_missing_date_key;
