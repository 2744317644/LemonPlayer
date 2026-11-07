import 'dart:io';

import 'package:lemon_guangya/lemon_guangya.dart';

/// Phase 1：Dart 包级验证光鸭开发者 API（签名 + 文件列表）。
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

  final api = GuangyaApi(
    config: GuangyaConfig(clientId: clientId, clientSecret: clientSecret),
  );
  try {
    final page = await api.listFiles(pageSize: 5);
    stdout.writeln('HTTP 200 · total=${page.total}');
    for (final item in page.items) {
      stdout.writeln('- ${item.isFolder ? "[目录]" : "[文件]"} ${item.name} (${item.id})');
    }
  } catch (error) {
    stderr.writeln('请求失败：$error');
    exitCode = 1;
  }
}