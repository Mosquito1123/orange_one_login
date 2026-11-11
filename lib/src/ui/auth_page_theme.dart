import 'package:flutter/material.dart';

import '../domain/models.dart';

/// 授权页外观。
///
/// 覆盖业务侧通常会改的部分：导航、号码区、登录按钮、协议和自定义入口。
@immutable
class AuthPageTheme {
  AuthPageTheme({
    this.navTitle = '登录',
    this.navColor = const Color(0xFF14322F),
    this.navTextColor = const Color(0xFFF6F1E8),
    this.pageColor = const Color(0xFFF6F1E8),
    this.inkColor = const Color(0xFF1C1915),
    this.accentColor = const Color(0xFF0F6E6B),
    this.mutedColor = const Color(0xFF6E675E),
    this.logoText = '本机号码',
    this.showLogo = true,
    this.loginButtonText = '本机号码一键登录',
    this.privacyCheckedByDefault = false,
    this.privacyHint = '请先阅读并同意相关协议',
    this.otherLoginText = '其他方式登录',
    this.showOtherLogin = true,
    List<PrivacyClause>? clauses,
    this.actions = const [],
  }) : clauses = clauses ?? defaultClauses;

  final String navTitle;
  final Color navColor;
  final Color navTextColor;
  final Color pageColor;
  final Color inkColor;
  final Color accentColor;
  final Color mutedColor;
  final String logoText;
  final bool showLogo;
  final String loginButtonText;
  final bool privacyCheckedByDefault;
  final String privacyHint;
  final String otherLoginText;
  final bool showOtherLogin;
  final List<PrivacyClause> clauses;
  final List<AuthAction> actions;

  static final List<PrivacyClause> defaultClauses = [
    PrivacyClause(name: '服务协议', url: Uri.parse('https://example.com/terms')),
    PrivacyClause(name: '隐私政策', url: Uri.parse('https://example.com/privacy')),
  ];
}
