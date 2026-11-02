import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

// Authentication
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';

// Student Dashboard
import 'home/dashboard.dart';

// Admin Dashboard
import 'admin/admin_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ForwardAPT());
}

class ForwardAPT extends StatelessWidget {
  const ForwardAPT({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'ForwardAPT',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
        ),

        scaffoldBackgroundColor:
            const Color(0xFFF7F8FC),
      ),

      initialRoute: '/login',

      routes: {
        // Authentication
        '/login': (context) => const LoginScreen(),

        '/register': (context) =>
            const RegisterScreen(),

        // Student Dashboard
        '/home': (context) =>
            const Dashboard(),

        // Admin Dashboard
        '/admin-dashboard': (context) =>
            const AdminDashboard(),
      },
    );
  }
}