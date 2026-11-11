import 'dart:async';

import 'package:flutter/material.dart';

import 'data/carrier_gateway.dart';
import 'data/demo_carrier_gateway.dart';
import 'data/session_exchanger.dart';
import 'domain/models.dart';
import 'domain/one_click_code.dart';
import 'domain/one_click_exception.dart';
import 'ui/auth_controller.dart';
import 'ui/auth_page_theme.dart';
import 'ui/one_click_auth_page.dart';

/// 拉起授权页并在用户完成或取消后返回结果。
typedef AuthPresenter = Future<LoginAuthResult?> Function(AuthPrompt prompt);

/// 一键登录业务客户端。
///
/// 调用顺序和运营商认证产品一致：`setup` → `checkVerifyEnable` →
/// `preLogin` → 授权页确认 → loginToken → 交给 [SessionExchanger] 换成自己的会话。
/// 蜂窝网络不可用或用户点了其他方式时，用 [getSmsCode] 走短信。
class OneClickClient {
  OneClickClient({
    CarrierAuthGateway? gateway,
    SessionExchanger? session,
    AuthPageTheme? theme,
    this.debug = false,
  })  : gateway = gateway ?? DemoCarrierGateway(),
        session = session ?? LocalSessionExchanger(),
        theme = theme ?? AuthPageTheme();

  final CarrierAuthGateway gateway;
  final SessionExchanger session;
  AuthPageTheme theme;
  bool debug;

  final StreamController<AuthPageEvent> _events =
      StreamController<AuthPageEvent>.broadcast();

  Duration _smsInterval = const Duration(seconds: 30);
  AuthPrompt? _prompt;

  Stream<AuthPageEvent> get pageEvents => _events.stream;

  void setDebugMode(bool enabled) => debug = enabled;

  void setAuthorizationTheme(AuthPageTheme value) => theme = value;

  /// 默认 30 秒，合法范围是大于 0 且不超过 5 分钟。
  void setSmsInterval(Duration interval) {
    final ms = interval.inMilliseconds;
    if (ms <= 0 || ms > 300000) {
      throw OneClickException(
        OneClickCode.parameterInvalid,
        '短信间隔必须在 (0, 300000] 毫秒',
      );
    }
    _smsInterval = interval;
  }

  Future<void> setup({
    required String appKey,
    String channel = 'developer-default',
    Duration timeout = const Duration(seconds: 10),
  }) {
    _log('setup channel=$channel');
    return gateway.setup(appKey: appKey, channel: channel, timeout: timeout);
  }

  Future<bool> isInitialized() async {
    if (gateway is DemoCarrierGateway) {
      return (gateway as DemoCarrierGateway).isReady;
    }
    try {
      await gateway.checkVerifyEnable();
      return true;
    } on OneClickException catch (error) {
      return error.code != OneClickCode.notInitialized;
    }
  }

  Future<VerifyEnvironment> checkVerifyEnable() {
    return _guard(
      gateway.checkVerifyEnable,
      (error) => VerifyEnvironment(supported: false, message: error.message),
    );
  }

  Future<PreLoginResult> preLogin({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _guard(() async {
      final ticket = await gateway.preLogin(timeout: timeout);
      return PreLoginResult(
        code: OneClickCode.tokenRequestSuccess,
        message: OneClickCode.tokenRequestSuccess.defaultMessage,
        ticket: ticket,
      );
    }, (error) => PreLoginResult(code: error.code, message: error.message));
  }

  Future<bool> validPreLoginCache() async => gateway.cachedPreLogin != null;

  Future<void> clearPreLoginCache() async => gateway.clearPreLogin();

  Future<TokenResult> getToken({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _guard(() async {
      final token = await gateway.getToken(timeout: timeout);
      return TokenResult(
        code: OneClickCode.tokenRequestSuccess,
        message: token.token,
        token: token,
      );
    }, (error) => TokenResult(code: error.code, message: error.message));
  }

  /// 检查网络并预取号，得到授权页要展示的掩码号码。
  Future<PreLoginResult> prepare({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _guard(() async {
      final env = await gateway.checkVerifyEnable();
      if (!env.supported) {
        throw OneClickException(OneClickCode.networkNotSupported, env.message);
      }
      final cached = gateway.cachedPreLogin;
      final ticket = cached ?? await gateway.preLogin(timeout: timeout);
      _prompt = AuthPrompt(
        maskedNumber: ticket.maskedNumber,
        operator: ticket.operator,
        slogan: ticket.operator.slogan,
        clauses: theme.clauses,
        actions: theme.actions,
      );
      return PreLoginResult(
        code: OneClickCode.tokenRequestSuccess,
        message: ticket.maskedNumber,
        ticket: ticket,
      );
    }, (error) => PreLoginResult(code: error.code, message: error.message));
  }

  /// 授权页确认后调用。失败结果不会抛出，方便界面留在当前页提示。
  Future<LoginAuthResult> completeAuthorization({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _guard(() async {
      final prompt = _prompt;
      if (prompt == null) {
        throw OneClickException(OneClickCode.loginTokenFailed, '请先预取号');
      }
      final token = await gateway.authorize(timeout: timeout);
      return LoginAuthResult(
        code: OneClickCode.loginTokenSuccess,
        message: OneClickCode.loginTokenSuccess.defaultMessage,
        loginToken: token,
        maskedNumber: prompt.maskedNumber,
        operator: token.operator,
      );
    }, (error) {
      final code = error.code == OneClickCode.networkNotSupported
          ? OneClickCode.networkNotSupported
          : OneClickCode.loginTokenFailed;
      return LoginAuthResult(
        code: error.code == OneClickCode.notInitialized ? error.code : code,
        message: error.message,
        operator: _prompt?.operator,
        maskedNumber: _prompt?.maskedNumber,
      );
    });
  }

  Future<LoginAuthResult> loginAuth(
    BuildContext context, {
    bool autoDismiss = true,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return loginAuthWith(
      (prompt) => _pushAuthPage(context, prompt, autoDismiss: autoDismiss),
      timeout: timeout,
    );
  }

  Future<LoginAuthResult> loginAuthWith(
    AuthPresenter presenter, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final prepared = await prepare(timeout: timeout);
    if (!prepared.ok || _prompt == null) {
      return LoginAuthResult(
        code: prepared.code == OneClickCode.tokenRequestSuccess
            ? OneClickCode.loginTokenFailed
            : prepared.code,
        message: prepared.message,
      );
    }
    final result = await presenter(_prompt!);
    return result ?? LoginAuthResult.cancelled();
  }

  /// 一键登录并换成业务会话。这是给页面用的完整业务入口。
  Future<SessionResult> signIn(
    BuildContext context, {
    bool autoDismiss = true,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return signInWith(
      (prompt) => _pushAuthPage(context, prompt, autoDismiss: autoDismiss),
      timeout: timeout,
    );
  }

  Future<SessionResult> signInWith(
    AuthPresenter presenter, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final auth = await loginAuthWith(presenter, timeout: timeout);
    if (!auth.ok || auth.loginToken == null) {
      return SessionResult(
        code: auth.code,
        message: auth.message,
        loginToken: auth.loginToken,
        maskedNumber: auth.maskedNumber,
      );
    }
    try {
      final appSession = await session.exchange(
        auth.loginToken!,
        maskedNumber: auth.maskedNumber ?? '',
      );
      return SessionResult(
        code: OneClickCode.loginTokenSuccess,
        message: '登录成功',
        session: appSession,
        loginToken: auth.loginToken,
        maskedNumber: auth.maskedNumber,
      );
    } on OneClickException catch (error) {
      return SessionResult(
        code: error.code,
        message: error.message,
        loginToken: auth.loginToken,
        maskedNumber: auth.maskedNumber,
      );
    }
  }

  Future<SmsCodeResult> getSmsCode(
    String phone, {
    String? signId,
    String? templateId,
  }) {
    return _guard(() async {
      final challenge = await gateway.requestSmsCode(
        phone: phone,
        signId: signId,
        templateId: templateId,
        minInterval: _smsInterval,
      );
      return SmsCodeResult(
        code: OneClickCode.smsSent,
        message: challenge.uuid,
        challenge: challenge,
      );
    }, (error) => SmsCodeResult(code: error.code, message: error.message));
  }

  void emit(AuthPageEvent event) {
    if (!_events.isClosed) _events.add(event);
    _log('event ${event.type.name}');
  }

  void dispose() => _events.close();

  Future<LoginAuthResult?> _pushAuthPage(
    BuildContext context,
    AuthPrompt prompt, {
    required bool autoDismiss,
  }) {
    final controller = OneClickAuthController(
      prompt: prompt,
      theme: theme,
      onAuthorize: () => completeAuthorization(),
      onEvent: emit,
    );
    return Navigator.of(context).push<LoginAuthResult>(
      MaterialPageRoute<LoginAuthResult>(
        fullscreenDialog: true,
        builder: (context) => OneClickAuthPage(
          controller: controller,
          theme: theme,
          autoDismiss: autoDismiss,
        ),
      ),
    );
  }

  Future<T> _guard<T>(
    Future<T> Function() body,
    T Function(OneClickException error) onError,
  ) async {
    try {
      return await body();
    } on OneClickException catch (error) {
      _log('code=${error.code.value} ${error.message}');
      return onError(error);
    } catch (error) {
      _log('internal $error');
      return onError(OneClickException(OneClickCode.internalError, '$error'));
    }
  }

  void _log(String message) {
    if (debug) debugPrint('[one_click_login] $message');
  }
}
