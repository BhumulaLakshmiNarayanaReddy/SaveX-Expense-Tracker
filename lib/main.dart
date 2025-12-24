import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;
import 'authentication.dart';


// 2. Update your main function to be async
void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    final prefs = await SharedPreferences.getInstance();
    final String? savedEmail = prefs.getString('user_email');

    final appState = AppState();
    
    // Use a try-catch here so a server error doesn't kill the app
    try {
      await appState.loadSavedUrl();
      if (savedEmail != null && savedEmail.isNotEmpty) {
        appState.userEmail = savedEmail;
        await appState.loadUserData();
      }
    } catch (e) {
      print("Startup Data Error: $e");
    }

    runApp(
      ChangeNotifierProvider.value(
        value: appState,
        child: SaveXApp(isLoggedIn: savedEmail != null),
      ),
    );
  } catch (e) {
    print("CRITICAL CRASH: $e");
  }
}

// 3. Update SaveXApp to use the 'isLoggedIn' flag
class SaveXApp extends StatelessWidget {
  final bool isLoggedIn;
  const SaveXApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.purple),
      // THE FIX: If logged in, go to Dashboard. If not, go to Login landing page.
      home: isLoggedIn ? const MainNavigation() : const AuthLandingPage(),
    );
  }
}
// --- DATA MODELS ---
class Transaction {
  final String category;
  final double amount;
  final DateTime date;
  final String? description;
  final bool isManual;

  Transaction({
    required this.category,
    required this.amount,
    required this.date,
    this.description,
    required this.isManual,
  });
}

// --- CONSOLIDATED APP STATE ---
class AppState extends ChangeNotifier {
  String serverUrl = "http://10.221.210.153:5000"; 

  double currentBalance = 0.0;
  String userName = "";
  String userEmail = "";
  String userPin = "";
  double budgetReminder = 0.0;
  bool isLoading = false;

  Map<String, List<Transaction>> categoryData = {
    "Groceries": [], "Food": [], "Shopping": [], "Transport": [], "Bills": [],
    "Health": [], "Education": [], "Entertainment": [], "Others": [],
    "Loan": [], "EMI": [], "Autopay": [], "Fixed Others": [],
  };

  List<String> notifications = ["Welcome to SaveX!"];
  // NEW METHOD: Called by authentication.dart after successful OTP
  void setAuthenticatedUser(String email) {
      userEmail = email;
      loadUserData(); // Now fetch actual data for THIS user
  }

  Future<void> updateServerUrl(String newUrl) async {
      serverUrl = newUrl;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_url', newUrl); // Save URL permanently
      notifyListeners();
    }
    Future<void> loadSavedUrl() async {
      final prefs = await SharedPreferences.getInstance();
      String? savedUrl = prefs.getString('custom_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        serverUrl = savedUrl;
        notifyListeners();
      }
    }

  // 1. SYNC: Database to App
  Future<void> loadUserData() async {
    isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse("$serverUrl/get_user?email=$userEmail"));
      
      if (response.statusCode == 200) {
              var data = jsonDecode(response.body);
              currentBalance = (data['currentBalance'] ?? 0.0).toDouble();
              userName = data['name'] ?? "User";
              userPin = data['pin'] ?? "0000"; // Load the actual PIN from DB
              budgetReminder = (data['budgetReminder'] ?? 0.0).toDouble();
        
        // Clear local lists to prevent duplicates
        categoryData.forEach((key, value) => value.clear());

        List txsFromDb = data['transactions'] ?? [];
        for (var item in txsFromDb) {
          String cat = item['category'];
          if (categoryData.containsKey(cat)) {
            categoryData[cat]?.add(Transaction(
              category: cat,
              amount: (item['amount']).toDouble(),
              date: DateTime.parse(item['date']).toLocal(),
              description: item['description'],
              isManual: item['isManual'] ?? false,
            ));
          }
        }
        debugPrint("Sync Complete. Balance: $currentBalance");
      }
    } catch (e) {
      debugPrint("Sync Failed: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // 2. ACTIONS: App to Database
  Future<void> addTransaction(String cat, double amt, {String? desc, required bool isManual}) async {
    currentBalance -= amt;
    categoryData[cat]?.insert(0, Transaction(
      category: cat, amount: amt, date: DateTime.now(), description: desc, isManual: isManual
    ));
    notifyListeners();

    await http.post(
      Uri.parse("$serverUrl/add_transaction"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": userEmail,
        "category": cat,
        "amount": amt,
        "description": desc,
        "isManual": isManual
      }),
    );
  }

  Future<void> addMoney(double amount) async {
    currentBalance += amount;
    notifyListeners();

    await http.post(
      Uri.parse("$serverUrl/add_money"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": userEmail, "amount": amount}),
    );
  }

  Future<void> updateProfile(String name, String email) async {
    String oldEmail = userEmail;
    userName = name;
    userEmail = email;
    notifyListeners();

    await http.post(
      Uri.parse("$serverUrl/update_profile"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"old_email": oldEmail, "name": name, "email": email}),
    );
  }
  // NEW: Save email to local storage
Future<void> saveSession(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email); // Saves to permanent storage
    userEmail = email;
    await loadUserData();
    notifyListeners();
  }

  // Call this when the user clicks Logout
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email'); // Deletes from permanent storage
    userEmail = "";
    userName = "";
    currentBalance = 0.0;
    notifyListeners();
  }

  // UPDATED: Check if user is already logged in
  Future<String?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_email');
  }
  Future<void> clearHistory() async {
    categoryData.forEach((key, value) => value.clear());
    notifyListeners();

    await http.post(
      Uri.parse("$serverUrl/clear_history"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": userEmail}),
    );
  }

  Future<void> setBudget(double amount) async {
    budgetReminder = amount;
    notifyListeners();

    await http.post(
      Uri.parse("$serverUrl/set_budget"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": userEmail, "amount": amount}),
    );
  }

  // 3. CALCULATIONS
  double get totalSpentThisMonth {
    double total = 0;
    categoryData.forEach((_, list) {
      for (var tx in list) {
        if (tx.date.month == DateTime.now().month && tx.date.year == DateTime.now().year) {
          total += tx.amount;
        }
      }
    });
    return total;
  }

  double getSpentOnDate(DateTime date) {
    double total = 0;
    categoryData.forEach((_, list) {
      for (var tx in list) {
        if (tx.date.day == date.day && tx.date.month == date.month && tx.date.year == date.year) {
          total += tx.amount;
        }
      }
    });
    return total;
  }
}


class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  final List<Widget> _pages = [const HomePage(), const FixedAmountsPage(), const QRScanPage(), const MetricsPage(), const ProfilePage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.purple,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Fixed'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Pay'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Metrics'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// --- 1. HOME PAGE ---
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text("Home", style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 30),
            onPressed: () {
              // THIS IS THE LINK TO THE CODE I GAVE YOU ABOVE
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationPage()));
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25))),
            child: Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Total Spent This Month", style: TextStyle(color: Colors.white70, fontSize: 18)),
                  Text("₹${state.totalSpentThisMonth.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12,
              children: [
                _catCard(context, "Groceries", Icons.shopping_cart, Colors.green),
                _catCard(context, "Food", Icons.restaurant, Colors.orange),
                _catCard(context, "Shopping", Icons.shopping_bag, Colors.pink),
                _catCard(context, "Transport", Icons.directions_car, Colors.blue),
                _catCard(context, "Bills", Icons.receipt_long, Colors.amber),
                _catCard(context, "Health", Icons.favorite, Colors.red),
                _catCard(context, "Education", Icons.school, Colors.indigo),
                _catCard(context, "Entertainment", Icons.movie, Colors.purpleAccent),
                _catCard(context, "Others", Icons.more_horiz, Colors.blueGrey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catCard(BuildContext context, String name, IconData icon, Color color) {
    final state = context.watch<AppState>();
    double sum = state.categoryData[name]!.fold(0, (p, e) => p + e.amount);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context, 
        isScrollControlled: true, 
        builder: (c) => CategoryActionSheet(category: name)
      ),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
            Text("₹${sum.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// --- 2. ADD EXPENSE SHEET ---
class CategoryActionSheet extends StatefulWidget {
  final String category;
  const CategoryActionSheet({super.key, required this.category});

  @override
  State<CategoryActionSheet> createState() => _CategoryActionSheetState();
}

class _CategoryActionSheetState extends State<CategoryActionSheet> {
  final TextEditingController _amt = TextEditingController(text: "0");
  final TextEditingController _desc = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.categoryData[widget.category] ?? [];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
      color: Color.fromARGB(255, 255, 255, 255), // <--- This makes the window solid white
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Add ${widget.category}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text("₹", style: TextStyle(fontSize: 40, color: Color.fromARGB(255, 53, 47, 47))),
            IntrinsicWidth(child: TextField(
              controller: _amt,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(border: InputBorder.none),
            )),
          ]),
          // Update the build method inside _CategoryActionSheetState
          if (["Loan", "EMI", "Autopay", "Fixed Others", "Others"].contains(widget.category))
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: TextField(
                controller: _desc,
                decoration: InputDecoration(
                  hintText: "Enter description (e.g. HDFC Loan)",
                  filled: true,
                  fillColor: const Color.fromARGB(255, 231, 231, 231),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          // Removed 2000 button
          Wrap(spacing: 10, children: [50, 100, 200, 500, 1000].map((v) => ActionChip(
            label: Text("₹$v"), onPressed: () => setState(() => _amt.text = v.toString()),
          )).toList()),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
            onPressed: () {
              if (_amt.text != "0") {
                state.addTransaction(widget.category, double.parse(_amt.text), desc: _desc.text, isManual: true);
                _amt.text = "0"; _desc.clear();
              }
            },
            child: const Text("Enter"),
          ),
          const Divider(height: 40),
          Expanded(
            child: ListView.builder(
              itemCount: history.length,
              itemBuilder: (c, i) => ListTile(
                title: Text("₹${history[i].amount.toStringAsFixed(0)}", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: history[i].isManual ? Colors.red : Colors.green)),
                subtitle: Text(history[i].description ?? widget.category),
                trailing: Text(DateFormat('dd MMM').format(history[i].date)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- 3. FIXED AMOUNTS PAGE ---
class FixedAmountsPage extends StatelessWidget {
  const FixedAmountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    List<Transaction> fixedHistory = [];
    ["Loan", "EMI", "Autopay", "Fixed Others"].forEach((cat) => fixedHistory.addAll(state.categoryData[cat]!));

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.purple, title: const Text("Fixed Amounts", style: TextStyle(color: Colors.white))),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.3,
                children: [
                  _fixedBtn(context, "Loan", Colors.red, Icons.business),
                  _fixedBtn(context, "EMI", Colors.orange, Icons.credit_card),
                  _fixedBtn(context, "Autopay", Colors.purple, Icons.sync),
                  _fixedBtn(context, "Fixed Others", Colors.blueGrey, Icons.more_horiz),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.all(16), child: Align(alignment: Alignment.centerLeft, child: Text("Payment History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: fixedHistory.length,
              itemBuilder: (c, i) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt)),
                title: Text(fixedHistory[i].category),
                subtitle: Text(fixedHistory[i].description ?? "Fixed Payment"),
                trailing: Text("₹${fixedHistory[i].amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _fixedBtn(BuildContext context, String label, Color color, IconData icon, {String? dbCatName}) {
    String actualCat = dbCatName ?? label;
    
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => CategoryActionSheet(category: actualCat),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Vertically center the content
          children: [
            // This creates the white background "Aura" around the icon
            Container(
              height: 60, // Size of the white circle
              width: 60,
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 255, 255, 255), // The white background
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color, // The icon takes the color of the button
                size: 35,    // Size of the symbol inside
              ),
            ),
            
            const SizedBox(height: 12), // Space between circle and text
            
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 4. QR SCAN & FULL PAGE PAY ---
class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});
  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController();
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    // Start the camera
    controller.start();
    
    // Setup the scanning line animation (2 seconds to slide down)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. The Camera View
          MobileScanner(
            controller: controller, 
          onDetect: (capture) {
            if (!mounted) return;
            controller.stop(); // Stop scanning once a code is found
            Navigator.push(context, MaterialPageRoute(builder: (c) => const FullPayPage(merchant: "Merchant Store")))
              .then((value) => controller.start()); // Restart scanning when you come back
          }
          ),
          // 2. The Animated Overlay (Dark background, Corners, and Scanning Line)
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return Positioned.fill(
                child: CustomPaint(
                  painter: ScannerOverlayPainter(scanPosition: _animController.value),
                ),
              );
            },
          ),

          // 3. Instruction Text
          const Positioned(
            top: 100, left: 0, right: 0,
            child: Text(
              "Scan QR Code to Pay",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
          // 4. Bottom Controls (Flash, Manual Capture, and Gallery)
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Flash Button
                CircleAvatar(
                  backgroundColor: Colors.white24, 
                  child: IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.white), 
                    onPressed: () => controller.toggleTorch()
                  )
                ),

                // --- THE MISSING CIRCLE BUTTON ---
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FullPayPage(merchant: "Merchant Store"))),
                  child: Container(
                    width: 75, 
                    height: 75, 
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, 
                      border: Border.all(color: Colors.white, width: 5), // Thick white border
                      color: Colors.white24, // See-through white middle
                    ),
                    child: const Icon(Icons.qr_code, color: Colors.white, size: 30), // Added a small icon inside for style
                  ),
                ),

                // Gallery Button
                CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    onPressed: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => const FullPayPage(merchant: "Gallery QR Payment")));
                      }
                    },
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
class ScannerOverlayPainter extends CustomPainter {
  final double scanPosition;
  ScannerOverlayPainter({required this.scanPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final double scanBoxSize = 250.0;
    final double borderRadius = 30.0;
    final double cornerLen = 40.0;

    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanBoxSize,
      height: scanBoxSize,
    );

    // 1. Draw Dark Blurred Overlay
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.65);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanRect, Radius.circular(borderRadius))),
      ),
      backgroundPaint,
    );

    // 2. Draw Perfectly Aligned White Corner Arcs
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final Path path = Path();
    // Top Left
    path.moveTo(scanRect.left, scanRect.top + cornerLen);
    path.lineTo(scanRect.left, scanRect.top + borderRadius);
    path.arcToPoint(Offset(scanRect.left + borderRadius, scanRect.top), radius: Radius.circular(borderRadius));
    path.lineTo(scanRect.left + cornerLen, scanRect.top);
    // Top Right
    path.moveTo(scanRect.right - cornerLen, scanRect.top);
    path.lineTo(scanRect.right - borderRadius, scanRect.top);
    path.arcToPoint(Offset(scanRect.right, scanRect.top + borderRadius), radius: Radius.circular(borderRadius));
    path.lineTo(scanRect.right, scanRect.top + cornerLen);
    // Bottom Right
    path.moveTo(scanRect.right, scanRect.bottom - cornerLen);
    path.lineTo(scanRect.right, scanRect.bottom - borderRadius);
    path.arcToPoint(Offset(scanRect.right - borderRadius, scanRect.bottom), radius: Radius.circular(borderRadius));
    path.lineTo(scanRect.right - cornerLen, scanRect.bottom);
    // Bottom Left
    path.moveTo(scanRect.left + cornerLen, scanRect.bottom);
    path.lineTo(scanRect.left + borderRadius, scanRect.bottom);
    path.arcToPoint(Offset(scanRect.left, scanRect.bottom - borderRadius), radius: Radius.circular(borderRadius));
    path.lineTo(scanRect.left, scanRect.bottom - cornerLen);

    canvas.drawPath(path, cornerPaint);

    // 3. Draw the Scanning Line (Purple Laser)
    double lineY = scanRect.top + (scanRect.height * scanPosition);
    final laserPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.purple.withOpacity(0.1), Colors.purple, Colors.purple.withOpacity(0.1)],
      ).createShader(Rect.fromLTWH(scanRect.left, lineY, scanRect.width, 3));

    canvas.drawRect(Rect.fromLTWH(scanRect.left + 15, lineY, scanRect.width - 30, 2.5), laserPaint);
    
    // Add glow to the laser
    canvas.drawRect(
      Rect.fromLTWH(scanRect.left + 15, lineY - 1, scanRect.width - 30, 4),
      Paint()..color = Colors.purple.withOpacity(0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(ScannerOverlayPainter oldDelegate) => oldDelegate.scanPosition != scanPosition;
}

class FullPayPage extends StatefulWidget {
  final String merchant;
  const FullPayPage({super.key, required this.merchant});
  @override
  State<FullPayPage> createState() => _FullPayPageState();
}

class _FullPayPageState extends State<FullPayPage> {
  bool showPin = false;
  final TextEditingController amount = TextEditingController();
  final TextEditingController pin = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.merchant)),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const SizedBox(height: 50),
            Text(showPin ? "Enter Secure PIN" : "Enter Amount", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: showPin ? pin : amount,
              textAlign: TextAlign.center,
              obscureText: showPin,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: showPin ? "****" : "₹0"),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () {
                if (!showPin) {
                  setState(() => showPin = true);
                } else if (pin.text == context.read<AppState>().userPin) {
                  _showCategoryPicker();
                }
              },
              child: Text(showPin ? "Pay Now" : "Proceed"),
            )
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(context: context, builder: (c) => ListView(
      children: ["Groceries", "Food", "Shopping", "Transport", "Bills", "Others"].map((cat) => ListTile(
        title: Text(cat),
        onTap: () {
          context.read<AppState>().addTransaction(cat, double.parse(amount.text), isManual: false);
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      )).toList(),
    ));
  }
}

// --- 5. METRICS PAGE (UPDATED WITH OVERFLOW FIX) ---
class MetricsPage extends StatefulWidget {
  const MetricsPage({super.key});

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  // 1. Initialize the controller here
  final TextEditingController reminderController = TextEditingController();

  @override
  void dispose() {
    // 2. Clean up the controller when the widget is destroyed
    reminderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Spending Analytics", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
                // 1. CHART SECTION
              Container(
                height: 250, // Fixed height for stability
                margin: const EdgeInsets.symmetric(vertical: 20),
                padding: const EdgeInsets.only(right: 20, top: 10), 
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    // 1. Fixed Y-Axis for Money (₹)
                    SizedBox(
                      width: 50,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: YAxisPainter(context.watch<AppState>()),
                      ),
                    ),
                    // 2. The Line Graph
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: DynamicChartPainter(context.watch<AppState>()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text("History shows spending trends over the last 5 days.", 
                style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 25),

// 2. MONTHLY BUDGET REMINDER SECTION
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9C4), 
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, 
                          color: Colors.orange.shade800, size: 28),
                        const SizedBox(width: 12),
                        Text("Set a Reminder", 
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, 
                          color: Colors.orange.shade900)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text("Enter monthly limit amount. We'll notify you if you exceed this.", 
                      style: TextStyle(fontSize: 14, color: Colors.black87)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: reminderController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: "Enter amount (₹)",
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15), 
                                borderSide: BorderSide.none
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            final String input = reminderController.text;
                            final double? amount = double.tryParse(input);

                            if (amount != null && amount > 0) {
                              context.read<AppState>().setBudget(amount); 
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Budget limit set successfully!"), 
                                  backgroundColor: Colors.green
                                ),
                              );
                              reminderController.clear();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Please enter a valid amount"), 
                                  backgroundColor: Colors.red
                                ),
                              );
                            }
                          },
                          child: const Text("Set", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    // --- NEW SECTION ADDED BELOW ---
                    // This checks if a budget is set and displays it at the bottom
                    if (context.watch<AppState>().budgetReminder > 0) ...[
                      const SizedBox(height: 20),
                      const Divider(color: Colors.orange, thickness: 0.5),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.orange.shade900, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "Your budget reminder is set at ₹${context.watch<AppState>().budgetReminder.toStringAsFixed(0)}",
                            style: TextStyle(
                              fontSize: 15, 
                              fontWeight: FontWeight.bold, 
                              color: Colors.orange.shade900
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ------------------------------
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// --- LINKEDIN STYLE NOTIFICATION PAGE ---
class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    // This pulls the notifications from your AppState
    final notes = context.watch<AppState>().notifications;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F2EF), // LinkedIn light grey background
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        title: const Text("Notifications", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 19)),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: notes.isEmpty 
        ? const Center(child: Text("No new notifications"))
        : ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: Color(0xFFEBEBEB)),
            itemBuilder: (context, index) {
              return Container(
                color: Colors.white, // Each notification has a white card feel
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Notification Icon / Avatar
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.purple,
                      child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    
                    // Notification Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.4),
                              children: [
                                const TextSpan(text: "Transaction Alert: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(text: notes[index]),
                                const TextSpan(text: " has been added to your history successfully."),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('h:mm a • d MMM').format(DateTime.now()), // Timestamp
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    // "More" icon like LinkedIn
                    const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                  ],
                ),
              );
            },
          ),
    );
  }
}

class DynamicChartPainter extends CustomPainter {
  final AppState state;
  DynamicChartPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    // Leave space at the bottom for X-axis labels
    double bottomPadding = 30.0;
    double chartHeight = size.height - bottomPadding;
    
    final linePaint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()..color = Colors.purple;
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    // 1. Get Data: 4 days ago -> Today (Right side)
    List<double> values = [];
    List<String> labels = [];
    for (int i = 4; i >= 0; i--) {
      DateTime d = DateTime.now().subtract(Duration(days: i));
      values.add(state.getSpentOnDate(d));
      
      if (i == 0) labels.add("Today");
      else if (i == 1) labels.add("Yesterday");
      else labels.add(DateFormat('MM/dd').format(d));
    }

    // 2. Dynamic Scaling
    double maxVal = values.fold(0, (p, c) => p > c ? p : c);
    if (maxVal < 500) maxVal = 500;

    final path = Path();
    double widthPerStep = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      double x = i * widthPerStep;
      // Calculate Y based on chartHeight (leaving room for text)
      double y = chartHeight - (values[i] / maxVal * chartHeight);

      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);

      // Draw the Point
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);

      // 3. Draw X-Axis Labels (Today, Y'day, etc.)
      textPainter.text = TextSpan(
        text: labels[i],
        style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      
      // Center the text under the dot
      double xOffset = x - (textPainter.width / 2);
      // If it's the last label (Today), nudge it left so it doesn't cut off
      if (i == values.length - 1) xOffset = x - textPainter.width;
      if (i == 0) xOffset = x;

      textPainter.paint(canvas, Offset(xOffset, chartHeight + 10));
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class YAxisPainter extends CustomPainter {
  final AppState state;
  YAxisPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    double bottomPadding = 30.0;
    double chartHeight = size.height - bottomPadding;
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    
    double maxVal = 0;
    for (int i = 0; i < 5; i++) {
      double v = state.getSpentOnDate(DateTime.now().subtract(Duration(days: i)));
      if (v > maxVal) maxVal = v;
    }
    if (maxVal < 500) maxVal = 500;

    // Draw 5 levels of money labels
    for (int i = 0; i <= 4; i++) {
      double y = chartHeight - (i * chartHeight / 4);
      textPainter.text = TextSpan(
        text: "₹${(maxVal * i / 4).toInt()}",
        style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - 6));
    }
  }

  @override bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// --- 5. STATEMENTS PAGE ---
class StatementsPage extends StatelessWidget {
  const StatementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    List<Transaction> allTx = [];
    state.categoryData.forEach((key, list) => allTx.addAll(list));
    allTx.sort((a, b) => b.date.compareTo(a.date)); // Newest first

    return Scaffold(
      appBar: AppBar(title: const Text("Account Statements")),
      body: allTx.isEmpty 
        ? const Center(child: Text("No transactions yet"))
        : ListView.builder(
            itemCount: allTx.length,
            itemBuilder: (c, i) => ListTile(
              leading: Icon(allTx[i].isManual ? Icons.arrow_downward : Icons.qr_code, 
                color: allTx[i].isManual ? Colors.red : Colors.green),
              title: Text(allTx[i].category, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(DateFormat('dd MMM, hh:mm a').format(allTx[i].date)),
              trailing: Text("₹${allTx[i].amount.toStringAsFixed(0)}", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, 
                  color: allTx[i].isManual ? Colors.red : Colors.green)),
            ),
          ),
    );
  }
}

// --- 6. PROFILE PAGE ---
class ProfilePage extends StatelessWidget {
  void _showEditProfile(BuildContext context) {
    final state = context.read<AppState>();
    TextEditingController nameCtrl = TextEditingController(text: state.userName);
    TextEditingController mailCtrl = TextEditingController(text: state.userEmail);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Edit Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
            TextField(controller: mailCtrl, decoration: const InputDecoration(labelText: "Email")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            state.updateProfile(nameCtrl.text, mailCtrl.text);
            Navigator.pop(c);
          }, child: const Text("Save")),
        ],
      ),
    );
  }
  void _showLargeBalanceWindow(BuildContext context) {
    TextEditingController addAmt = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom, left: 25, right: 25, top: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Bank Balance", style: TextStyle(fontSize: 18, color: Colors.grey)),
            Text("₹${context.watch<AppState>().currentBalance.toStringAsFixed(2)}", 
              style: const TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 30),
            TextField(
              controller: addAmt,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "Enter amount to add",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () {
                double? val = double.tryParse(addAmt.text); // Safe parsing
                if (val != null) {
                  context.read<AppState>().addMoney(val);
                  Navigator.pop(c);
                } else {
                  // Optional: show error message
                }
              },
              child: const Text("Add Amount to Bank", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
        Container(
          width: double.infinity, 
          padding: const EdgeInsets.only(top: 50, bottom: 30), 
          color: Colors.purple,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white70),
                  onPressed: () => _showEditProfile(context),
                ),
              ),
              const CircleAvatar(radius: 45, backgroundColor: Colors.white, child: Icon(Icons.person, size: 50, color: Colors.purple)),
              const SizedBox(height: 15),
              Text(context.watch<AppState>().userName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text(context.watch<AppState>().userEmail, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. CLEAR HISTORY
              _tile(Icons.delete, "Clear History", Colors.red, onTap: () {
                context.read<AppState>().clearHistory();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All transaction history erased.")));
              }),

              // 2. STATEMENTS (Replaced Settings)
              _tile(Icons.receipt_long, "Statements", Colors.blue, onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => const StatementsPage()));
              }),

              // 3. BALANCES (Large Window + Add Money)
              _tile(Icons.account_balance_wallet, "Balances", Colors.green, onTap: () {
                _showLargeBalanceWindow(context);
              }),

              // 4. INFO US (Detailed Window)
              _tile(Icons.info, "Info Us", Colors.purple, onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: "SaveX",
                  applicationVersion: "1.0.4",
                  applicationIcon: const Icon(Icons.account_balance_wallet, color: Colors.purple, size: 40),
                  children: [
                    const Text("SaveX is a professional expense manager designed to help you track daily spending. Features include QR code scanning, manual entry, and detailed analytics to keep your finances in check.")
                  ]
                );
              }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Logout", style: TextStyle(color: Colors.red)),
                onTap: () async {
                  await context.read<AppState>().clearSession();
                  Navigator.pushAndRemoveUntil(
                    context, 
                    MaterialPageRoute(builder: (c) => const AuthLandingPage()), 
                    (route) => false
                  );
                },
              )
            ],
          ),
        )
        ],
      ),
    );
  }
Widget _tile(IconData i, String t, Color color, {VoidCallback? onTap}) {
  return ListTile(
    leading: CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(i, color: color),
    ),
    title: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    onTap: onTap, // Now the tile can be clicked
  );
}
}