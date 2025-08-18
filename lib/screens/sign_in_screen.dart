import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:flutter/material.dart';
// import 'tournament_list_screen.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  void _continue(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GroupEventScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              const Spacer(),
              // Your logo and content here
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(290, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.apple, color: Colors.black),
                label: const Text("Continue with Apple"),
                onPressed: () => _continue(context),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(290, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.android, color: Colors.green),
                label: const Text("Continue with Google"),
                onPressed: () => _continue(context),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
