import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'carrier_codec.dart';

/// 中国移动号码认证，文档在 <https://dev.10086.cn/numIdentific>。
///
/// 一键登录换号走官方服务端接口
/// `POST https://www.cmpassport.com/unisdk/rsapi/loginTokenValidate`。
/// `sign = MD5(appid + version + msgid + systemtime + strictcheck + token + appSecret)`，32 位大写。
/// 成功码 `103000`，`msisdn` 是手机号。
///
/// 本机号码校验走 `POST https://www.cmpassport.com/openapi/rs/tokenValidate`。
/// 这两个接口都要在移动开发者社区配置出口 IP，密钥只能放在业务服务端。
class CmccAuthClient {
  CmccAuthClient({
    required this.appId,
    required this.appSecret,
    this.appKey,
    http.Client? httpClient,
    Uri? loginEndpoint,
    Uri? verifyEndpoint,
    Random? random,
  })  : loginEndpoint = loginEndpoint ?? defaultLoginEndpoint,
        verifyEndpoint = verifyEndpoint ?? defaultVerifyEndpoint,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _random = random ?? Random.secure();

  final String appId;
  final String appSecret;

  /// 本机号码校验的 HMAC 密钥。不填时用 [appSecret]。
  final String? appKey;
  final Uri loginEndpoint;
  final Uri verifyEndpoint;
  final http.Client _http;
  final bool _ownsClient;
  final Random _random;

  static final defaultLoginEndpoint = Uri.parse(
    'https://www.cmpassport.com/unisdk/rsapi/loginTokenValidate',
  );
  static final defaultVerifyEndpoint = Uri.parse(
    'https://www.cmpassport.com/openapi/rs/tokenValidate',
  );

  static const successCode = '103000';
  static const sameNumberCode = '000';

  Future<CarrierPhone> exchangeLoginToken(
    String token, {
    DateTime? now,
    String strictCheck = '0',
  }) async {
    const version = '2.0';
    final msgid = _msgid();
    final systemtime = carrierTimestamp17(now ?? DateTime.now());
    final sign = md5Upper('$appId$version$msgid$systemtime$strictCheck$token$appSecret');
    final response = await _http.post(
      loginEndpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'encryptionalgorithm': '',
        'expandparams': '',
        'appid': appId,
        'sign': sign,
        'strictcheck': strictCheck,
        'msgid': msgid,
        'systemtime': systemtime,
        'version': version,
        'token': token,
      }),
    );
    final body = _json(response);
    final code = '${body['resultCode'] ?? ''}';
    if (code != successCode) {
      throw OneClickException(
        OneClickCode.fetchTokenError,
        '移动换号失败 $code ${body['desc'] ?? body['resultDesc'] ?? ''}'.trim(),
      );
    }
    final mobile = '${body['msisdn'] ?? ''}';
    if (mobile.isEmpty) {
      throw OneClickException(OneClickCode.fetchTokenError, '移动响应没有 msisdn');
    }
    return CarrierPhone(
      mobile: mobile,
      operator: MobileOperator.cmcc,
      rawCode: code,
      message: '返回成功',
      taskId: '${body['taskId'] ?? ''}',
    );
  }

  /// 本机号码校验。`000` 是本机号码，`001` 不是。
  Future<CmccNumberCheck> verifyLocalNumber({
    required String token,
    required String phone,
    DateTime? now,
    String openType = '1',
  }) async {
    const version = '1.0';
    final key = appKey ?? appSecret;
    final timestamp = carrierTimestamp17(now ?? DateTime.now());
    final msgId = _msgid();
    final phoneNum = sha256Upper('$phone$key$timestamp');
    final sign = hmacSha256Upper('$appId$msgId$phoneNum$timestamp$token$version', key);
    final response = await _http.post(
      verifyEndpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'header': {
          'appId': appId,
          'timestamp': timestamp,
          'version': version,
          'msgId': msgId,
        },
        'body': {
          'openType': openType,
          'requesterType': '0',
          'token': token,
          'phoneNum': phoneNum,
          'sign': sign,
        },
      }),
    );
    final decoded = _json(response);
    final header = decoded['header'];
    final body = decoded['body'];
    final code = header is Map ? '${header['resultCode'] ?? ''}' : '';
    final desc = body is Map ? '${body['resultDesc'] ?? ''}' : '';
    return CmccNumberCheck(code: code, description: desc, sameNumber: code == sameNumberCode);
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneClickException(
        OneClickCode.badServer,
        '移动接口 HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw OneClickException(OneClickCode.badServer, '移动响应不是 JSON 对象');
    }
    return decoded.cast<String, dynamic>();
  }

  String _msgid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}

class CarrierPhone {
  const CarrierPhone({
    required this.mobile,
    required this.operator,
    required this.rawCode,
    required this.message,
    this.taskId = '',
  });

  final String mobile;
  final MobileOperator operator;
  final String rawCode;
  final String message;
  final String taskId;

  String get masked => maskMobile(mobile);
}

class CmccNumberCheck {
  const CmccNumberCheck({
    required this.code,
    required this.description,
    required this.sameNumber,
  });

  final String code;
  final String description;
  final bool sameNumber;
}
