"""
02_load_to_mysql.py
Loads the cleaned CSV into MySQL as the staging table `staging_appointments`.

The staging table stays in MySQL as the permanent raw layer: the star schema is
built from it in SQL, so the warehouse can be rebuilt without reloading the CSV.

Before running: create the database in MySQL Workbench
    CREATE DATABASE medical_appointment;
"""

import pandas as pd
from sqlalchemy import create_engine

df = pd.read_csv("cleaned_medical_appointments.csv")

username = "root"
password = ""          # local MySQL has no password
host = "localhost"
port = "3306"
database = "medical_appointment"

engine = create_engine(
    f"mysql+pymysql://{username}:{password}@{host}:{port}/{database}"
)

df.to_sql(
    name="staging_appointments",
    con=engine,
    if_exists="replace",   # re-running rebuilds the staging table
    index=False,
)

print("Data successfully loaded to MySQL!")
