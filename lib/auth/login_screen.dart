import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  Future<void> login() async {
    final String email = emailController.text.trim();
    final String password = passwordController.text;

    // --------------------------------------------------
    // Validate fields
    // --------------------------------------------------
    if (email.isEmpty || password.isEmpty) {
      showMessage('Please enter email and password.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // --------------------------------------------------
      // 1. Login with Firebase Authentication
      // --------------------------------------------------
      final UserCredential credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;

      if (user == null) {
        throw Exception('Unable to login.');
      }

      // --------------------------------------------------
      // 2. Get user document from Firestore
      // --------------------------------------------------
      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      // --------------------------------------------------
      // 3. Check whether Firestore profile exists
      // --------------------------------------------------
      if (!userDocument.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        showMessage(
          'User profile not found in Firestore.',
        );

        return;
      }

      // --------------------------------------------------
      // 4. Get user data
      // --------------------------------------------------
      final Map<String, dynamic>? userData =
          userDocument.data();

      final String role =
          userData?['role']?.toString() ?? 'user';

      if (!mounted) return;

      // --------------------------------------------------
      // 5. Navigate according to role
      // --------------------------------------------------
      if (role == 'admin') {
        Navigator.pushReplacementNamed(
          context,
          '/admin-dashboard',
        );
      } else {
        Navigator.pushReplacementNamed(
          context,
          '/home',
        );
      }
    }

    // --------------------------------------------------
    // Firebase Authentication Errors
    // --------------------------------------------------
    on FirebaseAuthException catch (e) {
      String message = 'Login failed.';

      if (e.code == 'invalid-credential') {
        message = 'Invalid email or password.';
      } else if (e.code == 'user-not-found') {
        message = 'No account found with this email.';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid email.';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled.';
      } else if (e.code == 'too-many-requests') {
        message =
            'Too many attempts. Please try again later.';
      } else if (e.code == 'network-request-failed') {
        message =
            'Network error. Please check your internet connection.';
      }

      if (mounted) {
        showMessage(message);
      }
    }

    // --------------------------------------------------
    // Other Errors
    // --------------------------------------------------
    catch (e) {
      debugPrint('LOGIN ERROR: $e');

      if (mounted) {
        showMessage(
          'Error: $e',
        );
      }
    }

    // --------------------------------------------------
    // Stop loading
    // --------------------------------------------------
    finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // Show SnackBar Message
  // --------------------------------------------------
  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // --------------------------------------------------
  // Dispose Controllers
  // --------------------------------------------------
  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [

                  // --------------------------------------------------
                  // Logo
                  // --------------------------------------------------
                  const Icon(
                    Icons.school_rounded,
                    size: 80,
                  ),

                  const SizedBox(height: 20),

                  // --------------------------------------------------
                  // App Name
                  // --------------------------------------------------
                  const Text(
                    'ForwardAPT',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // --------------------------------------------------
                  // Subtitle
                  // --------------------------------------------------
                  const Text(
                    'Aptitude practice made simple.',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --------------------------------------------------
                  // Email
                  // --------------------------------------------------
                  TextField(
                    controller: emailController,

                    keyboardType:
                        TextInputType.emailAddress,

                    textInputAction:
                        TextInputAction.next,

                    decoration:
                        const InputDecoration(
                      labelText: 'Email',

                      hintText:
                          'Enter your email',

                      prefixIcon: Icon(
                        Icons.email_outlined,
                      ),

                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --------------------------------------------------
                  // Password
                  // --------------------------------------------------
                  TextField(
                    controller: passwordController,

                    obscureText: obscurePassword,

                    textInputAction:
                        TextInputAction.done,

                    onSubmitted: (_) {
                      if (!isLoading) {
                        login();
                      }
                    },

                    decoration: InputDecoration(
                      labelText: 'Password',

                      hintText:
                          'Enter your password',

                      prefixIcon: const Icon(
                        Icons.lock_outline,
                      ),

                      border:
                          const OutlineInputBorder(),

                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePassword =
                                !obscurePassword;
                          });
                        },

                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --------------------------------------------------
                  // Login Button
                  // --------------------------------------------------
                  SizedBox(
                    height: 52,

                    child: FilledButton(
                      onPressed:
                          isLoading ? null : login,

                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,

                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )

                          : const Text(
                              'Login',

                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --------------------------------------------------
                  // Register Button
                  // --------------------------------------------------
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            Navigator
                                .pushReplacementNamed(
                              context,
                              '/register',
                            );
                          },

                    child: const Text(
                      "Don't have an account? Register",
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}