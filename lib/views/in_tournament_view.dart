import 'package:chessever2/repository/models/tournament.dart';

import 'standings_view.dart';
import 'package:flutter/material.dart';
import 'game_list_view.dart';

/// This widget shows the tournament detail with tabs for About, Games, and Standings
class InTournamentView extends StatelessWidget {
  final Tournament tournament;

  const InTournamentView({super.key, required this.tournament});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tournament.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'About'),
              Tab(text: 'Games'),
              Tab(text: 'Standings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // About tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Replace with your actual image source or widget
                  Image.network(tournament.imageUrl),
                  const SizedBox(height: 16),
                  Text(
                    tournament.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // Games tab
            GameListView(tournament: tournament),

            // Standings tab uses its own view
            StandingsView(players: tournament.players),
          ],
        ),
      ),
    );
  }
}
