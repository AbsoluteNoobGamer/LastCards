import 'dart:async';

import 'package:flutter/material.dart';

import 'router/app_routes.dart';

/// Full-screen splash shown when the app loads.
/// Displays the Last Cards branding, then navigates to [AuthGate].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _kDuration = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    Future.delayed(_kDuration, _goToStart);
  }

  void _goToStart() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.start);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/splash.png'),
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
