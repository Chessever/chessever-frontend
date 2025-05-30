import 'package:flutter/material.dart';

class TournamentListScreen extends StatelessWidget {
  const TournamentListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tournaments = [
      {
        'name': 'Norway Chess 2025',
        'status': 'LIVE',
        'date': 'Feb 27 -29, 2025',
        'country': 'Netherlands',
        'players': 12,
        'elo': 2714,
      },
      {
        'name': 'World Rapid Championship 2025',
        'status': 'LIVE',
        'date': 'Dec 10 - 12, 2025',
        'country': 'Russia',
        'players': 16,
        'elo': 2700,
      },
      {
        'name': 'FIDE Grand Prix 2025',
        'status': 'LIVE',
        'date': 'Mar 5 - 15, 2025',
        'country': 'Germany',
        'players': 14,
        'elo': 2695,
      },
      {
        'name': 'Candidates Tournament 2026',
        'status': 'Completed',
        'date': 'Apr 18 - May 6, 2025',
        'country': 'Spain',
        'players': 8,
        'elo': 2720,
      },
      {
        'name': 'London Chess Classic 2025',
        'status': 'Completed',
        'date': 'Nov 1 - 8, 2025',
        'country': 'UK',
        'players': 10,
        'elo': 2705,
      },
      {
        'name': 'Magnus Carlsen Invitational 2025',
        'status': 'Completed',
        'date': 'Jul 15 - 20, 2025',
        'country': 'Norway',
        'players': 8,
        'elo': 2702,
      },
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Color(0xFF20B3D6),
        unselectedItemColor: Colors.white60,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events),
            label: 'Tournaments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
        currentIndex: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Avatar
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFF20B3D6),
                    child: Text(
                      'TW',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Title
              Text(
                "Tournaments",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 18),
              // Search bar and filter icon
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(0xFF232325),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.search, color: Colors.white60, size: 22),
                          ),
                          Expanded(
                            child: TextField(
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Search tournaments or players',
                                hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(0xFF232325),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.filter_alt, color: Colors.white60, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Tabs
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(0xFF18181A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'All Events',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(0xFF171718),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Upcoming Events',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tournament list
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: tournaments.length,
                itemBuilder: (context, index) {
                  final t = tournaments[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Color(0xFF232325),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        title: Row(
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: t['name'] as String,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (t['status'] == 'LIVE')
                                      TextSpan(
                                        text: '  LIVE',
                                        style: TextStyle(
                                          color: Color(0xFF20B3D6),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    else
                                      TextSpan(
                                        text: '  Completed',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Icon(
                              Icons.star_border,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Text(
                            '${t['date']} • ${t['country']} • ${t['players']} players • ELO ${t['elo']}',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        trailing: index > 2
                            ? Icon(Icons.more_vert, color: Colors.white54, size: 22)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
