
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),

      // Authentication decides the first screen.
      home: const AuthGate(),

      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const Dashboard(),
        '/admin-dashboard': (context) => const AdminDashboard(),
      },
    );
  }
}

// =====================================================
// AUTHENTICATION GATE
// =====================================================

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final Map<String, Future<String?>> _roleFutures = {};

  Future<String?> getUserRole(String uid) {
    return _roleFutures.putIfAbsent(uid, () async {
      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!document.exists) {
        return null;
      }

      return document.data()?['role']?.toString() ?? 'user';
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, authSnapshot) {
        // Waiting for Firebase authentication.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        // No authenticated user.
        final User? user = authSnapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        // Authenticated user: retrieve their Firestore role.
        return FutureBuilder<String?>(
          future: getUserRole(user.uid),

          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const LoadingScreen();
            }

            if (roleSnapshot.hasError) {
              return ErrorScreen(
                onRetry: () {
                  setState(() {
                    _roleFutures.remove(user.uid);
                  });
                },
              );
            }

            final String? role = roleSnapshot.data;

            // Invalid or missing user profile.
            if (role == null) {
              FirebaseAuth.instance.signOut();
              return const LoadingScreen();
            }

            // Open the correct dashboard.
            if (role == 'admin') {
              return const AdminDashboard();
            }

            return const Dashboard();
          },
        );
      },
    );
  }
}

// =====================================================
// LOADING SCREEN
// =====================================================

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

// =====================================================
// ERROR SCREEN
// =====================================================

class ErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const ErrorScreen({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Unable to load your account.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
