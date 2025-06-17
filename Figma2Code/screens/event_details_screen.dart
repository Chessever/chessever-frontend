import 'package:flutter/material.dart';

class EventDetailsScreen extends StatelessWidget {
  final String eventName;
  final String logoUrl;
  final String description;
  final String players;
  final String timeControl;
  final String date;
  final String location;
  final String website;

  const EventDetailsScreen({
    Key? key,
    required this.eventName,
    required this.logoUrl,
    required this.description,
    required this.players,
    required this.timeControl,
    required this.date,
    required this.location,
    required this.website,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E), // Figma background
      body: SafeArea(
        child: Container(
          width: 393, // Figma width
          height: 852, // Figma height
          decoration: BoxDecoration(
            color: const Color(0xFF0C0C0E),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              eventName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/Flag-of-Norway.png',
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover, // Use cover for best fill and cropping
                        alignment: Alignment.center, // Center the flag
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 160,
                            width: double.infinity,
                            color: Colors.grey[800],
                            child: Center(
                              child: Text(
                                'Flag image not found',
                                style: TextStyle(color: Colors.white54, fontSize: 16),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        SizedBox(height: 18),
                        Text('Players', style: TextStyle(color: Colors.white60, fontSize: 15)),
                        Text(players, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                        SizedBox(height: 14),
                        Text('Time Control', style: TextStyle(color: Colors.white60, fontSize: 15)),
                        Text(timeControl, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                        SizedBox(height: 14),
                        Text('Date', style: TextStyle(color: Colors.white60, fontSize: 15)),
                        Text(date, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                        SizedBox(height: 14),
                        Text('Location', style: TextStyle(color: Colors.white60, fontSize: 15)),
                        Text(location, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                        SizedBox(height: 18),
                        Row(
                          children: [
                            Icon(Icons.language, color: Color(0xFFEDEBCB)),
                            SizedBox(width: 8),
                            Text(website, style: TextStyle(color: Color(0xFFEDEBCB), fontSize: 16, decoration: TextDecoration.underline)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Container(
                    height: 5,
                    margin: EdgeInsets.only(bottom: 8),
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
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
