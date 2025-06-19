import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';

class SelectCountryScreen extends StatelessWidget {
  const SelectCountryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Hero(tag: 'blur', child: BlurBackground()),
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'Select Your Country',
                      style: AppTypography.textSmBold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 48),
                    height: 40,
                    width: MediaQuery.of(context).size.width,
                    child: CountryDropdown(
                      onChanged: (_) {
                        Navigator.pushReplacementNamed(context, '/tournament_screen');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
