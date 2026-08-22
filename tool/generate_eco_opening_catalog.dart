import 'dart:convert';
import 'dart:io';

const _defaultInput = 'assets/data/eco-365chess.csv';
const _defaultOutput = 'lib/utils/eco_opening_catalog_data.g.dart';

void main(List<String> arguments) {
  final inputPath = arguments.isEmpty ? _defaultInput : arguments.first;
  final outputPath =
      arguments.length < 2 ? _defaultOutput : arguments.elementAt(1);
  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('ECO source not found: $inputPath');
    exitCode = 64;
    return;
  }

  final source = input.readAsStringSync();
  final rows = _parseCsv(source);
  if (rows.isEmpty || rows.first.join(',') != 'eco,name,moves') {
    stderr.writeln('Expected the header eco,name,moves in $inputPath');
    exitCode = 65;
    return;
  }

  final records = rows
      .skip(1)
      .where((row) => row.any((cell) => cell.isNotEmpty));
  final exactCodes = <String>{};
  var recordCount = 0;
  final buffer =
      StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
        ..writeln('//')
        ..writeln('// Source: $inputPath')
        ..writeln('// Source fingerprint: ${sourceFingerprint(source)}')
        ..writeln("part of 'eco_openings.dart';")
        ..writeln()
        ..writeln('const List<EcoOpeningRecord> _ecoOpeningCatalog = [');

  for (final row in records) {
    if (row.length != 3 || row.any((cell) => cell.trim().isEmpty)) {
      stderr.writeln('Invalid ECO row ${recordCount + 2}: $row');
      exitCode = 65;
      return;
    }
    final code = row[0].trim().toUpperCase();
    if (RegExp(r'^[A-E][0-9]{2}$').hasMatch(code)) exactCodes.add(code);
    buffer
      ..writeln('  EcoOpeningRecord(')
      ..writeln('    code: ${_dartString(code)},')
      ..writeln('    name: ${_dartString(row[1].trim())},')
      ..writeln('    moves: ${_dartString(row[2].trim())},')
      ..writeln('  ),');
    recordCount++;
  }
  buffer.writeln('];');

  if (exactCodes.length != 500) {
    stderr.writeln(
      'Expected all 500 exact A00-E99 codes, found ${exactCodes.length}.',
    );
    exitCode = 65;
    return;
  }

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(buffer.toString());
  stdout.writeln('Generated $recordCount ECO records in $outputPath');
}

String _dartString(String value) {
  // JSON string literals are valid Dart string literals. Escape interpolation
  // as a final step so an opening name can never become generated Dart code.
  return jsonEncode(value).replaceAll(r'$', r'\$');
}

List<List<String>> _parseCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;

  void finishField() {
    row.add(field.toString());
    field = StringBuffer();
  }

  void finishRow() {
    finishField();
    rows.add(row);
    row = <String>[];
  }

  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (quoted) {
      if (character == '"') {
        if (index + 1 < source.length && source[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        field.write(character);
      }
      continue;
    }

    switch (character) {
      case '"':
        quoted = true;
      case ',':
        finishField();
      case '\n':
        finishRow();
      case '\r':
        if (index + 1 >= source.length || source[index + 1] != '\n') {
          finishRow();
        }
      default:
        field.write(character);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote');
  if (field.isNotEmpty || row.isNotEmpty) finishRow();
  return rows;
}

/// A deterministic, dependency-free fingerprint for the generated-file
/// header. The repository's source CSV remains the authority; this catches a
/// stale generated catalog without adding a crypto package to this tiny tool.
String sourceFingerprint(String source) {
  var first = 0xcbf29ce484222325;
  var second = 0x84222325cbf29ce4;
  for (final byte in utf8.encode(source)) {
    first = ((first ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
    second = ((second ^ (byte + 17)) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return '${first.toRadixString(16).padLeft(16, '0')}'
      '${second.toRadixString(16).padLeft(16, '0')}';
}
