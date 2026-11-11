import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'demo_carrier_gateway.dart';

/// 把运营商 loginToken 换成业务自己的登录态。
abstract class SessionExchanger {
  Future<AppSession> exchange(
    CarrierToken token, {
    required String maskedNumber,
  });
}

/// 不访问网络。过期 token 会被拒绝，适合示例和单测。
class LocalSessionExchanger implements SessionExchanger {
  LocalSessionExchanger({OneClickClock? clock}) : _clock = clock ?? DateTime.now;

  final OneClickClock _clock;

  @override
  Future<AppSession> exchange(
    CarrierToken token, {
    required String maskedNumber,
  }) async {
    if (token.kind != TokenKind.login) {
      throw OneClickException(OneClickCode.parameterInvalid, '需要 loginToken');
    }
    if (!token.isValidAt(_clock())) {
      throw OneClickException(OneClickCode.tokenExpired);
    }
    return AppSession(
      sessionId: 'sess-${token.token.hashCode.toUnsigned(32).toRadixString(16)}',
      maskedNumber: maskedNumber,
      operator: token.operator,
      expiresAt: _clock().toUtc().add(const Duration(hours: 12)),
    );
  }
}

/// `POST` JSON：`loginToken`、`operator`、`maskedNumber`。
///
/// 成功响应需要 `sessionId`，可选 `maskedNumber`、`operator`、`expiresAt` 或 `expiresIn`（秒）。
class HttpSessionExchanger implements SessionExchanger {
  HttpSessionExchanger({
    required this.endpoint,
    http.Client? httpClient,
    Map<String, String>? headers,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _headers = headers ?? const {};

  final Uri endpoint;
  final http.Client _http;
  final bool _ownsClient;
  final Map<String, String> _headers;

  @override
  Future<AppSession> exchange(
    CarrierToken token, {
    required String maskedNumber,
  }) async {
    if (token.kind != TokenKind.login || !token.token.startsWith('ocl.') && token.token.isEmpty) {
      throw OneClickException(OneClickCode.parameterInvalid, 'loginToken 为空');
    }
    final response = await _http.post(
      endpoint,
      headers: {
        'content-type': 'application/json',
        ..._headers,
      },
      body: jsonEncode({
        'loginToken': token.token,
        'operator': token.operator.code,
        'maskedNumber': maskedNumber,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneClickException(
        OneClickCode.badServer,
        '会话交换失败 HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw OneClickException(OneClickCode.badServer, '会话响应不是 JSON 对象');
    }
    final session = AppSession.fromJson(decoded.cast<String, dynamic>());
    if (session.sessionId.isEmpty) {
      throw OneClickException(OneClickCode.badServer, '会话响应缺少 sessionId');
    }
    return AppSession(
      sessionId: session.sessionId,
      maskedNumber: session.maskedNumber.isEmpty ? maskedNumber : session.maskedNumber,
      operator: session.operator == MobileOperator.unknown
          ? token.operator
          : session.operator,
      expiresAt: session.expiresAt,
    );
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
