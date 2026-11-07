# Medical Appointment No-Shows: Data Cleaning, Warehousing, and Analysis

## Project Overview

This project analyzes medical appointment records to understand patient attendance behavior and identify patterns associated with missed appointments (*no-shows*).

The project follows an end-to-end data analytics workflow, starting with data exploration and cleaning using Python and Pandas, followed by data warehousing and SQL analysis in MySQL, and finally data visualization using Power BI.

The goal is to transform raw appointment records into structured data and meaningful insights that can help explain appointment attendance patterns.

## Project Objectives

- Explore and assess the quality of the raw medical appointment dataset.
- Clean and prepare the data using Python and Pandas.
- Load the cleaned dataset into MySQL.
- Design a dimensional data warehouse using a Star Schema.
- Analyze patient attendance behavior using SQL.
- Build an interactive Power BI dashboard to present key findings.

## Tools and Technologies

| Tool | Purpose |
|---|---|
| Python | Data exploration and cleaning |
| Pandas | Data manipulation and preparation |
| NumPy | Handling invalid values |
| SQLAlchemy | Connecting Python to MySQL |
| PyMySQL | MySQL database connection |
| MySQL | Data warehousing and SQL analysis |
| Power BI | Data visualization and dashboard development |

## Project Workflow

1. Data Collection
2. Data Exploration and Cleaning using Python and Pandas
3. Data Loading into MySQL
4. Data Warehouse Design using Star Schema
5. SQL Business Analysis
6. Power BI Dashboard Development

---

## 1. Data Collection

The project uses the **Medical Appointment No Shows** dataset, originally distributed through Kaggle.

**Dataset file:** `KaggleV2-May-2016.csv`

The dataset contains medical appointment records and patient-related information, including:

- Patient ID
- Appointment ID
- Gender
- Age
- Scheduled Day
- Appointment Day
- Neighbourhood
- Scholarship
- Hypertension
- Diabetes
- Alcoholism
- Handicap
- SMS Received
- No-show status

The original dataset was loaded into Python for initial exploration and data quality assessment.

---

## 2. Data Exploration and Cleaning (Python & Pandas)

The initial dataset was loaded using Pandas.

```python
import pandas as pd
import numpy as np

df = pd.read_csv("KaggleV2-May-2016.csv")
```

### 2.1 Initial Data Exploration

The following methods were used to understand the dataset's structure and contents:

```python
df.shape
df.head(20)
df.info()
df.tail(10)
df.describe()
```

Categorical and binary columns were also examined using `value_counts()` to understand their distributions.

### 2.2 Data Quality Investigation

Several potential data quality issues were investigated before making changes.

**Age validation**

- `Age = -1` was identified as an invalid age value and replaced with `NaN`.
- `Age = 0` was investigated but retained because the value alone was not enough to confirm that the records were invalid.
- Ages of 102 and 115 were also investigated and retained rather than being removed simply because they were unusually high.

```python
df.loc[df["Age"] == -1, "Age"] = np.nan
```

**Date columns**

The scheduled and appointment date columns were converted into datetime data types.

```python
df["ScheduledDay"] = pd.to_datetime(df["ScheduledDay"])
df["AppointmentDay"] = pd.to_datetime(df["AppointmentDay"])
```

Records where the scheduled date occurred after the appointment date were investigated as potential date anomalies.

**Other data checks**

Additional checks were performed on:

- Handicap values
- Neighbourhood consistency
- Patient ID and Appointment ID
- Missing values
- Duplicate Appointment IDs
- Appointment frequency per patient
- No-show distribution
- SMS notification and attendance distribution

These checks helped identify potential issues without automatically deleting records that required further investigation.

### 2.3 Exploratory Data Analysis

Initial analysis was performed to understand appointment attendance and SMS notification patterns.

**No-show distribution**

```python
df["No-show"].value_counts()
df["No-show"].value_counts(normalize=True) * 100
```

**SMS notification versus attendance**

```python
pd.crosstab(
    df["SMS_received"],
    df["No-show"],
    normalize="index"
) * 100
```

### 2.4 Export Cleaned Dataset

After the cleaning and investigation process, the prepared dataset was exported into a new CSV file.

```python
df.to_csv("cleaned_medical_appointments.csv", index=False)
```

The original dataset was preserved separately.

**Output file:** `cleaned_medical_appointments.csv`

---

## 3. Loading Data into MySQL

The cleaned CSV file was loaded into MySQL using Pandas, SQLAlchemy, and PyMySQL.

```python
import pandas as pd
from sqlalchemy import create_engine

df = pd.read_csv("cleaned_medical_appointments.csv")

username = "root"
password = ""
host = "localhost"
port = "3306"
database = "medical_appointment"

engine = create_engine(
    f"mysql+pymysql://{username}:{password}@{host}:{port}/{database}"
)

df.to_sql(
    name="staging_appointments",
    con=engine,
    if_exists="replace",
    index=False
)
```

The cleaned CSV was loaded into a staging table named `staging_appointments`.

The staging table served as the source for the subsequent data warehouse preparation.

*Note: Database credentials are intentionally excluded from this project documentation.*

---

## 4. Data Warehouse Design (MySQL)

A Star Schema was designed to organize the appointment data for analytical queries and reporting.

### 4.1 Star Schema Structure

The data warehouse consists of the following tables:

| Table | Description |
|---|---|
| `fact_appointments` | Contains appointment-level records and measurable attendance information. |
| `dim_patient` | Contains unique patient records and patient-related attributes. |
| `dim_date` | Contains calendar attributes used for date-based analysis. |

### 4.2 Dimension Tables

**dim_patient**

The patient dimension stores one record per unique patient.

Patient records were deduplicated using `ROW_NUMBER()` with `PARTITION BY PatientId`. A surrogate key named `patient_sk` was generated to identify each patient record in the warehouse.

```sql
CREATE TABLE dim_patient (
    patient_sk BIGINT UNSIGNED PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    gender CHAR(1),
    scholarship TINYINT,
    hipertension TINYINT,
    diabetes TINYINT,
    alcoholism TINYINT,
    handcap TINYINT
);
```

**dim_date**

The date dimension provides calendar attributes for time-based analysis.

It includes:

- Date key
- Full date
- Day number
- Month number
- Month name
- Quarter
- Year
- Day of week number
- Day of week name
- Weekend indicator

A recursive CTE was used to generate the calendar dates from November 1, 2015, to June 30, 2016.

### 4.3 Fact Table

**fact_appointments**

The fact table stores appointment-level records. Each row represents an appointment.

Important columns include:

- `appointment_id`
- `patient_sk`
- `scheduled_day`
- `appointment_day`
- `age`
- `neighbourhood`
- `sms_received`
- `no_show`
- `scheduled_date_key`
- `appointment_date_key`

The fact table connects to the patient dimension and uses two date keys referencing the same date dimension.

This is an example of a **role-playing date dimension**, where one date dimension serves two different purposes:

- Scheduled date
- Appointment date

### 4.4 No-Show Transformation

The original `No-show` column contains text values. These were transformed into numeric values during the MySQL fact table loading process.

```sql
CASE
    WHEN a.`No-show` = 'No' THEN 0
    WHEN a.`No-show` = 'Yes' THEN 1
    ELSE NULL
END
```

| Original Value | Transformed Value | Meaning |
|---|---:|---|
| No | 0 | Attended |
| Yes | 1 | No-show |

The date keys were populated using the date values from the fact table.

```sql
UPDATE fact_appointments
SET
    scheduled_date_key =
        CAST(DATE_FORMAT(scheduled_day, '%Y%m%d') AS UNSIGNED),
    appointment_date_key =
        CAST(DATE_FORMAT(appointment_day, '%Y%m%d') AS UNSIGNED)
WHERE appointment_id > 0;
```

The resulting fact table uses these keys to establish relationships with `dim_date`.

### 4.5 Data Warehouse Relationship

<!-- INSERT STAR SCHEMA SCREENSHOT HERE -->
![Medical Appointment Star Schema](images/star-schema.png)

---

## 5. SQL Business Analysis

SQL was used to answer three main business questions using CTEs, aggregate functions, and window functions.

### Business Question 1: Which patients have the highest number of missed appointments?

The analysis identifies the patient records with the highest number of missed appointments.

Techniques used:

- Common Table Expressions (CTEs)
- `COUNT()`
- `GROUP BY`
- `RANK()`
- Window Functions

```sql
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
```

**Key Finding**

The highest-ranked patient record had 18 missed appointments, followed by another record with 16 missed appointments.

Four records shared rank 7, each with 11 missed appointments.

*Note: The patient key is a warehouse-generated identifier. The number of missed appointments does not necessarily represent a patient's likelihood of missing an appointment, since patients with more appointments have more opportunities to miss one.*

### Business Question 2: How did a patient's previous appointment attendance compare with their next appointment?

This analysis examines appointment-to-appointment attendance transitions for each patient.

The `LAG()` window function retrieves the previous appointment's attendance status.

**Detail-level analysis**

```sql
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
```

**Aggregated transition analysis**

```sql
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
```

**Key Findings**

| Attendance Transition | Count |
|---|---:|
| Attended → Attended | 31,490 |
| Attended → No Show | 6,700 |
| No Show → Attended | 6,585 |
| No Show → No Show | 3,453 |

The analysis identified 48,228 consecutive appointment transitions.

The most frequent pattern was **Attended → Attended**, with 31,490 transitions. Meanwhile, 3,453 transitions showed consecutive missed appointments, while 6,585 showed patients attending after a previous missed appointment.

These counts represent appointment transitions, not unique patients.

### Business Question 3: How did the monthly no-show rate change compared with the previous month?

This analysis calculates the monthly no-show rate and compares it with the previous month using `LAG()`.

```sql
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
```

**Key Findings**

| Month | Total Appointments | No-Shows | No-Show Rate | Change from Previous Month |
|---|---:|---:|---:|---:|
| April 2016 | 3,235 | 633 | 19.57% | — |
| May 2016 | 80,838 | 16,804 | 20.79% | +1.22 pp |
| June 2016 | 26,449 | 4,882 | 18.46% | -2.33 pp |

The no-show rate increased by 1.22 percentage points in May compared with April, then decreased by 2.33 percentage points in June.

May recorded the highest no-show rate at 20.79%, while June recorded the lowest at 18.46%.

*Note: The monthly appointment volumes differ considerably. The results describe the records available in the dataset and should be interpreted with the dataset's date coverage in mind.*

---

## 6. Power BI Dashboard

The final data warehouse was connected to Power BI to create a dashboard presenting appointment attendance patterns and no-show counts.

### Dashboard Overview

<!-- INSERT FULL DASHBOARD SCREENSHOT HERE -->
![Medical Appointment Dashboard](images/dashboard.png)

### Dashboard Visualizations

The dashboard includes the following visuals:

| Visualization | Description |
|---|---|
| Total Appointments | Displays the total number of appointment records. |
| Appointment Attendance Distribution | Shows the distribution of attended and missed appointments. |
| Monthly No-Show Trend | Displays the number of missed appointments across months. |
| No-Show Appointments by Age Group | Shows missed appointment counts across age groups. |
| Top 10 Neighbourhoods by No-Show Count | Identifies neighbourhoods with the highest number of missed appointments. |
| Attendance by SMS Notification | Compares attendance counts based on SMS notification status. |

### Age Group Classification

Age groups were created in Power Query using conditional column logic.

| Age Condition | Age Group |
|---|---|
| Age below 0 | Unknown |
| Below 18 | Under 18 |
| 18–30 | 18–30 |
| 31–45 | 31–45 |
| 46–60 | 46–60 |
| Above 60 | Above 60 |

### Additional Dashboard Screenshots

<!-- INSERT ATTENDANCE DISTRIBUTION SCREENSHOT HERE -->
![Attendance Distribution](images/attendance-distribution.png)

<!-- INSERT MONTHLY NO-SHOW TREND SCREENSHOT HERE -->
![Monthly No-Show Trend](images/monthly-no-show-trend.png)

<!-- INSERT AGE GROUP ANALYSIS SCREENSHOT HERE -->
![No-Show by Age Group](images/no-show-by-age-group.png)

<!-- INSERT NEIGHBOURHOOD ANALYSIS SCREENSHOT HERE -->
![Top Neighbourhoods by No-Show Count](images/top-neighbourhoods.png)

<!-- INSERT SMS ANALYSIS SCREENSHOT HERE -->
![Attendance by SMS Notification](images/sms-attendance.png)

---

## 7. Key Findings and Observations

Based on the SQL analysis and Power BI visualizations:

- Some patient records had repeated missed appointments, with the highest-ranked record showing 18 missed appointments.
- Attended → Attended was the most frequent consecutive appointment transition.
- A total of 3,453 transitions showed consecutive missed appointments.
- The monthly no-show rate increased in May 2016 and declined in June 2016.
- The dashboard provides additional breakdowns of missed appointments by age group, neighbourhood, and SMS notification status.

These findings describe patterns in the available appointment records. They do not establish that any particular factor causes a patient to miss an appointment.

## 8. Project Limitations

- The analysis is based on the available historical dataset and does not represent current medical appointment behavior.
- Some unusual values were investigated but retained when there was insufficient evidence to classify them as invalid.
- Appointment counts do not automatically represent no-show rates or individual patient risk.
- SMS attendance comparisons are descriptive and do not establish a causal relationship between receiving an SMS and attending an appointment.
- The monthly comparison should be interpreted alongside differences in appointment volume and dataset coverage.

## 9. Skills Demonstrated

- Data exploration and quality assessment
- Data cleaning using Python and Pandas
- Handling invalid and unusual values
- Data type conversion and missing-value investigation
- Loading data into MySQL using SQLAlchemy
- Relational database design
- Star Schema and dimensional modeling
- Surrogate keys and foreign key relationships
- SQL CTEs and recursive CTEs
- Window functions: `ROW_NUMBER()`, `RANK()`, and `LAG()`
- Aggregation and business analysis
- Power BI dashboard development
- Data storytelling and insight communication


## Conclusion

This project demonstrates an end-to-end data analytics workflow, from raw data exploration and cleaning to data warehousing, SQL-based analysis, and Power BI visualization.

By combining Python, MySQL, and Power BI, the project transforms raw medical appointment records into a structured analytical dataset and presents findings about patient attendance behavior and missed appointments.

The project also demonstrates the use of dimensional modeling, SQL window functions, and data visualization to support data-driven analysis.
