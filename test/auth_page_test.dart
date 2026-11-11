import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one_login/orange_one_login.dart';

void main() {
  testWidgets('login stays on the page until privacy is accepted', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    final gateway = DemoCarrierGateway(clock: () => now);
    final client = OneClickClient(
      gateway: gateway,
      session: LocalSessionExchanger(clock: () => now),
    );
    await client.setup(appKey: 'demo-app-key');
    final prepared = await client.prepare();
    expect(prepared.ok, isTrue);

    LoginAuthResult? popped;
    final controller = OneClickAuthController(
      prompt: AuthPrompt(
        maskedNumber: prepared.ticket!.maskedNumber,
        operator: prepared.ticket!.operator,
        slogan: prepared.ticket!.operator.slogan,
        clauses: client.theme.clauses,
        actions: const [AuthAction(id: 'help', title: '遇到问题')],
      ),
      theme: client.theme,
      onAuthorize: client.completeAuthorization,
      onEvent: client.emit,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<LoginAuthResult>(
                  MaterialPageRoute(
                    builder: (_) => OneClickAuthPage(
                      controller: controller,
                      theme: client.theme,
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('138****8000'), findsOneWidget);
    expect(find.text('中国移动提供认证服务'), findsOneWidget);

    await tester.tap(find.byKey(const Key('one-click-submit')));
    await tester.pump();
    expect(find.byKey(const Key('auth-hint')), findsOneWidget);
    expect(find.text('请先阅读并同意相关协议'), findsOneWidget);
    expect(popped, isNull);

    await tester.tap(find.byKey(const Key('privacy-check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('one-click-submit')));
    await tester.pumpAndSettle();

    expect(popped?.ok, isTrue);
    expect(popped?.loginToken?.token, startsWith('ocl.login.CM.'));
    expect(find.text('138****8000'), findsNothing);
  });

  testWidgets('close returns a cancellation', (tester) async {
    final controller = OneClickAuthController(
      prompt: AuthPrompt(
        maskedNumber: '186****1111',
        operator: MobileOperator.cucc,
        slogan: MobileOperator.cucc.slogan,
        clauses: AuthPageTheme.defaultClauses,
        actions: const [],
      ),
      theme: AuthPageTheme(),
      onAuthorize: () async => LoginAuthResult.cancelled(),
      onEvent: (_) {},
    );
    LoginAuthResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<LoginAuthResult>(
                  MaterialPageRoute(
                    builder: (_) => OneClickAuthPage(
                      controller: controller,
                      theme: AuthPageTheme(),
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(popped?.code, OneClickCode.loginCancelled);
  });
}
