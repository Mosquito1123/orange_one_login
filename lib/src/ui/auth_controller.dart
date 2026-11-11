import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/one_click_code.dart';
import 'auth_page_theme.dart';

/// 授权页状态。协议勾选和提交都在这里，页面只负责绘制和把结果弹回。
class OneClickAuthController extends ChangeNotifier {
  OneClickAuthController({
    required this.prompt,
    required AuthPageTheme theme,
    required this.onAuthorize,
    required this.onEvent,
  })  : _theme = theme,
        privacyChecked = theme.privacyCheckedByDefault;

  final AuthPrompt prompt;
  final AuthPageTheme _theme;
  final Future<LoginAuthResult> Function() onAuthorize;
  final void Function(AuthPageEvent event) onEvent;

  bool privacyChecked;
  bool submitting = false;
  String? hint;

  void togglePrivacy(bool value) {
    privacyChecked = value;
    hint = null;
    onEvent(AuthPageEvent(AuthPageEventType.privacyChanged, privacyChecked: value));
    notifyListeners();
  }

  void openClause(PrivacyClause clause) {
    onEvent(AuthPageEvent(AuthPageEventType.customAction, widgetId: clause.url.toString()));
  }

  void tapAction(AuthAction action) {
    onEvent(AuthPageEvent(AuthPageEventType.customAction, widgetId: action.id));
  }

  /// 返回 `null` 表示留在授权页，例如还没有勾选协议。
  Future<LoginAuthResult?> submit() async {
    onEvent(const AuthPageEvent(AuthPageEventType.loginTapped));
    if (!privacyChecked) {
      hint = _theme.privacyHint;
      notifyListeners();
      return null;
    }
    if (submitting) return null;
    submitting = true;
    hint = null;
    notifyListeners();
    try {
      final result = await onAuthorize();
      if (!result.ok) hint = result.message;
      return result;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  LoginAuthResult cancel() {
    onEvent(const AuthPageEvent(AuthPageEventType.dismissed));
    return LoginAuthResult.cancelled();
  }

  LoginAuthResult otherLogin() {
    onEvent(const AuthPageEvent(AuthPageEventType.otherLogin));
    return const LoginAuthResult(
      code: OneClickCode.switchedToOther,
      message: '用户改用其他登录方式',
    );
  }
}
