# SaveX - Professional Expense Tracker

SaveX is a Flutter-based mobile application designed to help users track their daily spending with professional analytics and budget reminders.

##  Key Features
* **Spending Analytics:** A dynamic line chart showing the last 5 days of activity.
* **Budget Reminders:** Set a monthly limit and get notified of your status.
* **Authentication:** Secure login and OTP verification.
* **Category Tracking:** Organize spending into Groceries, Food, Shopping, and more.
* **Dashboard:** Real-time balance and category overview.
* **Fixed Expenses:** Manage recurring payments easily.
* **QR Scanner:** Scan and pay or log expenses instantly.
* **Analytics:** Professional line charts (Graph) to track 5-day spending trends.

## 📸 App Screenshots

<table style="width: 100%; border-collapse: collapse;">
  <tr>
    <td align="center"><b>Dashboard</b></td>
    <td align="center"><b>Fixed Amounts</b></td>
    <td align="center"><b>QR Scanner</b></td>
    <td align="center"><b>Spending Graph</b></td>
    <td align="center"><b>Profile</b></td>
  </tr>
  <tr>
    <td><img src="Screenshots/dashboard.png" width="180"></td>
    <td><img src="Screenshots/fixedAmounts.png" width="180"></td>
    <td><img src="Screenshots/scanner.png" width="180"></td>
    <td><img src="Screenshots/graph.png" width="180"></td>
    <td><img src="Screenshots/profile.png" width="180"></td>
  </tr>
</table>


## 🛠️ Tech Stack
* **Frontend:** Flutter & Dart
* **Backend:** Flask (Python)
* **Database:** mongodb
* **State Management:** Provider

## 🏁 How to Run
1. Clone the repository.
2. Run `flutter pub get`.
3. Ensure your Flask server is running at the configured IP.
4. Run `flutter run`.

## 📥 Installation & Setup Guide
Since this is a personal project, the main server is not hosted 24/7. To run the app and test its full functionality, please follow these steps:

### 1. Database Setup (MongoDB)
The app uses **MongoDB** to store expenses and user data.
* Create a free account at [MongoDB Atlas](https://www.mongodb.com/cloud/atlas).
* Create a Cluster and get your **Connection String (URI)**.
* Open `backendFiles/app.py` and replace the `MONGO_URI` with your own:

```python
# Replace YOUR_USERNAME and YOUR_PASSWORD with your credentials
MONGO_URI = "mongodb+srv://YOUR_USERNAME:YOUR_PASSWORD@your-cluster.mongodb.net/"
