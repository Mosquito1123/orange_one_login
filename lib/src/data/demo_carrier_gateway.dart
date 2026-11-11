import '../domain/models.dart';
import '../domain/one_click_code.dart';
import '../domain/one_click_exception.dart';
import 'carrier_gateway.dart';

typedef OneClickClock = DateTime Function();

/// 本地演示网关。
///
/// 它复现一键登录的业务时序：蜂窝网络判断、预取号缓存、1 分钟 token、短信间隔。
/// 返回的 token 以 `ocl.` 开头，不能拿去换任何第三方认证服务的登录态。
class DemoCarrierGateway implements CarrierAuthGateway {
  DemoCarrierGateway({
    this.operator = MobileOperator.cmcc,
    this.maskedNumber = '138****8000',
    this.cellular = true,
    OneClickClock? clock,
    this.preLoginTtl = const Duration(minutes: 10),
    this.tokenTtl = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now;

  MobileOperator operator;
  String maskedNumber;

  /// 为 false 时表示当前是 Wi-Fi 或不支持认证的网络。
  bool cellular;

  final Duration preLoginTtl;
  final Duration tokenTtl;
  final OneClickClock _clock;

  String? _appKey;
  PreLoginTicket? _preLogin;
  DateTime? _lastSmsAt;
  bool _busy = false;
  int _seq = 0;

  /// 测试用：进入临界区后先等待，便于断言重复请求会被拒绝。
  Future<void> Function()? stall;

  bool get isReady => _appKey != null;

  DateTime get _now => _clock();

  @override
  Future<void> setup({
    required String appKey,
    required String channel,
    required Duration timeout,
  }) async {
    _checkTimeout(timeout);
    if (appKey.trim().length < 8 || channel.trim().isEmpty) {
      throw OneClickException(OneClickCode.appKeyIllegal);
    }
    _appKey = appKey.trim();
  }

  @override
  Future<VerifyEnvironment> checkVerifyEnable() async {
    _ensureReady();
    if (!cellular || operator == MobileOperator.unknown) {
      return const VerifyEnvironment(
        supported: false,
        message: '当前网络环境不支持认证',
      );
    }
    return VerifyEnvironment(
      supported: true,
      operator: operator,
      message: '当前网络环境支持认证',
    );
  }

  @override
  PreLoginTicket? get cachedPreLogin {
    final cached = _preLogin;
    if (cached == null || !cached.isValidAt(_now)) return null;
    return cached;
  }

  @override
  void clearPreLogin() => _preLogin = null;

  @override
  Future<PreLoginTicket> preLogin({required Duration timeout}) {
    return _exclusive(tokenBusy: true, () async {
      _checkTimeout(timeout);
      _ensureReady();
      _ensureCellular();
      final ticket = PreLoginTicket(
        maskedNumber: maskedNumber,
        operator: operator,
        expiresAt: _now.add(preLoginTtl),
      );
      _preLogin = ticket;
      return ticket;
    });
  }

  @override
  Future<CarrierToken> getToken({required Duration timeout}) {
    return _exclusive(tokenBusy: true, () async {
      _checkTimeout(timeout);
      _ensureReady();
      _ensureCellular();
      return _issue(TokenKind.verify);
    });
  }

  @override
  Future<CarrierToken> authorize({required Duration timeout}) {
    return _exclusive(tokenBusy: false, () async {
      _checkTimeout(timeout);
      _ensureReady();
      _ensureCellular();
      cachedPreLogin ??
          (throw OneClickException(
            OneClickCode.loginTokenFailed,
            '请先预取号',
          ));
      return _issue(TokenKind.login);
    });
  }

  @override
  Future<SmsChallenge> requestSmsCode({
    required String phone,
    String? signId,
    String? templateId,
    required Duration minInterval,
  }) async {
    _ensureReady();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      throw OneClickException(OneClickCode.invalidPhone);
    }
    final last = _lastSmsAt;
    if (last != null && _now.difference(last) < minInterval) {
      throw OneClickException(OneClickCode.smsTooFrequent);
    }
    _lastSmsAt = _now;
    _seq += 1;
    return SmsChallenge(uuid: 'sms-$_seq', phone: phone);
  }

  CarrierToken _issue(TokenKind kind) {
    _seq += 1;
    return CarrierToken(
      token: 'ocl.${kind.name}.${operator.code}.$_seq.${_now.millisecondsSinceEpoch}',
      kind: kind,
      operator: operator,
      expiresAt: _now.add(tokenTtl),
    );
  }

  Future<T> _exclusive<T>(
    Future<T> Function() body, {
    required bool tokenBusy,
  }) async {
    if (_busy) {
      throw OneClickException(
        tokenBusy
            ? OneClickCode.tokenRequestInProgress
            : OneClickCode.verifyingInProgress,
      );
    }
    _busy = true;
    try {
      final pause = stall;
      if (pause != null) await pause();
      return await body();
    } finally {
      _busy = false;
    }
  }

  void _ensureReady() {
    if (_appKey == null) {
      throw OneClickException(OneClickCode.notInitialized);
    }
  }

  void _ensureCellular() {
    if (!cellular || operator == MobileOperator.unknown) {
      throw OneClickException(OneClickCode.networkNotSupported);
    }
  }

  void _checkTimeout(Duration timeout) {
    final ms = timeout.inMilliseconds;
    if (ms <= 0 || ms > 30000) {
      throw OneClickException(
        OneClickCode.parameterInvalid,
        'timeout 必须在 (0, 30000] 毫秒',
      );
    }
  }
}
