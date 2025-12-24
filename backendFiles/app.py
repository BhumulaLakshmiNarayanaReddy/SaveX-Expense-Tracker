from flask import Flask, request, jsonify
from flask_cors import CORS
from pymongo import MongoClient
from datetime import datetime
import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import random
import string

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
# Replace with your actual password if "bqax zujz crda iifg" is not working
SENDER_EMAIL = "Savex.financial@gmail.com"
SENDER_PASSWORD = "bqax zujz crda iifg" 

# MongoDB Connection
MONGO_URI = "mongodb+srv://YOUR_USERNAME:YOUR_PASSWORD@your-cluster.mongodb.net/"
client = MongoClient(MONGO_URI)
db = client['SaveX_Database']
users_collection = db['users']

# Temporary OTP Storage
otp_storage = {}

# --- HELPER FUNCTIONS ---
def send_email_otp(receiver_email, otp):
    """Sends a 6-digit verification code to the user's email."""
    try:
        context = ssl.create_default_context()
        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls(context=context) 
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            
            msg = MIMEMultipart()
            msg['From'] = SENDER_EMAIL
            msg['To'] = receiver_email
            msg['Subject'] = f" Please confirm your email address. Your OTP is {otp}"
            body = f" Enter the code in the cabex login page to complete your sign up: {otp}\n\nThis code expires in 10 minutes."
            msg.attach(MIMEText(body, 'plain'))
            
            server.sendmail(SENDER_EMAIL, receiver_email, msg.as_string())
        return True
    except Exception as e:
        print(f"CRITICAL EMAIL ERROR: {e}")
        return False

# --- AUTHENTICATION ROUTES ---

@app.route('/send_login_otp', methods=['POST'])
def send_login_otp():
    email = request.json.get('email')
    if not users_collection.find_one({"email": email}):
        return jsonify({"status": "error", "message": "User not found"}), 404
    
    otp = ''.join(random.choices(string.digits, k=6))
    otp_storage[email] = otp
    if send_email_otp(email, otp):
        print(f"DEBUG: Login OTP for {email}: {otp}")
        return jsonify({"status": "success"}), 200
    return jsonify({"status": "error", "message": "Email failed"}), 500

@app.route('/send_signup_otp', methods=['POST'])
def send_signup_otp():
    email = request.json.get('email')
    if users_collection.find_one({"email": email}):
        return jsonify({"status": "error", "message": "Account already exists"}), 409
    
    otp = ''.join(random.choices(string.digits, k=6))
    otp_storage[email] = otp
    if send_email_otp(email, otp):
        print(f"DEBUG: SignUp OTP for {email}: {otp}")
        return jsonify({"status": "success"}), 200
    return jsonify({"status": "error", "message": "Email failed"}), 500

@app.route('/verify_otp', methods=['POST'])
def verify_otp():
    data = request.json
    email = data.get('email')
    user_otp = data.get('otp')
    if otp_storage.get(email) == user_otp:
        # Optional: delete otp_storage[email] after verification for security
        return jsonify({"status": "success"}), 200
    return jsonify({"status": "error", "message": "Invalid OTP"}), 400

@app.route('/create_user', methods=['POST'])
def create_user():
    data = request.json
    new_user = {
        "email": data['email'],
        "name": data['name'],
        "pin": data['pin'],
        "currentBalance": float(data['currentBalance']),
        "transactions": [],
        "budgetReminder": 0.0
    }
    users_collection.insert_one(new_user)
    return jsonify({"status": "success"}), 201

# --- TRANSACTION & USER DATA ROUTES ---

@app.route('/get_user', methods=['GET'])
def get_user():
    email = request.args.get('email')
    user = users_collection.find_one({"email": email}, {"_id": 0})
    if user:
        return jsonify(user), 200
    return jsonify({"error": "User not found"}), 404

@app.route('/add_transaction', methods=['POST'])
def add_transaction():
    data = request.json
    email = data['email']
    amount = float(data['amount'])
    
    new_tx = {
        "category": data['category'],
        "amount": amount,
        "description": data.get('description', ''),
        "isManual": data['isManual'],
        "date": datetime.now().isoformat()
    }

    users_collection.update_one(
        {"email": email},
        {
            "$push": {"transactions": new_tx},
            "$inc": {"currentBalance": -amount} 
        }
    )
    return jsonify({"status": "success"}), 200

@app.route('/add_money', methods=['POST'])
def add_money():
    data = request.json
    users_collection.update_one(
        {"email": data['email']},
        {"$inc": {"currentBalance": float(data['amount'])}}
    )
    return jsonify({"status": "money_added"}), 200

@app.route('/update_balance', methods=['POST'])
def update_balance():
    data = request.json
    user_email = data.get('email')
    new_balance = float(data.get('new_balance'))

    result = users_collection.update_one(
        {"email": user_email},
        {"$set": {"currentBalance": new_balance}}
    )

    if result.matched_count > 0:
        return jsonify({"status": "success", "message": "Balance updated"}), 200
    return jsonify({"status": "error", "message": "User not found"}), 404

@app.route('/set_budget', methods=['POST'])
def set_budget():
    data = request.json
    users_collection.update_one(
        {"email": data['email']},
        {"$set": {"budgetReminder": float(data['amount'])}}
    )
    return jsonify({"status": "budget_set"}), 200

@app.route('/clear_history', methods=['POST'])
def clear_history():
    data = request.json
    email = data['email']
    users_collection.update_one(
        {"email": email},
        {"$set": {"transactions": []}}
    )
    return jsonify({"status": "history_cleared"}), 200

if __name__ == '__main__':
    # Run on 0.0.0.0 so your physical phone can connect via local IP
    app.run(host='0.0.0.0', port=5000, debug=True)
