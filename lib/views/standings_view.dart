import 'package:flutter/material.dart';

class StandingsView extends StatelessWidget {
  final List<String> players;

  const StandingsView({Key? key, required this.players}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: players.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return ListTile(
          leading: Text('${index + 1}'),
          title: Text(players[index]),
        );
      },
    );
  }
}