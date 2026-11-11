import '../data/session_exchanger.dart';
import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'cmcc_auth_client.dart';
import 'ctcc_auth_client.dart';
import 'cucc_auth_client.dart';

/// 按运营商把 loginToken 换成业务会话。
///
/// 移动、联通、电信的 appSecret 和电信 RSA 私钥都只放在调用方服务端。
/// 客户端只上传 token，不要把这些密钥打进 App。
class ThreeCarrierSessionExchanger implements SessionExchanger {
  ThreeCarrierSessionExchanger({
    this.cmcc,
    this.cucc,
    this.ctcc,
    this.sessionTtl = const Duration(hours: 12),
  });

  final CmccAuthClient? cmcc;
  final CuccAuthClient? cucc;
  final CtccAuthClient? ctcc;
  final Duration sessionTtl;

  @override
  Future<AppSession> exchange(
    CarrierToken token, {
    required String maskedNumber,
  }) async {
    if (token.kind != TokenKind.login) {
      throw OneClickException(OneClickCode.parameterInvalid, '需要 loginToken');
    }
    final phone = await _phone(token);
    return AppSession(
      sessionId: phone.taskId.isNotEmpty
          ? phone.taskId
          : 'sess-${phone.operator.code}-${phone.masked.hashCode.toUnsigned(32).toRadixString(16)}',
      maskedNumber: phone.masked,
      operator: phone.operator,
      expiresAt: DateTime.now().toUtc().add(sessionTtl),
    );
  }

  Future<CarrierPhone> _phone(CarrierToken token) {
    switch (token.operator) {
      case MobileOperator.cmcc:
        final client = cmcc;
        if (client == null) {
          throw OneClickException(OneClickCode.fetchConfigFailed, '未配置中国移动');
        }
        return client.exchangeLoginToken(token.token);
      case MobileOperator.cucc:
        final client = cucc;
        if (client == null) {
          throw OneClickException(OneClickCode.fetchConfigFailed, '未配置中国联通');
        }
        return client.exchangeAccessToken(token.token);
      case MobileOperator.ctcc:
        final client = ctcc;
        if (client == null) {
          throw OneClickException(OneClickCode.fetchConfigFailed, '未配置中国电信');
        }
        final authCode = token.extras['authCode'];
        if (authCode == null || authCode.isEmpty) {
          throw OneClickException(
            OneClickCode.parameterInvalid,
            '电信换号需要 extras.authCode',
          );
        }
        return client.exchangeSdkCode(accessCode: token.token, authCode: authCode);
      case MobileOperator.unknown:
        throw OneClickException(OneClickCode.parameterInvalid, '未知运营商');
    }
  }
}
