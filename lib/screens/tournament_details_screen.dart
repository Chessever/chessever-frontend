import 'package:flutter/material.dart';

class TournamentDetailsScreen extends StatelessWidget {
  const TournamentDetailsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Example tournaments data, you may want to pass this as arguments
    final tournament = {
      'name': 'Norway Chess 2025',
      'status': 'LIVE',
      'date': 'Feb 27 - 29, 2025',
      'country': 'Netherlands',
      'players': 12,
      'elo': 2714,
      'description':
          'The most prestigious annual chess tournaments in the world. Watch top grandmasters compete for glory!',
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AppBar Row
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 28, right: 16, bottom: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Text(
                  tournament['name'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                if (tournament['status'] == 'LIVE')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(0xFF20B3D6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Card with tournament details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF232325),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date and country
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.white60, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        tournament['date'] as String,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(width: 14),
                      const Icon(Icons.place, color: Colors.white60, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        tournament['country'] as String,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Players and ELO
                  Row(
                    children: [
                      const Icon(Icons.people_alt, color: Colors.white60, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${tournament['players']} players',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(width: 14),
                      const Icon(Icons.star, color: Colors.white60, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'ELO ${tournament['elo']}',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Description
                  Text(
                    tournament['description'] as String,
                    style: const TextStyle(color: Colors.white70, fontSize: 15.5),
                  ),
                ],
              ),
            ),
          ),
          // Spacer for pushing button to the bottom
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF20B3D6),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Watch Live',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
