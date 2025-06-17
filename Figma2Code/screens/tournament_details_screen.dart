import 'package:flutter/material.dart';

class TournamentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> tournament;
  final String player;
  final String resultFilter;
  final String colorFilter;

  const TournamentDetailsScreen({
    Key? key,
    required this.tournament,
    required this.player,
    required this.resultFilter,
    required this.colorFilter,
  }) : super(key: key);

  @override
  State<TournamentDetailsScreen> createState() => _TournamentDetailsScreenState();
}

class _TournamentDetailsScreenState extends State<TournamentDetailsScreen> {
  int _selectedTab = 0;
  int _selectedRound = 4;

  // Add mock games data
  final List<Map<String, dynamic>> games = [
    {
      'white': {
        'name': 'Nakamura, Hikaru',
        'elo': 2804,
        'flag': '🇺🇸',
      },
      'black': {
        'name': 'Magnus, Carlsen',
        'elo': 2837,
        'flag': '🇳🇴',
      },
      'time': '01:30',
    },
    // Add more games...
  ];

  @override
  Widget build(BuildContext context) {
    // Find the player key in the results map, safely
    final results = widget.tournament['results'] as Map<String, dynamic>?;

    String? playerKey;
    if (results != null && widget.player.trim().isNotEmpty) {
      try {
        playerKey = results.keys.firstWhere(
          (k) => k.toLowerCase().contains(widget.player.toLowerCase()),
          orElse: () => '',
        );
        if (playerKey.isEmpty) playerKey = null;
      } catch (_) {
        playerKey = null;
      }
    }

    // Filter games for the player based on filters
    List<Map<String, dynamic>> playerGames = [];
    if (playerKey != null && results != null) {
      final game = results[playerKey];
      if (game != null &&
          (widget.resultFilter == 'All Results' || game['result'] == widget.resultFilter) &&
          (widget.colorFilter == 'All Colors' || game['color'] == widget.colorFilter)) {
        playerGames.add({'opponent': playerKey, ...game});
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF101215),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AppBar with back arrow and centered title
            Padding(
              padding: const EdgeInsets.only(left: 0, top: 12, right: 0, bottom: 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.tournament['name']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // To balance the back arrow
                ],
              ),
            ),
            // Tabs (About, Games, Standings)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTabButton("About", 0),
                  const SizedBox(width: 8),
                  _buildTabButton("Games", 1),
                  const SizedBox(width: 8),
                  _buildTabButton("Standings", 2),
                ],
              ),
            ),
            // Content area with IndexedStack
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  // About tab
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        // Add the image here instead
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/norway_chess_2025.png',
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Description
                        Padding(
                          padding: const EdgeInsets.only(top: 18, left: 18, right: 18, bottom: 0),
                          child: Text(
                            widget.tournament['description']?.toString() ??
                                "Norway Chess is an annual closed chess tournament, typically taking place in the May to June time period every year. The first edition took place in the Stavanger area, Norway, from 7 May to 18 May 2013.",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                            ),
                          ),
                        ),
                        // Players
                        Padding(
                          padding: const EdgeInsets.only(top: 22, left: 18, right: 18, bottom: 0),
                          child: Text(
                            "Players",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18, right: 18, bottom: 0),
                          child: Text(
                            (widget.tournament['participants'] as List<dynamic>?)
                                    ?.join(', ') ??
                                "Hikaru, Magnus, Caruana, Giri, Ding",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Time Control
                        Padding(
                          padding: const EdgeInsets.only(top: 22, left: 18, right: 18, bottom: 0),
                          child: Text(
                            "Time Control",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18, right: 18, bottom: 0),
                          child: Text(
                            widget.tournament['timeControl']?.toString() ??
                                "90 min/ 40 moves + 30min + 30sec / move",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Date
                        Padding(
                          padding: const EdgeInsets.only(top: 22, left: 18, right: 18, bottom: 0),
                          child: Text(
                            "Date",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18, right: 18, bottom: 0),
                          child: Text(
                            widget.tournament['date']?.toString() ?? "May 7 - 18, 2025",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Location
                        Padding(
                          padding: const EdgeInsets.only(top: 22, left: 18, right: 18, bottom: 0),
                          child: Text(
                            "Location",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18, right: 18, bottom: 0),
                          child: Row(
                            children: [
                              const Text(
                                "🇳🇴",
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.tournament['country']?.toString() ?? "Stavanger, Norway",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Website link
                        Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.public,
                                  color: Color(0xFFEFEFC2),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Norwaychess.no",
                                  style: const TextStyle(
                                    color: Color(0xFFEFEFC2),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Games tab (new content)
                  Column(
                    children: [
                      // Round selector
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.chevron_left, color: Colors.white),
                              onPressed: () {
                                if (_selectedRound > 1) {
                                  setState(() => _selectedRound--);
                                }
                              },
                            ),
                            Expanded(
                              child: Text(
                                'Round $_selectedRound',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.chevron_right, color: Colors.white),
                              onPressed: () {
                                setState(() => _selectedRound++);
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      // Games list with updated background color
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: games.length,
                          itemBuilder: (context, index) {
                            final game = games[index];
                            return Container(
                              margin: EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Color(0xFFE0E0E0), // Changed from Colors.white to light grey
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                game['white']['name'],
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    game['white']['flag'],
                                                    style: TextStyle(fontSize: 16),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'GM ${game['white']['elo']}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.black),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 16,
                                                height: 16,
                                                color: Colors.white,
                                                margin: EdgeInsets.only(right: 4),
                                              ),
                                              Container(
                                                width: 16,
                                                height: 16,
                                                color: Colors.black,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                game['black']['name'],
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    game['black']['flag'],
                                                    style: TextStyle(fontSize: 16),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'GM ${game['black']['elo']}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF232325),
                                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          game['time'],
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        Text(
                                          game['time'],
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  
                  // Standings tab (placeholder)
                  Center(
                    child: Text(
                      'Standings coming soon...',
                      style: TextStyle(color: Colors.white),
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

  Widget _buildTabButton(String text, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}