import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// 17 位时间戳，格式 `yyyyMMddHHmmssSSS`。移动认证用这个，不用 Unix 毫秒。
String carrierTimestamp17(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${local.year}${two(local.month)}${two(local.day)}'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}$millis';
}

String md5Upper(String input) => md5.convert(utf8.encode(input)).toString().toUpperCase();

String sha256Upper(String input) => sha256.convert(utf8.encode(input)).toString().toUpperCase();

String hmacSha256Upper(String input, String key) {
  final mac = Hmac(sha256, utf8.encode(key));
  return mac.convert(utf8.encode(input)).toString().toUpperCase();
}

String maskMobile(String mobile) {
  final digits = mobile.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7) return mobile;
  return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
}

/// 天翼账号文档里的 XXTea。密钥只用前 16 字节，输出大写十六进制。
///
/// 校对向量：密钥 `N4rg8jiKy8618nY9B5uUKenVLyr0cNwp`、原文 `a=1&b=2&c=3`
/// 得到 `7945EDF312271A30DFF9DE02C3AFA736`。
String xxteaEncryptHex(String plain, String key) {
  final data = utf8.encode(plain);
  final encrypted = _xxteaEncrypt(Uint8List.fromList(data), Uint8List.fromList(utf8.encode(key)));
  return encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

Uint8List _xxteaEncrypt(Uint8List data, Uint8List key) {
  if (data.isEmpty) return data;
  final v = _toIntArray(data, true);
  final k = _toIntArray(_fixKey(key), false);
  _encryptInts(v, k);
  return _toByteArray(v, false);
}

Uint8List _fixKey(Uint8List key) {
  if (key.length == 16) return key;
  final fixed = Uint8List(16);
  fixed.setRange(0, key.length < 16 ? key.length : 16, key);
  return fixed;
}

List<int> _toIntArray(Uint8List data, bool includeLength) {
  var n = (data.length & 3) == 0 ? data.length >> 2 : (data.length >> 2) + 1;
  final result = List<int>.filled(includeLength ? n + 1 : n, 0);
  if (includeLength) result[n] = data.length;
  for (var i = 0; i < data.length; i++) {
    result[i >> 2] = (result[i >> 2] | ((data[i] & 0xff) << ((i & 3) << 3))) & 0xffffffff;
  }
  return result;
}

Uint8List _toByteArray(List<int> data, bool includeLength) {
  var n = data.length << 2;
  if (includeLength) {
    final m = data.last;
    if (m > n || m <= 0) return Uint8List(0);
    n = m;
  }
  final result = Uint8List(n);
  for (var i = 0; i < n; i++) {
    result[i] = (data[i >> 2] >> ((i & 3) << 3)) & 0xff;
  }
  return result;
}

void _encryptInts(List<int> v, List<int> k) {
  final n = v.length - 1;
  if (n < 1) return;
  if (k.length < 4) {
    k = [...k, ...List<int>.filled(4 - k.length, 0)];
  }
  var z = v[n];
  var y = v[0];
  const delta = 0x9E3779B9;
  var sum = 0;
  var q = 6 + 52 ~/ (n + 1);
  while (q-- > 0) {
    sum = (sum + delta) & 0xffffffff;
    final e = (sum >> 2) & 3;
    var p = 0;
    for (; p < n; p++) {
      y = v[p + 1];
      z = v[p] = (v[p] + _mx(sum, y, z, p, e, k)) & 0xffffffff;
    }
    y = v[0];
    z = v[n] = (v[n] + _mx(sum, y, z, p, e, k)) & 0xffffffff;
  }
}

int _mx(int sum, int y, int z, int p, int e, List<int> k) {
  return (((z >> 5) ^ ((y << 2) & 0xffffffff)) +
              (((y >> 3) ^ ((z << 4) & 0xffffffff)) & 0xffffffff)) ^
      ((sum ^ y) + (k[(p & 3) ^ e] ^ z));
}

RSAPrivateKey parsePkcs8RsaPrivateKey(String pem) {
  final body = pem
      .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
      .replaceAll(RegExp(r'-----END [^-]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  final parser = ASN1Parser(base64.decode(body));
  final top = parser.nextObject() as ASN1Sequence;
  final octet = top.elements![2];
  final keyBytes = octet is ASN1OctetString
      ? octet.octets!
      : (octet as ASN1BitString).stringValues as Uint8List;
  final inner = ASN1Parser(Uint8List.fromList(keyBytes)).nextObject() as ASN1Sequence;
  BigInt at(int index) => (inner.elements![index] as ASN1Integer).integer!;
  return RSAPrivateKey(at(1), at(3), at(4), at(5));
}

/// SHA1withRSA，输出大写十六进制。天翼 `sign` 用这个。
String rsaSha1SignHex(RSAPrivateKey key, String message) {
  final signer = Signer('SHA-1/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  final signature = signer.generateSignature(utf8.encode(message)) as RSASignature;
  return signature.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

String rsaPkcs1DecryptUtf8(RSAPrivateKey key, String hexCipher) {
  final cipher = _hexToBytes(hexCipher);
  final engine = PKCS1Encoding(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
  final plain = engine.process(Uint8List.fromList(cipher));
  return utf8.decode(plain);
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
