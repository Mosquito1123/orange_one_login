import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'carrier_codec.dart';
import 'cmcc_auth_client.dart';

/// 中国联通一键登录换号。产品文档入口是 <https://kaidian.10010.com/docInside>。
///
/// 客户端 SDK（`com.unicom.online.account`）只负责拿 `accessToken`。
/// 服务端用 appId 和 appSecret 把 token 换成手机号。签名是
/// `MD5(appId + accessToken + timeStamp + appSecret)`，32 位大写。
///
/// 开店平台给的路径如果和 [defaultEndpoint] 不一致，构造时传入 [endpoint]。
/// appSecret 放在业务服务端，并在联通侧配置出口 IP。
class CuccAuthClient {
  CuccAuthClient({
    required this.appId,
    required this.appSecret,
    http.Client? httpClient,
    Uri? endpoint,
  })  : endpoint = endpoint ?? defaultEndpoint,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String appId;
  final String appSecret;
  final Uri endpoint;
  final http.Client _http;
  final bool _ownsClient;

  static final defaultEndpoint = Uri.parse(
    'https://opencloud.wostore.cn/openapi/netauth/tokenValidate',
  );

  Future<CarrierPhone> exchangeAccessToken(
    String accessToken, {
    DateTime? now,
  }) async {
    final timeStamp = carrierTimestamp17(now ?? DateTime.now());
    final sign = md5Upper('$appId$accessToken$timeStamp$appSecret');
    final response = await _http.post(
      endpoint,
      headers: {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'version': '1.0',
        'appId': appId,
        'accessToken': accessToken,
        'timeStamp': timeStamp,
        'sign': sign,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneClickException(
        OneClickCode.badServer,
        '联通接口 HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw OneClickException(OneClickCode.badServer, '联通响应不是 JSON 对象');
    }
    final code = '${decoded['code'] ?? decoded['resultCode'] ?? ''}';
    final data = decoded['data'];
    final mobile = data is Map ? '${data['mobile'] ?? data['msisdn'] ?? ''}' : '';
    if (code != '0' && code != '0000' && code != '103000') {
      throw OneClickException(
        OneClickCode.fetchTokenError,
        '联通换号失败 $code ${decoded['msg'] ?? decoded['message'] ?? ''}'.trim(),
      );
    }
    if (mobile.isEmpty) {
      throw OneClickException(OneClickCode.fetchTokenError, '联通响应没有手机号');
    }
    return CarrierPhone(
      mobile: mobile,
      operator: MobileOperator.cucc,
      rawCode: code,
      message: '${decoded['msg'] ?? decoded['message'] ?? 'success'}',
    );
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
