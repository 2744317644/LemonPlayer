import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Phase 0：Dart 侧验证光鸭开发者 API（签名 + 文件列表）。
/// 用法（不要把凭据写进仓库）：
///   $env:GUANGYA_CLIENT_ID=...; $env:GUANGYA_CLIENT_SECRET=...
///   dart run tool/guangya_probe.dart
Future<void> main() async {
  final clientId = Platform.environment['GUANGYA_CLIENT_ID'] ?? '';
  final clientSecret = Platform.environment['GUANGYA_CLIENT_SECRET'] ?? '';
  if (clientId.isEmpty || clientSecret.isEmpty) {
    stderr.writeln('缺少 GUANGYA_CLIENT_ID / GUANGYA_CLIENT_SECRET');
    exitCode = 2;
    return;
  }

  final nonce = _randomHex(16);
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sign = _sign(clientId, clientSecret, nonce, '$timestamp');

  final client = HttpClient();
  final request = await client.postUrl(
    Uri.parse('https://dapi.guangyapan.com/userres/v1/file/get_file_list'),
  );
  request.headers
    ..set('Content-Type', 'application/json')
    ..set('client_id', clientId)
    ..set('nonce', nonce)
    ..set('timestamp', '$timestamp')
    ..set('sign', sign);
  request.write(jsonEncode({
    'parentId': '',
    'page': 0,
    'pageSize': 3,
    'orderBy': 3,
    'sortType': 0,
  }));

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  stdout.writeln('HTTP ${response.statusCode}');
  stdout.writeln(body.length > 600 ? '${body.substring(0, 600)}…' : body);
  client.close();
}

String _sign(
  String clientId,
  String clientSecret,
  String nonce,
  String timestamp,
) {
  final source = 'client_id=$clientId&client_secret=$clientSecret'
      '&nonce=$nonce&timestamp=$timestamp';
  final md5Bytes = md5.convert(utf8.encode(source)).bytes;
  return sha512.convert(md5Bytes).toString();
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
