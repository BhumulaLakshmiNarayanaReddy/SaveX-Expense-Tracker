import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart'; 

// --- SHARED UI COMPONENTS ---
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isNumeric;
  final bool isPin;
  final int? maxLength;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.isNumeric = false,
    this.isPin = false,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        obscureText: isPin,
        maxLength: maxLength,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.emailAddress,
        inputFormatters: isNumeric ? [FilteringTextInputFormatter.digitsOnly] : [],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.purple),
          counterText: "",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }
}

// --- SCREEN 1: LANDING ---
class AuthLandingPage extends StatefulWidget {
  const AuthLandingPage({super.key});

  @override
  State<AuthLandingPage> createState() => _AuthLandingPageState();
}

class _AuthLandingPageState extends State<AuthLandingPage> {
  int _tapCount = 0; 

  void _handleSecretTaps() {
    setState(() {
      _tapCount++;
    });

    if (_tapCount >= 7) {
      _tapCount = 0; 
      _showUrlDialog();
    }
  }

  void _showUrlDialog() {
    final appState = context.read<AppState>();
    final controller = TextEditingController(text: appState.serverUrl);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_remote, color: Colors.purple),
            SizedBox(width: 10),
            Text("Backend Settings"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter the server IP address provided by your developer:", 
              style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Server URL",
                hintText: "http://192.168.1.XX:5000",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            onPressed: () async {
              String newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await appState.updateServerUrl(newUrl);
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Connected to: $newUrl")),
                );
              }
            },
            child: const Text("Update & Connect"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. THE MAIN UI
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.purple.withOpacity(0.1), Colors.white],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet, size: 80, color: Colors.purple),
                const Text("SaveX", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.purple)),
                const SizedBox(height: 60),
                _btn(context, "Login", const LoginPage(), true),
                const SizedBox(height: 15),
                _btn(context, "Sign Up", const SignUpPage(), false),
              ],
            ),
          ),

          // 2. THE HIDDEN TRIGGER ICON 
          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: _handleSecretTaps,
              child: Opacity(
                opacity: 0.2, 
                child: Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.transparent,
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 25, color: Colors.purple),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, String text, Widget page, bool primary) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ? Colors.purple : Colors.white,
        foregroundColor: primary ? Colors.white : Colors.purple,
        minimumSize: const Size(280, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15), 
          side: const BorderSide(color: Colors.purple)
        ),
      ),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => page)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

// --- SCREEN 2: LOGIN ---
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  bool _isLoading = false;

  void _requestOtp() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse("${context.read<AppState>().serverUrl}/send_login_otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": _email.text.trim()}),
      );
      if (res.statusCode == 200) {
        Navigator.push(context, MaterialPageRoute(builder: (c) => OtpVerifyPage(email: _email.text.trim(), isLogin: true)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account not found")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection Error")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            CustomTextField(controller: _email, label: "Email Address", icon: Icons.email_outlined),
            const SizedBox(height: 30),
            _isLoading 
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
                  onPressed: _requestOtp,
                  child: const Text("Get OTP"),
                ),
          ],
        ),
      ),
    );
  }
}

// --- SCREEN 3: SIGN UP ---
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _balance = TextEditingController();
  bool _isLoading = false;

  void _requestOtp() async {
    setState(() => _isLoading = true);
    final res = await http.post(
      Uri.parse("${context.read<AppState>().serverUrl}/send_signup_otp"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": _email.text.trim()}),
    );
    setState(() => _isLoading = false);

    if (res.statusCode == 200) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => OtpVerifyPage(
        email: _email.text.trim(),
        isLogin: false,
        signupData: {"name": _name.text, "pin": _pin.text, "balance": _balance.text},
      )));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account already exists")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            CustomTextField(controller: _name, label: "Name", icon: Icons.person_outline),
            CustomTextField(controller: _email, label: "Email", icon: Icons.email_outlined),
            CustomTextField(controller: _pin, label: "4-Digit PIN", icon: Icons.lock_outline, isNumeric: true, isPin: true, maxLength: 4),
            CustomTextField(controller: _balance, label: "Initial Balance", icon: Icons.account_balance_wallet_outlined, isNumeric: true),
            const SizedBox(height: 30),
            _isLoading ? const CircularProgressIndicator() : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
              onPressed: _requestOtp,
              child: const Text("Verify Email"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- SCREEN 4: OTP VERIFY ---
class OtpVerifyPage extends StatefulWidget {
  final String email;
  final bool isLogin;
  final Map<String, dynamic>? signupData;
  const OtpVerifyPage({super.key, required this.email, required this.isLogin, this.signupData});

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage> {
  final _otp = TextEditingController();

  void _verify() async {
    final state = context.read<AppState>();
    final res = await http.post(
      Uri.parse("${state.serverUrl}/verify_otp"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": widget.email, "otp": _otp.text.trim()}),
    );

    if (res.statusCode == 200) {
      if (!widget.isLogin) {
        await http.post(Uri.parse("${state.serverUrl}/create_user"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "email": widget.email,
            "name": widget.signupData!['name'],
            "pin": widget.signupData!['pin'],
            "currentBalance": widget.signupData!['balance'],
          }));
      }
      await state.saveSession(widget.email);
      
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (c) => const MainNavigation()), 
        (route) => false
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Enter 6-digit OTP", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(counterText: ""),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
                onPressed: _verify,
                child: const Text("Confirm & Continue"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}