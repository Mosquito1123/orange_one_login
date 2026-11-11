import '../domain/models.dart';

/// 运营商网关。
///
/// 正式环境换成自家的号码认证通道（或任何符合该接口的实现）。
/// 开源包自带 [DemoCarrierGateway]，只用于开发和测试，不会访问真实运营商。
abstract class CarrierAuthGateway {
  Future<void> setup({
    required String appKey,
    required String channel,
    required Duration timeout,
  });

  Future<VerifyEnvironment> checkVerifyEnable();

  Future<PreLoginTicket> preLogin({required Duration timeout});

  PreLoginTicket? get cachedPreLogin;

  void clearPreLogin();

  Future<CarrierToken> getToken({required Duration timeout});

  /// 用户在授权页确认后取 loginToken。有效期由实现方决定，演示网关为 1 分钟。
  Future<CarrierToken> authorize({required Duration timeout});

  Future<SmsChallenge> requestSmsCode({
    required String phone,
    String? signId,
    String? templateId,
    required Duration minInterval,
  });
}
