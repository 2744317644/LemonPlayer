import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 光鸭开发者 API 签名：
/// hex(sha512(md5_raw_bytes("client_id=..&client_secret=..&nonce=..&timestamp=..")))
String createDeveloperSign({
  required String clientId,
  required String clientSecret,
  required String nonce,
  required int timestamp,
}) {
  final source =
      'client_id=$clientId&client_secret=$clientSecret&nonce=$nonce&timestamp=$timestamp';
  final md5Bytes = md5.convert(utf8.encode(source)).bytes;
  return sha512.convert(md5Bytes).toString();
}

String randomNonce({int bytes = 16, Random? random}) {
  final source = random ?? Random.secure();
  return List.generate(
    bytes,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Map<String, String> developerSignHeaders({
  required String clientId,
  required String clientSecret,
  DateTime? now,
  String? nonce,
}) {
  final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final resolvedNonce = nonce ?? randomNonce();
  return {
    'Content-Type': 'application/json',
    'client_id': clientId,
    'nonce': resolvedNonce,
    'timestamp': '$timestamp',
    'sign': createDeveloperSign(
      clientId: clientId,
      clientSecret: clientSecret,
      nonce: resolvedNonce,
      timestamp: timestamp,
    ),
  };
}
