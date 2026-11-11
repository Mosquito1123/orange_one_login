import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orange_one_login/orange_one_login.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('xxtea matches the Tianyi published vector', () {
    expect(
      xxteaEncryptHex('a=1&b=2&c=3', 'N4rg8jiKy8618nY9B5uUKenVLyr0cNwp'),
      '7945EDF312271A30DFF9DE02C3AFA736',
    );
  });

  test('cmcc login token request uses the documented md5 sign', () async {
    final requests = <http.Request>[];
    final httpClient = _FakeHttp((request) {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'inresponseto': 'abc',
          'resultCode': '103000',
          'msisdn': '15900001111',
          'taskId': 'task-1',
        }),
        200,
      );
    });
    final client = CmccAuthClient(
      appId: '10000001',
      appSecret: 'secret',
      httpClient: httpClient,
      random: _FixedRandom(),
    );
    final phone = await client.exchangeLoginToken(
      'token-1',
      now: DateTime(2019, 2, 26, 11, 18, 42, 617),
    );
    expect(phone.mobile, '15900001111');
    expect(phone.masked, '159****1111');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['version'], '2.0');
    expect(body['strictcheck'], '0');
    expect(body['systemtime'], '20190226111842617');
    expect(
      body['sign'],
      md5Upper(
        '10000001'
        '2.0'
        '${body['msgid']}'
        '20190226111842617'
        '0'
        'token-1'
        'secret',
      ),
    );
    expect(requests.single.url.toString(), CmccAuthClient.defaultLoginEndpoint.toString());
    client.close();
  });

  test('cmcc rejects a bad result code', () async {
    final client = CmccAuthClient(
      appId: '10000001',
      appSecret: 'secret',
      httpClient: _FakeHttp(
        (_) => http.Response(jsonEncode({'resultCode': '104201'}), 200),
      ),
    );
    expect(
      () => client.exchangeLoginToken('gone'),
      throwsA(
        isA<OneClickException>().having((e) => e.code, 'code', OneClickCode.fetchTokenError),
      ),
    );
    client.close();
  });

  test('cucc posts accessToken and md5 sign', () async {
    final requests = <http.Request>[];
    final client = CuccAuthClient(
      appId: 'unicom-app',
      appSecret: 'unicom-secret',
      httpClient: _FakeHttp((request) {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'code': '0',
            'msg': 'success',
            'data': {'mobile': '18600001234'},
          }),
          200,
        );
      }),
    );
    final phone = await client.exchangeAccessToken(
      'access-1',
      now: DateTime(2020, 11, 25, 10, 15, 40, 980),
    );
    expect(phone.operator, MobileOperator.cucc);
    expect(phone.masked, '186****1234');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['accessToken'], 'access-1');
    expect(body['timeStamp'], '20201125101540980');
    expect(
      body['sign'],
      md5Upper('unicom-appaccess-120201125101540980unicom-secret'),
    );
    client.close();
  });

  test('ctcc form body contains xxtea params and a sha1-rsa sign', () async {
    final key = _testKey();
    final requests = <http.Request>[];
    final client = CtccAuthClient(
      appId: '8134110178',
      appSecret: 'N4rg8jiKy8618nY9B5uUKenVLyr0cNwp',
      rsaPrivateKeyPem: key.pem,
      httpClient: _FakeHttp((request) {
        requests.add(request);
        final cipher = rsaEncryptHex(key.public, '{"mobile":"15100000000","state":"1"}');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'result': 0, 'msg': '操作成功', 'data': cipher})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final phone = await client.exchangeSdkCode(
      accessCode: 'access-code',
      authCode: 'auth-code',
      now: DateTime.fromMillisecondsSinceEpoch(175868425871),
    );
    expect(phone.mobile, '15100000000');
    expect(phone.operator, MobileOperator.ctcc);
    final form = requests.single.body;
    expect(form, contains('format=json'));
    expect(form, contains('params=${xxteaEncryptHex('accessCode=access-code&authCode=auth-code', 'N4rg8jiKy8618nY9B5uUKenVLyr0cNwp')}'));
    expect(requests.single.url.toString(), CtccAuthClient.defaultEndpoint.toString());
    client.close();
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

class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 1;
}

class _KeyPair {
  _KeyPair(this.pem, this.public);
  final String pem;
  final RSAPublicKey public;
}

_KeyPair _testKey() {
  final pair = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
        FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1)))),
      ),
    );
  final generated = pair.generateKeyPair();
  final public = generated.publicKey as RSAPublicKey;
  final private = generated.privateKey as RSAPrivateKey;
  return _KeyPair(_pkcs8(private, public), public);
}

String _pkcs8(RSAPrivateKey private, RSAPublicKey public) {
  final seq = ASN1Sequence()
    ..add(ASN1Integer(BigInt.zero))
    ..add(ASN1Integer(private.n!))
    ..add(ASN1Integer(public.exponent!))
    ..add(ASN1Integer(private.privateExponent!))
    ..add(ASN1Integer(private.p!))
    ..add(ASN1Integer(private.q!));
  final pkcs8 = ASN1Sequence()
    ..add(ASN1Integer(BigInt.zero))
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
        ..add(ASN1Null()),
    )
    ..add(ASN1OctetString(octets: seq.encode()));
  final b64 = base64.encode(pkcs8.encode());
  return '-----BEGIN PRIVATE KEY-----\n$b64\n-----END PRIVATE KEY-----';
}

String rsaEncryptHex(RSAPublicKey key, String plain) {
  final engine = PKCS1Encoding(RSAEngine())..init(true, PublicKeyParameter<RSAPublicKey>(key));
  final bytes = engine.process(Uint8List.fromList(utf8.encode(plain)));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
