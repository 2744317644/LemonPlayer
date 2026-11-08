import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lemon_core/lemon_core.dart';

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 4),
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Set<int> retryableStatusCodes;

  bool shouldRetryStatus(int statusCode, int attempt) =>
      attempt < maxAttempts && retryableStatusCodes.contains(statusCode);

  Duration delayForAttempt(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << (attempt - 1).clamp(0, 20));
    return Duration(
      milliseconds: ms.clamp(0, maxDelay.inMilliseconds),
    );
  }
}

class HttpClientConfig {
  const HttpClientConfig({
    this.userAgent = 'LemonPlayer/0.1.0 (https://github.com/2744317644/LemonPlayer)',
    this.timeout = const Duration(seconds: 30),
    this.retryPolicy = const RetryPolicy(),
    this.defaultHeaders = const {},
    this.proxy,
  });

  final String userAgent;
  final Duration timeout;
  final RetryPolicy retryPolicy;
  final Map<String, String> defaultHeaders;

  /// 可选 HTTP 代理（如 http://127.0.0.1:7890），用于访问被墙服务。
  final String? proxy;
}

class HttpRequestSpec {
  const HttpRequestSpec({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
    this.timeout,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
  final Duration? timeout;
}

class HttpResponseData {
  const HttpResponseData({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> decodeJson() {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const LemonError(
        kind: LemonErrorKind.decoding,
        message: '响应不是 JSON 对象',
      );
    }
    return decoded;
  }
}

class LemonHttpClient {
  LemonHttpClient({
    this.config = const HttpClientConfig(),
    Diagnostics? diagnostics,
  }) : diagnostics = diagnostics ?? Diagnostics.shared;

  final HttpClientConfig config;
  final Diagnostics diagnostics;
  late final HttpClient _client = _createClient();

  HttpClient _createClient() {
    final client = HttpClient();
    final proxy = config.proxy;
    if (proxy != null && proxy.isNotEmpty) {
      final uri = Uri.tryParse(proxy);
      if (uri != null && uri.host.isNotEmpty) {
        client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
      }
    }
    return client;
  }

  Future<HttpResponseData> send(HttpRequestSpec spec) async {
    final target = '${spec.method} ${spec.uri.host}${spec.uri.path}';
    final retry = config.retryPolicy;
    var attempt = 0;

    while (true) {
      attempt++;
      final started = DateTime.now();
      try {
        final request = await _client
            .openUrl(spec.method, spec.uri)
            .timeout(spec.timeout ?? config.timeout);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          config.userAgent,
        );
        for (final entry in {...config.defaultHeaders, ...spec.headers}.entries) {
          request.headers.set(entry.key, entry.value);
        }
        if (spec.body != null) {
          final body = spec.body;
          final text = body is String ? body : jsonEncode(body);
          if (request.headers.contentType == null) {
            request.headers.contentType = ContentType.json;
          }
          request.write(text);
        }

        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        diagnostics.log(
          'network',
          '$target -> ${response.statusCode} ${elapsed}ms (attempt $attempt)',
          level: response.statusCode >= 400 ? 'warning' : 'debug',
        );

        if (retry.shouldRetryStatus(response.statusCode, attempt)) {
          final delay = retry.delayForAttempt(attempt);
          diagnostics.log(
            'network',
            '$target 重试 ${attempt + 1}/${retry.maxAttempts}，'
            '${delay.inMilliseconds}ms 后（上次 HTTP ${response.statusCode}）',
            level: 'warning',
          );
          await Future<void>.delayed(delay);
          continue;
        }

        final headers = <String, String>{};
        response.headers.forEach((name, values) {
          headers[name] = values.join(',');
        });
        return HttpResponseData(
          statusCode: response.statusCode,
          body: text,
          headers: headers,
        );
      } on TimeoutException catch (error) {
        if (attempt < retry.maxAttempts) {
          await Future<void>.delayed(retry.delayForAttempt(attempt));
          continue;
        }
        diagnostics.log('network', '$target timeout: $error', level: 'error');
        throw LemonError(
          kind: LemonErrorKind.transport,
          message: '请求超时',
          cause: error,
        );
      } on SocketException catch (error) {
        if (attempt < retry.maxAttempts) {
          await Future<void>.delayed(retry.delayForAttempt(attempt));
          continue;
        }
        diagnostics.log('network', '$target socket: $error', level: 'error');
        throw LemonError(
          kind: LemonErrorKind.transport,
          message: error.message,
          cause: error,
        );
      } on HttpException catch (error) {
        diagnostics.log('network', '$target http: $error', level: 'error');
        throw LemonError(
          kind: LemonErrorKind.transport,
          message: error.message,
          cause: error,
        );
      }
    }
  }

  /// 串行限流：两次请求之间至少间隔 `minimumInterval`。
  Future<void> rateLimit(Duration minimumInterval) async {
    final elapsed = DateTime.now().difference(_lastRequestAt);
    if (elapsed < minimumInterval) {
      await Future<void>.delayed(minimumInterval - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
}
