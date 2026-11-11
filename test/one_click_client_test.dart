import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orange_one_login/orange_one_login.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 8);

  OneClickClient clientOf(
    DemoCarrierGateway gateway, {
    SessionExchanger? session,
  }) {
    return OneClickClient(
      gateway: gateway,
      session: session ?? LocalSessionExchanger(clock: () => now),
    );
  }

  DemoCarrierGateway gateway() => DemoCarrierGateway(clock: () => now);

  group('OneClickClient', () {
    test('setup is required before prelogin', () async {
      final client = clientOf(gateway());
      final result = await client.preLogin();
      expect(result.code, OneClickCode.notInitialized);
    });

    test('rejects a short app key and a timeout outside the legal range', () async {
      final client = clientOf(gateway());
      expect(
        () => client.setup(appKey: 'short'),
        throwsA(isA<OneClickException>()),
      );
      await client.setup(appKey: 'demo-app-key');
      final result = await client.preLogin(timeout: Duration.zero);
      expect(result.code, OneClickCode.parameterInvalid);
    });

    test('wifi cannot prefetch or authorize', () async {
      final net = gateway()..cellular = false;
      final client = clientOf(net);
      await client.setup(appKey: 'demo-app-key');
      final env = await client.checkVerifyEnable();
      expect(env.supported, isFalse);
      final prepared = await client.prepare();
      expect(prepared.code, OneClickCode.networkNotSupported);
    });

    test('prelogin cache is reused and can be cleared', () async {
      final client = clientOf(gateway());
      await client.setup(appKey: 'demo-app-key');
      final first = await client.preLogin();
      expect(first.ticket?.maskedNumber, '138****8000');
      expect(await client.validPreLoginCache(), isTrue);
      await client.clearPreLoginCache();
      expect(await client.validPreLoginCache(), isFalse);
    });

    test('verify token expires after one minute', () async {
      var clock = now;
      final net = DemoCarrierGateway(clock: () => clock);
      final client = clientOf(net);
      await client.setup(appKey: 'demo-app-key');
      final token = await client.getToken();
      expect(token.ok, isTrue);
      expect(token.message, token.token!.token);
      expect(token.token!.isValidAt(clock), isTrue);
      clock = now.add(const Duration(minutes: 1));
      expect(token.token!.isValidAt(clock), isFalse);
    });

    test('a second token request is rejected while the first is in flight', () async {
      final gate = Completer<void>();
      final net = gateway()..stall = () => gate.future;
      final client = clientOf(net);
      await client.setup(appKey: 'demo-app-key');
      final first = client.getToken();
      await Future<void>.delayed(Duration.zero);
      final second = await client.getToken();
      expect(second.code, OneClickCode.tokenRequestInProgress);
      gate.complete();
      expect((await first).ok, isTrue);
    });

    test('sign-in exchanges a login token after the user agrees', () async {
      final events = <AuthPageEventType>[];
      final client = clientOf(gateway());
      client.pageEvents.listen((event) => events.add(event.type));
      await client.setup(appKey: 'demo-app-key');

      final session = await client.signInWith((prompt) async {
        expect(prompt.maskedNumber, '138****8000');
        expect(prompt.slogan, '中国移动提供认证服务');
        return client.completeAuthorization();
      });

      expect(session.ok, isTrue);
      expect(session.session?.maskedNumber, '138****8000');
      expect(session.loginToken?.token, startsWith('ocl.login.CM.'));
    });

    test('cancel and other-login do not create a session', () async {
      final client = clientOf(gateway());
      await client.setup(appKey: 'demo-app-key');
      final cancelled = await client.signInWith((_) async => LoginAuthResult.cancelled());
      expect(cancelled.code, OneClickCode.loginCancelled);
      expect(cancelled.session, isNull);

      final other = await client.signInWith(
        (_) async => const LoginAuthResult(
          code: OneClickCode.switchedToOther,
          message: '其他方式',
        ),
      );
      expect(other.code, OneClickCode.switchedToOther);
    });

    test('sms code respects phone format and the interval', () async {
      final client = clientOf(gateway());
      await client.setup(appKey: 'demo-app-key');
      client.setSmsInterval(const Duration(seconds: 30));
      expect((await client.getSmsCode('123')).code, OneClickCode.invalidPhone);
      final sent = await client.getSmsCode('13800138000');
      expect(sent.ok, isTrue);
      expect(sent.challenge?.uuid, 'sms-1');
      expect(
        (await client.getSmsCode('13800138000')).code,
        OneClickCode.smsTooFrequent,
      );
    });
  });

  test('http session exchanger posts the login token', () async {
    final requests = <http.Request>[];
    final httpClient = _FakeHttp((request) {
      requests.add(request);
      return http.Response(
        jsonEncode({'sessionId': 's-9', 'expiresIn': 60}),
        200,
      );
    });
    final exchanger = HttpSessionExchanger(
      endpoint: Uri.parse('https://auth.example.com/one-click'),
      httpClient: httpClient,
    );
    final token = CarrierToken(
      token: 'carrier-login-token',
      kind: TokenKind.login,
      operator: MobileOperator.cucc,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final session = await exchanger.exchange(token, maskedNumber: '186****0000');
    expect(session.sessionId, 's-9');
    expect(session.operator, MobileOperator.cucc);
    expect(session.maskedNumber, '186****0000');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['loginToken'], 'carrier-login-token');
    expect(body['operator'], 'CU');
    exchanger.close();
  });
}

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this._handle);

  final http.Response Function(http.Request request) _handle;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final materialized = http.Request(request.method, request.url)
      ..bodyBytes = await request.finalize().toBytes();
    final response = _handle(materialized);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
