import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:libcompress/libcompress.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';

const kPrepImportMaxBytes = 64 * 1024 * 1024;

/// Mirrors desktop's supported PGN databases with a mobile memory bound.
String decodePrepPgn((String, Uint8List) input) {
  final name = input.$1.toLowerCase();
  final bytes = input.$2;
  if (bytes.length > kPrepImportMaxBytes) {
    throw const PrepException('Choose a PGN file smaller than 64 MB.');
  }
  try {
    final List<int> decoded;
    if (name.endsWith('.bz2')) {
      final output = _BoundedOutput(kPrepImportMaxBytes);
      if (!BZip2Decoder().decodeStream(
        InputMemoryStream(bytes),
        output,
        verify: true,
      )) {
        throw const FormatException('Invalid bzip2 PGN');
      }
      decoded = output.getBytes();
    } else if (name.endsWith('.zst')) {
      decoded = ZstdCodec(
        maxDecompressedSize: kPrepImportMaxBytes,
      ).decompress(bytes);
    } else {
      decoded = bytes;
    }
    return utf8.decode(decoded, allowMalformed: true);
  } on PrepException {
    rethrow;
  } catch (_) {
    throw PrepException(
      'Could not decode ${input.$1}. Use a valid PGN database up to 64 MB when uncompressed.',
    );
  }
}

class _BoundedOutput extends OutputMemoryStream {
  _BoundedOutput(this.maxBytes);
  final int maxBytes;

  void _check(int additional) {
    if (length + additional > maxBytes) {
      throw const PrepException('The uncompressed PGN is larger than 64 MB.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}
