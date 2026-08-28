import 'dart:convert';
import 'dart:io';

/// Synchronizes the mobile-only Memorial detail assets from the canonical web
/// profile data without inflating the lightweight startup search catalog.
///
/// Usage:
///   dart run tool/sync_memorial_profile_assets.dart [web-repository-path]
void main(List<String> arguments) {
  final webRoot =
      Directory(
        arguments.isEmpty ? '../chessever_web_frontend' : arguments.first,
      ).absolute;
  final profilesFile = File(
    '${webRoot.path}/src/data/historical-player-profiles.json',
  );
  final aboutFile = File(
    '${webRoot.path}/src/data/historical-player-about.json',
  );
  final catalogFile = File('assets/data/memorial-player-catalog.json');
  final historyOutput = File('assets/data/memorial-player-history.json');
  final aboutOutput = File('assets/data/memorial-player-about.json');

  for (final file in [profilesFile, aboutFile, catalogFile]) {
    if (!file.existsSync()) {
      stderr.writeln('Missing required Memorial source: ${file.path}');
      exitCode = 2;
      return;
    }
  }

  final catalog = jsonDecode(catalogFile.readAsStringSync()) as Map;
  final catalogRows = (catalog['players'] as List? ?? const <dynamic>[])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
  final catalogRouteIds =
      catalogRows
          .map((row) => row['routeId']?.toString())
          .whereType<String>()
          .toSet();

  final profiles = (jsonDecode(profilesFile.readAsStringSync()) as List)
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where((row) => catalogRouteIds.contains(row['routeId']?.toString()))
      .map(
        (row) => <String, dynamic>{
          'routeId': row['routeId'],
          if (row['peakPeriod'] != null) 'peakPeriod': row['peakPeriod'],
          if (row['peakRapidPeriod'] != null)
            'peakRapidPeriod': row['peakRapidPeriod'],
          if (row['peakBlitzPeriod'] != null)
            'peakBlitzPeriod': row['peakBlitzPeriod'],
          if (row['ratingListSpan'] != null)
            'ratingListSpan': row['ratingListSpan'],
          'history': row['history'] ?? const <dynamic>[],
          'sources': row['sources'] ?? const <dynamic>[],
        },
      )
      .toList(growable: false);

  final about = (jsonDecode(aboutFile.readAsStringSync()) as List)
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where((row) => catalogRouteIds.contains(row['routeId']?.toString()))
      .toList(growable: false);

  if (profiles.length != catalogRouteIds.length) {
    stderr.writeln(
      'Refusing incomplete history sync: found ${profiles.length} of '
      '${catalogRouteIds.length} catalog profiles.',
    );
    exitCode = 3;
    return;
  }

  const compactEncoder = JsonEncoder();
  historyOutput.writeAsStringSync(
    compactEncoder.convert(<String, dynamic>{
      'version': 1,
      'count': profiles.length,
      'profiles': profiles,
    }),
  );
  // Preserve the canonical file's reviewed formatting as well as its content.
  // It is already restricted to Memorial catalog route ids above.
  aboutOutput.writeAsStringSync(aboutFile.readAsStringSync());

  stdout.writeln(
    'Synced ${profiles.length} Memorial histories and ${about.length} '
    'authored biographies from ${webRoot.path}.',
  );
}
