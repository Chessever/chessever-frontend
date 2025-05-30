import 'package:flutter/material.dart';

class ResponsiveScreenTemplate extends StatelessWidget {
  const ResponsiveScreenTemplate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          width: size.width,
          height: size.height,
          child: Column(
            children: [
              // Example logo
              SizedBox(height: size.height * 0.1),
              Image.asset(
                'assets/logo.png',
                width: size.width * 0.32, // 32% of screen width
              ),
              // Example title
              SizedBox(height: size.height * 0.05),
              Text(
                'YOUR APP',
                style: TextStyle(
                  fontSize: size.width * 0.09, // Responsive font
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Spacer for flexible layout
              Spacer(),
              // Example button
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: SizedBox(
                  width: double.infinity,
                  height: size.height * 0.065,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: size.width * 0.055,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.04),
            ],
          ),
        ),
      ),
    );
  }
}
