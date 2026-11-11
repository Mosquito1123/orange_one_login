import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'carrier_codec.dart';
import 'cmcc_auth_client.dart';

/// 中国电信天翼账号免密登录换号。
///
/// 文档：<https://id.dlife.cn/api?initialSrc=/html/api_detail_391.html>
/// 以及同平台的 `sdkcodeinfo`：
/// `POST https://open.e.189.cn/auth/sdkcodeinfo.do`
/// `application/x-www-form-urlencoded`。
///
/// `params = XXTea(accessCode=...&authCode=..., appSecret)`，输出大写十六进制。
/// `sign = SHA1withRSA(appId + format + params + timeStamp)`，私钥是在天翼平台登记的那把。
/// 成功时 `result` 为 `0`，`data` 用同一把私钥做 PKCS1 解密，明文里有 `mobile`。
class CtccAuthClient {
  CtccAuthClient({
    required this.appId,
    required this.appSecret,
    required String rsaPrivateKeyPem,
    http.Client? httpClient,
    Uri? endpoint,
  })  : endpoint = endpoint ?? defaultEndpoint,
        _privateKey = parsePkcs8RsaPrivateKey(rsaPrivateKeyPem),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String appId;
  final String appSecret;
  final Uri endpoint;
  final RSAPrivateKey _privateKey;
  final http.Client _http;
  final bool _ownsClient;

  static final defaultEndpoint = Uri.parse('https://open.e.189.cn/auth/sdkcodeinfo.do');

  Future<CarrierPhone> exchangeSdkCode({
    required String accessCode,
    required String authCode,
    DateTime? now,
  }) async {
    const format = 'json';
    final timeStamp = (now ?? DateTime.now()).millisecondsSinceEpoch.toString();
    final params = xxteaEncryptHex('accessCode=$accessCode&authCode=$authCode', appSecret);
    final sign = rsaSha1SignHex(_privateKey, '$appId$format$params$timeStamp');
    final response = await _http.post(
      endpoint,
      headers: {'content-type': 'application/x-www-form-urlencoded; charset=utf-8'},
      body: {
        'appId': appId,
        'timeStamp': timeStamp,
        'format': format,
        'params': params,
        'sign': sign,
      }.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneClickException(
        OneClickCode.badServer,
        '电信接口 HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw OneClickException(OneClickCode.badServer, '电信响应不是 JSON 对象');
    }
    final result = '${decoded['result'] ?? ''}';
    if (result != '0' && result != '10000') {
      throw OneClickException(
        OneClickCode.fetchTokenError,
        '电信换号失败 $result ${decoded['msg'] ?? ''}'.trim(),
      );
    }
    final data = '${decoded['data'] ?? ''}';
    if (data.isEmpty) {
      throw OneClickException(OneClickCode.fetchTokenError, '电信响应没有 data');
    }
    final plain = rsaPkcs1DecryptUtf8(_privateKey, data);
    final payload = jsonDecode(plain);
    if (payload is! Map) {
      throw OneClickException(OneClickCode.fetchTokenError, '电信 data 解密后不是 JSON');
    }
    final mobile = '${payload['mobile'] ?? ''}';
    if (mobile.isEmpty) {
      throw OneClickException(OneClickCode.fetchTokenError, '电信 data 没有 mobile');
    }
    return CarrierPhone(
      mobile: mobile,
      operator: MobileOperator.ctcc,
      rawCode: result,
      message: '${decoded['msg'] ?? '操作成功'}',
    );
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
