abstract class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(String msg) : super(msg);
}

class RateLimitException extends ApiException {
  RateLimitException(String msg) : super(msg);
}

class NotFoundException extends ApiException {
  NotFoundException(String msg) : super(msg);
}

class ParsingException extends ApiException {
  ParsingException(String msg) : super(msg);
}

class GenericApiException extends ApiException {
  GenericApiException(String message) : super(message);
}
