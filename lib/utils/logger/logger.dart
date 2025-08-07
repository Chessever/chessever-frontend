// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

final loggerProvider = Provider(_LoggerController.new);

//
class _LoggerController {
  _LoggerController(this._ref);
  // ignore: unused_field
  final Ref _ref;

  final logger = Logger();

  void logError(Object error, [StackTrace? stackTrace]) async {
    logger.e(error, stackTrace: stackTrace ?? StackTrace.current);
  }

  void logInfo(Object info) {
    logger.i(info);
  }
}
