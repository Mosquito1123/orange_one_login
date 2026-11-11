import 'one_click_code.dart';

class OneClickException implements Exception {
  OneClickException(this.code, [String? message])
      : message = message ?? code.defaultMessage;

  final OneClickCode code;
  final String message;

  @override
  String toString() => 'OneClickException(${code.value}): $message';
}
