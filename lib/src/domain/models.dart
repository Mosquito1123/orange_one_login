import 'one_click_code.dart';

/// 运营商。`code` 使用公开缩写：CM / CU / CT。
enum MobileOperator {
  cmcc('CM', '中国移动'),
  cucc('CU', '中国联通'),
  ctcc('CT', '中国电信'),
  unknown('', '未知运营商');

  const MobileOperator(this.code, this.displayName);

  final String code;
  final String displayName;

  String get slogan => displayName == '未知运营商'
      ? '认证服务由运营商提供'
      : '$displayName提供认证服务';

  static MobileOperator parse(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'CM':
      case 'CMCC':
        return MobileOperator.cmcc;
      case 'CU':
      case 'CUCC':
        return MobileOperator.cucc;
      case 'CT':
      case 'CTCC':
        return MobileOperator.ctcc;
      default:
        return MobileOperator.unknown;
    }
  }
}

enum TokenKind { verify, login }

class VerifyEnvironment {
  const VerifyEnvironment({
    required this.supported,
    required this.message,
    this.operator,
  });

  final bool supported;
  final String message;
  final MobileOperator? operator;
}

class PreLoginTicket {
  const PreLoginTicket({
    required this.maskedNumber,
    required this.operator,
    required this.expiresAt,
  });

  final String maskedNumber;
  final MobileOperator operator;
  final DateTime expiresAt;

  bool isValidAt(DateTime now) => expiresAt.isAfter(now);
}

class CarrierToken {
  const CarrierToken({
    required this.token,
    required this.kind,
    required this.operator,
    required this.expiresAt,
    this.extras = const {},
  });

  final String token;
  final TokenKind kind;
  final MobileOperator operator;
  final DateTime expiresAt;

  /// 运营商换号还要的附加字段。电信免密登录把 `authCode` 放在这里，`token` 是 `accessCode`。
  final Map<String, String> extras;

  bool isValidAt(DateTime now) => expiresAt.isAfter(now);
}

class SmsChallenge {
  const SmsChallenge({required this.uuid, required this.phone});

  final String uuid;
  final String phone;
}

class AppSession {
  const AppSession({
    required this.sessionId,
    required this.maskedNumber,
    required this.operator,
    required this.expiresAt,
  });

  final String sessionId;
  final String maskedNumber;
  final MobileOperator operator;
  final DateTime expiresAt;

  factory AppSession.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expiresAt'];
    final expiresIn = json['expiresIn'];
    final DateTime expiresAt;
    if (expiresRaw is String) {
      expiresAt = DateTime.parse(expiresRaw);
    } else if (expiresIn is num) {
      expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn.round()));
    } else {
      expiresAt = DateTime.now().toUtc().add(const Duration(hours: 12));
    }
    return AppSession(
      sessionId: '${json['sessionId'] ?? ''}',
      maskedNumber: '${json['maskedNumber'] ?? ''}',
      operator: MobileOperator.parse('${json['operator'] ?? ''}'),
      expiresAt: expiresAt,
    );
  }
}

class TokenResult {
  const TokenResult({
    required this.code,
    required this.message,
    this.token,
  });

  final OneClickCode code;
  final String message;
  final CarrierToken? token;

  bool get ok => code == OneClickCode.tokenRequestSuccess && token != null;
}

class PreLoginResult {
  const PreLoginResult({
    required this.code,
    required this.message,
    this.ticket,
  });

  final OneClickCode code;
  final String message;
  final PreLoginTicket? ticket;

  bool get ok => code == OneClickCode.tokenRequestSuccess && ticket != null;
}

class LoginAuthResult {
  const LoginAuthResult({
    required this.code,
    required this.message,
    this.loginToken,
    this.maskedNumber,
    this.operator,
  });

  final OneClickCode code;
  final String message;
  final CarrierToken? loginToken;
  final String? maskedNumber;
  final MobileOperator? operator;

  bool get ok => code == OneClickCode.loginTokenSuccess && loginToken != null;

  factory LoginAuthResult.cancelled() => const LoginAuthResult(
        code: OneClickCode.loginCancelled,
        message: '用户取消登录',
      );
}

class SmsCodeResult {
  const SmsCodeResult({
    required this.code,
    required this.message,
    this.challenge,
  });

  final OneClickCode code;
  final String message;
  final SmsChallenge? challenge;

  bool get ok => code == OneClickCode.smsSent && challenge != null;
}

class SessionResult {
  const SessionResult({
    required this.code,
    required this.message,
    this.session,
    this.loginToken,
    this.maskedNumber,
  });

  final OneClickCode code;
  final String message;
  final AppSession? session;
  final CarrierToken? loginToken;
  final String? maskedNumber;

  bool get ok => session != null && code == OneClickCode.loginTokenSuccess;
}

class PrivacyClause {
  const PrivacyClause({required this.name, required this.url});

  final String name;
  final Uri url;
}

class AuthAction {
  const AuthAction({required this.id, required this.title});

  final String id;
  final String title;
}

class AuthPrompt {
  const AuthPrompt({
    required this.maskedNumber,
    required this.operator,
    required this.slogan,
    required this.clauses,
    required this.actions,
  });

  final String maskedNumber;
  final MobileOperator operator;
  final String slogan;
  final List<PrivacyClause> clauses;
  final List<AuthAction> actions;
}

enum AuthPageEventType {
  shown,
  dismissed,
  privacyChanged,
  loginTapped,
  otherLogin,
  customAction,
}

class AuthPageEvent {
  const AuthPageEvent(this.type, {this.widgetId, this.privacyChecked});

  final AuthPageEventType type;
  final String? widgetId;
  final bool? privacyChecked;
}
