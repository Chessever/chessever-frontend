import 'package:flutter/material.dart';
import 'tournament_list_screen.dart';

class UsernamePasswordSignInScreen extends StatefulWidget {
  const UsernamePasswordSignInScreen({Key? key}) : super(key: key);

  @override
  State<UsernamePasswordSignInScreen> createState() => _UsernamePasswordSignInScreenState();
}

class _UsernamePasswordSignInScreenState extends State<UsernamePasswordSignInScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  void _signIn() {
    setState(() {
      _error = null;
    });
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _error = 'Username and password are required.';
      });
      return;
    }
    // Simulate successful sign in
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TournamentListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Color(0xFF232325),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  SizedBox(height: 18),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Color(0xFF232325),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    SizedBox(height: 14),
                    Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 15)),
                  ],
                  SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(290, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _signIn,
                    child: Text('Sign In', style: TextStyle(fontWeight: FontWeight.w600)),
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
