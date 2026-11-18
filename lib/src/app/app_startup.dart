import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Shown while the stored session is restored; the router moves on once
/// the auth state is known.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.monitor_heart_outlined,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                'MedVitals Link',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Your health, continuously monitored.',
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 40,
                height: 40,
                child:
                    CircularProgressIndicator(color: c.brand, strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
