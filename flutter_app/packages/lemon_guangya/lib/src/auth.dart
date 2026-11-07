import 'dart:convert';

import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_network/lemon_network.dart';

import 'device_identity.dart';

const String guangyaClientId = 'aMe-8VSlkrbQXpUR';
const String guangyaAccountBase = 'https://account.guangyapan.com';

class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.expiresIn,
    required this.interval,
    this.verificationUrl,
    this.verificationUriComplete,
  });

  final String deviceCode;
  final String userCode;
  final int expiresIn;
  final int interval;
  final String? verificationUrl;
  final String? verificationUriComplete;

  String get qrContent =>
      verificationUriComplete ?? verificationUrl ?? '';

  factory DeviceCode.fromJson(Map<String, dynamic> json) => DeviceCode(
        deviceCode: '${json['device_code'] ?? ''}',
        userCode: '${json['user_code'] ?? ''}',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 120,
        interval: (json['interval'] as num?)?.toInt() ?? 2,
        verificationUrl: json['verification_url'] as String?,
        verificationUriComplete: json['verification_uri_complete'] as String?,
      );
}

class TokenBundle {
  const TokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.tokenType,
    this.subject,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String? tokenType;
  final String? subject;

  factory TokenBundle.fromJson(Map<String, dynamic> json) => TokenBundle(
        accessToken: '${json['access_token'] ?? ''}',
        refreshToken: '${json['refresh_token'] ?? ''}',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
        tokenType: json['token_type'] as String?,
        subject: json['sub'] as String?,
      );

  /// 宽容解析：token 可能在顶层或 data 里。
  static TokenBundle? decodeLenient(String body) {
    final root = _tryJson(body);
    if (root == null) return null;
    for (final map in _walk(root)) {
      final token = map['access_token'];
      if (token is String && token.isNotEmpty) {
        return TokenBundle(
          accessToken: token,
          refreshToken: '${map['refresh_token'] ?? ''}',
          expiresIn: (map['expires_in'] as num?)?.toInt() ?? 3600,
          tokenType: map['token_type'] as String?,
          subject: map['sub'] as String?,
        );
      }
    }
    return null;
  }

  static Map<String, dynamic>? _tryJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Iterable<Map<String, dynamic>> _walk(
    Map<String, dynamic> root, [
    int depth = 0,
  ]) sync* {
    yield root;
    if (depth >= 3) return;
    for (final value in root.values) {
      if (value is Map<String, dynamic>) {
        yield* _walk(value, depth + 1);
      }
    }
  }
}

enum DevicePollStatus { pending, authorized, expired, failed }

class DevicePollResult {
  const DevicePollResult({required this.status, this.token, this.message});

  final DevicePollStatus status;
  final TokenBundle? token;
  final String? message;

  /// 服务端用 HTTP 400 + JSON error 表示 pending，必须按 body 判断。
  static DevicePollResult decode(int statusCode, String body) {
    final json = _tryJson(body);
    if (json == null) {
      return DevicePollResult(
        status: DevicePollStatus.failed,
        message: '无法解析登录响应（HTTP $statusCode）',
      );
    }
    final token = TokenBundle.decodeLenient(body);
    if (token != null) {
      return DevicePollResult(
        status: DevicePollStatus.authorized,
        token: token,
      );
    }
    final error = json['error'] as String?;
    switch (error) {
      case 'authorization_pending':
        return const DevicePollResult(status: DevicePollStatus.pending);
      case 'expired_token':
        return const DevicePollResult(status: DevicePollStatus.expired);
      case 'access_denied':
        return const DevicePollResult(
          status: DevicePollStatus.failed,
          message: '授权被拒绝，请重试',
        );
      default:
        return DevicePollResult(
          status: DevicePollStatus.failed,
          message:
              (json['error_description'] as String?) ?? error ?? '未知响应（HTTP $statusCode）',
        );
    }
  }

  static Map<String, dynamic>? _tryJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// 光鸭账户域客户端：设备码扫码、轮询、刷新。
class GuangyaAuthClient {
  GuangyaAuthClient({
    required this.identity,
    LemonHttpClient? http,
  }) : http = http ?? LemonHttpClient();

  final DeviceIdentity identity;
  final LemonHttpClient http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-client-version': '0.0.1',
        'x-sdk-version': '9.0.2',
        'x-protocol-version': '301',
        'x-device-model': 'chrome%2F147.0.0.0',
        'x-device-name': 'PC-Chrome',
        'x-device-sign': identity.sign,
        'x-os-version': 'Win32',
        'x-platform-version': '1',
        'x-provider-name': 'NONE',
        'x-net-work-type': 'NONE',
        'x-device-id': identity.deviceId,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
      };

  Future<DeviceCode> requestDeviceCode() async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('$guangyaAccountBase/v1/auth/device/code'),
        headers: _headers,
        body: {'scope': 'user', 'client_id': guangyaClientId},
      ),
    );
    if (!response.isSuccess) {
      throw LemonError(
        kind: LemonErrorKind.http,
        statusCode: response.statusCode,
        message: _snippet(response.body),
      );
    }
    final json = response.decodeJson();
    return DeviceCode.fromJson(json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json);
  }

  Future<DevicePollResult> poll(String deviceCode) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('$guangyaAccountBase/v1/auth/token'),
        headers: _headers,
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': deviceCode,
          'client_id': guangyaClientId,
        },
      ),
    );
    return DevicePollResult.decode(response.statusCode, response.body);
  }

  Future<TokenBundle> refresh(String refreshToken) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('$guangyaAccountBase/v1/auth/token'),
        headers: {
          ..._headers,
          'x-action': '401',
          'x-client-id': guangyaClientId,
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': guangyaClientId,
        },
      ),
    );
    if (!response.isSuccess) {
      throw const LemonError(
        kind: LemonErrorKind.unauthorized,
        statusCode: 401,
        message: '刷新 token 失败',
      );
    }
    final token = TokenBundle.decodeLenient(response.body);
    if (token == null) {
      throw const LemonError(
        kind: LemonErrorKind.decoding,
        message: '刷新响应缺少 access_token',
      );
    }
    return token;
  }

  static String _snippet(String text) {
    final trimmed = text.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
