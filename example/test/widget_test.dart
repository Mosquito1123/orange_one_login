import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_login_example/main.dart';

void main() {
  testWidgets('shows the one-click login entry', (tester) async {
    await tester.pumpWidget(const OneClickDemoApp());
    expect(find.text('本机号码一键登录'), findsOneWidget);
    expect(find.text('仅获取认证 token'), findsOneWidget);
  });
}
