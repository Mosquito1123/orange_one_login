import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'auth_controller.dart';
import 'auth_page_theme.dart';

/// 一键登录授权页：掩码号码、运营商说明、协议勾选、登录和其他方式。
class OneClickAuthPage extends StatefulWidget {
  const OneClickAuthPage({
    super.key,
    required this.controller,
    required this.theme,
    this.autoDismiss = true,
  });

  final OneClickAuthController controller;
  final AuthPageTheme theme;
  final bool autoDismiss;

  @override
  State<OneClickAuthPage> createState() => _OneClickAuthPageState();
}

class _OneClickAuthPageState extends State<OneClickAuthPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.onEvent(const AuthPageEvent(AuthPageEventType.shown));
  }

  Future<void> _submit() async {
    final result = await widget.controller.submit();
    if (!mounted || result == null || !result.ok) return;
    if (widget.autoDismiss) {
      Navigator.of(context).pop(result);
    }
  }

  void _pop(LoginAuthResult result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final prompt = controller.prompt;
        return Scaffold(
          backgroundColor: theme.pageColor,
          appBar: AppBar(
            backgroundColor: theme.navColor,
            foregroundColor: theme.navTextColor,
            title: Text(theme.navTitle),
            leading: IconButton(
              tooltip: '关闭',
              onPressed: () => _pop(controller.cancel()),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (theme.showLogo) ...[
                    Align(
                      child: Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.accentColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          theme.logoText.isEmpty ? '号' : theme.logoText.characters.first,
                          style: TextStyle(
                            color: theme.pageColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                  Text(
                    prompt.maskedNumber,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prompt.slogan,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.mutedColor, fontSize: 13),
                  ),
                  const Spacer(),
                  if (controller.hint != null) ...[
                    Text(
                      controller.hint!,
                      key: const Key('auth-hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF9A3B2F), fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    key: const Key('one-click-submit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: theme.pageColor,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: controller.submitting ? null : _submit,
                    child: controller.submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(theme.loginButtonText),
                  ),
                  if (theme.showOtherLogin)
                    TextButton(
                      key: const Key('other-login'),
                      onPressed: () => _pop(controller.otherLogin()),
                      child: Text(
                        theme.otherLoginText,
                        style: TextStyle(color: theme.inkColor),
                      ),
                    ),
                  for (final action in prompt.actions)
                    TextButton(
                      onPressed: () => controller.tapAction(action),
                      child: Text(action.title),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: const Key('privacy-check'),
                        value: controller.privacyChecked,
                        activeColor: theme.accentColor,
                        onChanged: (value) => controller.togglePrivacy(value ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '我已阅读并同意',
                                style: TextStyle(color: theme.mutedColor, fontSize: 13),
                              ),
                              for (var i = 0; i < prompt.clauses.length; i++) ...[
                                if (i > 0)
                                  Text(
                                    '和',
                                    style: TextStyle(color: theme.mutedColor, fontSize: 13),
                                  ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showClause(prompt.clauses[i]),
                                  child: Text(
                                    '《${prompt.clauses[i].name}》',
                                    style: TextStyle(color: theme.accentColor, fontSize: 13),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showClause(PrivacyClause clause) {
    widget.controller.openClause(clause);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(clause.name),
        content: Text(clause.url.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
