import 'package:flutter/material.dart';

class TournamentController {
  // Dummy data for tournaments
  final Map<String, List<Map<String, dynamic>>> _tournaments = {
    'live': [
      {
        'title': 'Norway Chess 2025',
        'dates': 'Feb 27-29, 2025',
        'location': 'Netherlands',
        'playerCount': 12,
        'elo': 2714,
      },
      {
        'title': 'World Rapid Championship 2025',
        'dates': 'Dec 10 - 12, 2025',
        'location': 'Russia',
        'playerCount': 16,
        'elo': 2700,
      },
      {
        'title': 'FIDE Grand Prix 2025',
        'dates': 'Mar 5 - 15, 2025',
        'location': 'Germany',
        'playerCount': 14,
        'elo': 2695,
      },
    ],
    'completed': [
      {
        'title': 'Candidates Tournament 2026',
        'dates': 'Apr 18 - May 6, 2025',
        'location': 'Spain',
        'playerCount': 8,
        'elo': 2720,
      },
      {
        'title': 'London Chess Classic 2025',
        'dates': 'Nov 1 - 8, 2025',
        'location': 'UK',
        'playerCount': 10,
        'elo': 2705,
      },
      {
        'title': 'Magnus Carlsen Invitational 2025',
        'dates': 'Jul 15 - 20, 2025',
        'location': 'Norway',
        'playerCount': 8,
        'elo': 2730,
      },
      {
        'title': 'Online Chess Championship 2025',
        'dates': 'Jan 15 - 20, 2025',
        'location': 'Global',
        'playerCount': 64,
        'elo': 2680,
      },
      {
        'title': 'Women\'s World Chess Championship 2025',
        'dates': 'May 10 - 25, 2025',
        'location': 'China',
        'playerCount': 10,
        'elo': 2500,
      },
    ],
    'upcoming': [
      {
        'title': 'Magnus Carlsen Invitational 2025',
        'dates': 'Jul 15 - 20, 2025',
        'location': 'Norway',
        'playerCount': 8,
        'elo': 2702,
        'timeUntilStart': 'Starts in 3 days',
      },
      {
        'title': 'Tata Steel Chess 2026',
        'dates': 'Jan 10 - 25, 2026',
        'location': 'Netherlands',
        'playerCount': 14,
        'elo': 2690,
        'timeUntilStart': 'Starts in 2 months',
      },
    ],
  };

  // Methods to fetch tournaments
  List<Map<String, dynamic>> getLiveTournaments() {
    return _tournaments['live'] ?? [];
  }

  List<Map<String, dynamic>> getCompletedTournaments() {
    return _tournaments['completed'] ?? [];
  }

  List<Map<String, dynamic>> getUpcomingTournaments() {
    return _tournaments['upcoming'] ?? [];
  }

  // Method to get all events (live + completed)
  List<Map<String, dynamic>> getAllEvents() {
    final allEvents = [
      ...getLiveTournaments().map((event) => {...event, 'type': 'live'}),
      ...getCompletedTournaments().map(
        (event) => {...event, 'type': 'completed'},
      ),
    ];
    return allEvents;
  }

  // Method for searching tournaments
  List<Map<String, dynamic>> searchTournaments(
    String query,
    bool upcomingOnly,
  ) {
    if (query.isEmpty) {
      return upcomingOnly ? getUpcomingTournaments() : getAllEvents();
    }

    final lowercaseQuery = query.toLowerCase();

    if (upcomingOnly) {
      return getUpcomingTournaments().where((tournament) {
        return tournament['title'].toString().toLowerCase().contains(
              lowercaseQuery,
            ) ||
            tournament['location'].toString().toLowerCase().contains(
              lowercaseQuery,
            );
      }).toList();
    } else {
      return getAllEvents().where((tournament) {
        return tournament['title'].toString().toLowerCase().contains(
              lowercaseQuery,
            ) ||
            tournament['location'].toString().toLowerCase().contains(
              lowercaseQuery,
            );
      }).toList();
    }
  }

  // This method can be replaced later with actual API calls
  Future<void> fetchTournaments() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));
    // In the future, this would fetch data from an API and update _tournaments
  }
}
