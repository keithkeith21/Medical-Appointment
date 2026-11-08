"""
01_clean_data.py
Medical Appointment No-Shows: exploration, anomaly investigation, cleaning, EDA.

Input : KaggleV2-May-2016.csv          (original file, left untouched)
Output: cleaned_medical_appointments.csv

Every check from the original exploration script is kept, in the same order.
Investigation happens BEFORE any change is made to the data.
"""

import pandas as pd
import numpy as np

RAW_FILE = "KaggleV2-May-2016.csv"
CLEAN_FILE = "cleaned_medical_appointments.csv"


# ---------------------------------------------------------------------
# 1. EXPLORATION
# ---------------------------------------------------------------------
def explore(df):
    print("=======EXPLORATION=======")

    print(df.shape)
    print(df.head(20))
    print(df.info())
    print(df.tail(10))
    print(df.describe())


def check_binary_columns(df):
    print("=======CHECK BINARY COLUMNS=======")

    for col in [
        "Neighbourhood", "Handcap", "Gender", "No-show", "Scholarship",
        "Hipertension", "Diabetes", "Alcoholism", "SMS_received",
    ]:
        print(f"{col}:")
        print(df[col].value_counts())


# ---------------------------------------------------------------------
# 2. DETECT ANOMALIES
# ---------------------------------------------------------------------
def detect_anomalies(df):
    print("=======DETECT ANOMALY=======")

    print(df[["ScheduledDay", "AppointmentDay"]].dtypes)
    print(df[["ScheduledDay", "AppointmentDay"]].head(10))

    # Neighbourhood: any difference after stripping spaces?
    print("Unique neighbourhoods:", df["Neighbourhood"].nunique())
    print(df["Neighbourhood"].astype(str).str.strip().nunique())

    # Handcap should be binary but has values 0-4
    print(
        df.loc[
            df["Handcap"] == 4,
            ["PatientId", "AppointmentID", "Age", "Handcap",
             "Gender", "No-show"],
        ]
    )
    print(
        df.loc[
            df["Handcap"] >= 2,
            ["PatientId", "AppointmentID", "Age", "Handcap",
             "Gender", "Neighbourhood", "No-show"],
        ]
    )

    # Age = 0
    print(
        df.loc[
            df["Age"] == 0,
            ["Gender", "Neighbourhood", "Scholarship",
             "Hipertension", "Diabetes", "SMS_received", "No-show"],
        ].head(20)
    )
    print((df["Age"] == 0).mean() * 100)
    print(df["Age"].value_counts())
    print(df.loc[df["Age"] == 0, "Neighbourhood"].value_counts().head(10))
    print(
        df.loc[
            df["Age"] == 0,
            ["Age", "Neighbourhood", "Scholarship",
             "Hipertension", "Diabetes"],
        ].describe(include="all")
    )
    print(df.groupby("Age")["No-show"].value_counts(normalize=True).head(10))


# ---------------------------------------------------------------------
# 3. INVESTIGATE ANOMALIES (before deciding what to change)
# ---------------------------------------------------------------------
def investigate_anomalies(df):
    print("========INVESTIGATE ANOMALY=======")

    # Age = -1
    print(
        df.loc[
            df["Age"] == -1,
            ["AppointmentID", "Gender", "ScheduledDay", "AppointmentDay",
             "Age", "Neighbourhood", "Scholarship", "Hipertension",
             "Diabetes", "No-show"],
        ]
    )
    print(df["Age"].describe())

    # Very high ages
    print(
        df.loc[
            df["Age"] > 100,
            ["AppointmentID", "Age", "Gender", "No-show"],
        ]
    )
    print(
        df.loc[
            df["Age"] >= 102,
            ["PatientId", "AppointmentID", "Age", "Gender",
             "Neighbourhood", "No-show"],
        ]
    )

    # History of the patient aged 115
    patient_115 = df.loc[df["Age"] == 115, "PatientId"].iloc[0]
    print(
        df.loc[
            df["PatientId"] == patient_115,
            ["PatientId", "AppointmentID", "Age",
             "ScheduledDay", "AppointmentDay", "No-show"],
        ]
    )

    # Do patients with Age = 0 appear again with other ages?
    age_zero_patients = df.loc[df["Age"] == 0, "PatientId"].unique()
    print(
        df.loc[
            df["PatientId"].isin(age_zero_patients),
            ["PatientId", "AppointmentID", "Age", "No-show"],
        ]
        .sort_values("PatientId")
        .head(30)
    )

    # History of the patient with Age = -1
    print(df.loc[df["Age"] == -1])
    patient_id = df.loc[df["Age"] == -1, "PatientId"].iloc[0]
    print(
        df.loc[
            df["PatientId"] == patient_id,
            ["PatientId", "AppointmentID", "Age",
             "ScheduledDay", "AppointmentDay", "No-show"],
        ].sort_values("AppointmentDay")
    )


# ---------------------------------------------------------------------
# 4. CLEANING
# ---------------------------------------------------------------------
def clean(df):
    print("===========CLEANING==========")

    df["ScheduledDay"] = pd.to_datetime(df["ScheduledDay"])
    df["AppointmentDay"] = pd.to_datetime(df["AppointmentDay"])

    # Age = -1 is invalid -> missing value.
    # Age = 0 and ages above 100 were investigated but kept.
    df.loc[df["Age"] == -1, "Age"] = np.nan

    return df


def verify_cleaning(df):
    print("===========VERIFY CLEANING==========")

    print(df[["ScheduledDay", "AppointmentDay"]].dtypes)
    print(df.loc[df["Age"].isna()])
    print("Missing Age:", df["Age"].isna().sum())
    print("Minimum Age:", df["Age"].min())


# ---------------------------------------------------------------------
# 5. DATE ANOMALIES
# ---------------------------------------------------------------------
def investigate_dates(df):
    print("==========INVESTIGATE DATE ANOMALIES========")

    # Scheduled date after appointment date?
    print(
        df.loc[
            df["ScheduledDay"].dt.date > df["AppointmentDay"].dt.date,
            ["ScheduledDay", "AppointmentDay", "Age", "Gender", "No-show"],
        ]
    )

    # normalize() removes the time part so only calendar days are compared
    date_diff = (
        df["AppointmentDay"].dt.normalize()
        - df["ScheduledDay"].dt.normalize()
    ).dt.days

    print(date_diff[date_diff < 0].value_counts())
    print(
        df.loc[
            date_diff < 0,
            ["PatientId", "AppointmentID", "ScheduledDay", "AppointmentDay",
             "Age", "Gender", "No-show"],
        ]
    )
    print(date_diff.describe())
    print(date_diff.value_counts().sort_index().head(20))
    print(df[["ScheduledDay", "AppointmentDay"]].isna().sum())


# ---------------------------------------------------------------------
# 6. PATIENT ID / APPOINTMENT ID
# ---------------------------------------------------------------------
def investigate_ids(df):
    print("=======INVESTIGATE PATIENT ID=======")

    print("Unique PatientId:", df["PatientId"].nunique())
    print("Total rows:", len(df))

    print("\nAppointments per Patient:")
    print(df["PatientId"].value_counts().describe())

    patient_counts = df["PatientId"].value_counts()
    print(patient_counts.head(10))

    top_patient = patient_counts.index[0]
    print(
        df.loc[
            df["PatientId"] == top_patient,
            ["PatientId", "AppointmentID", "ScheduledDay",
             "AppointmentDay", "Age", "Gender", "No-show"],
        ]
    )

    print(df["PatientId"].dtype)
    print(df["AppointmentID"].dtype)
    print("Missing PatientId:", df["PatientId"].isna().sum())
    print("Missing AppointmentID:", df["AppointmentID"].isna().sum())
    print("Duplicate AppointmentID:", df["AppointmentID"].duplicated().sum())
    print("Unique AppointmentID:", df["AppointmentID"].nunique())
    print("Total rows:", len(df))


def final_checks(df):
    print("=======FINAL DATA TYPES CHECK=======")
    print(df.dtypes)

    print("=======FINAL MISSING VALUES CHECK=======")
    print(df.isna().sum())


# ---------------------------------------------------------------------
# 7. EDA
# ---------------------------------------------------------------------
def eda(df):
    print("=======EDA: NO-SHOW OVERVIEW=======")
    print(df["No-show"].value_counts())
    print()
    print(df["No-show"].value_counts(normalize=True) * 100)

    print("=======EDA: SMS vs NO-SHOW=======")
    print(
        pd.crosstab(
            df["SMS_received"],
            df["No-show"],
            normalize="index",
        ) * 100
    )


def main():
    df = pd.read_csv(RAW_FILE)

    explore(df)
    check_binary_columns(df)
    detect_anomalies(df)
    investigate_anomalies(df)

    df = clean(df)
    verify_cleaning(df)

    investigate_dates(df)
    investigate_ids(df)
    final_checks(df)
    eda(df)

    df.to_csv(CLEAN_FILE, index=False)
    print(f"Saved cleaned data to {CLEAN_FILE}")


if __name__ == "__main__":
    main()
