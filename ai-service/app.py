from flask import Flask, jsonify, request
from flask_cors import CORS
import json
import os

app = Flask(__name__)

# Allow the Node.js backend to call this service
CORS(app)

# Load compatibility rules from JSON file
with open('compatibility.json', 'r') as f:
    COMPATIBILITY = json.load(f)

# ── Health check ──────────────────────────────────────────
# Used to verify the Flask service is running
@app.route('/health')
def health():
    model_exists = os.path.exists('model.joblib')
    return jsonify({
        'status': 'ok',
        'service': 'Smart Blood Bank AI Service',
        'model_trained': model_exists
    })

# ── Compatibility endpoint ─────────────────────────────────
# Given a blood group, returns compatible donor blood groups
# Example: GET /compatibility/A+
@app.route('/compatibility/<blood_group>')
def compatibility(blood_group):
    # Handle URL encoding — A%2B becomes A+
    blood_group = blood_group.replace('%2B', '+')

    if blood_group not in COMPATIBILITY:
        return jsonify({
            'error': f'Invalid blood group: {blood_group}',
            'valid_groups': list(COMPATIBILITY.keys())
        }), 400

    return jsonify({
        'blood_group': blood_group,
        'compatible_with': COMPATIBILITY[blood_group]
    })

# ── Prediction endpoint ────────────────────────────────────
# Returns demand predictions for each blood group
# Returns fallback response until model is trained on Day 13
@app.route('/predict')
def predict():
    model_exists = os.path.exists('model.joblib')

    if not model_exists:
        # Graceful fallback — dashboard shows "unavailable" instead of crashing
        return jsonify({
            'predictions': None,
            'fallback': True,
            'message': 'Model not yet trained. Run train.py to generate predictions.'
        })

    # Real predictions will be returned here after Day 13
    from predict import get_predictions
    predictions = get_predictions()
    return jsonify({
        'predictions': predictions,
        'fallback': False
    })

if __name__ == '__main__':
    app.run(port=5001, debug=True)