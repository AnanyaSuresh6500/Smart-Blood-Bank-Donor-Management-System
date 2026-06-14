"""
Blood Demand Prediction Model — Training Script
Run this script on Day 13 once the database has real data.
Usage: python train.py
"""
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error
import joblib
import psycopg2
import os
from dotenv import load_dotenv

load_dotenv('../backend/.env')

def train():
    print("Connecting to ShaktiDB...")
    conn = psycopg2.connect(
        host=os.getenv('DB_HOST'),
        port=os.getenv('DB_PORT', 5432),
        dbname=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD')
    )

    print("Loading training data...")
    # This query uses the v_donation_monthly view
    # created in the database schema on Day 1
    query = """
        SELECT blood_group, units_requested,
               EXTRACT(MONTH FROM requested_at) as month,
               EXTRACT(DOW FROM requested_at) as day_of_week
        FROM BloodRequests
        WHERE status != 'cancelled'
        ORDER BY requested_at
    """
    df = pd.read_sql(query, conn)
    conn.close()

    if df.empty:
        print("No training data found. Run seed script first.")
        return

    # One-hot encode blood group
    df = pd.get_dummies(df, columns=['blood_group'])

    # Features and target
    X = df.drop('units_requested', axis=1)
    y = df['units_requested']

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    print("Training Random Forest model...")
    model = RandomForestRegressor(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    # Evaluate
    predictions = model.predict(X_test)
    mae = mean_absolute_error(y_test, predictions)
    print(f"Model trained. Mean Absolute Error: {mae:.2f} units")

    # Save model
    joblib.dump(model, 'model.joblib')
    print("Model saved to model.joblib")

if __name__ == '__main__':
    train()