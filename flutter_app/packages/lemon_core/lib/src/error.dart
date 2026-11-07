/// 统一错误类型（对应 Swift 端 LemonError）。
enum LemonErrorKind {
  transport,
  http,
  unauthorized,
  decoding,
  fileNotFound,
  cancelled,
  unknown,
}

class LemonError implements Exception {
  const LemonError({
    required this.kind,
    this.statusCode,
    this.message,
    this.cause,
  });

  final LemonErrorKind kind;
  final int? statusCode;
  final String? message;
  final Object? cause;

  bool get isRetryable {
    switch (kind) {
      case LemonErrorKind.transport:
        return true;
      case LemonErrorKind.http:
        final code = statusCode ?? 0;
        return code == 408 || code == 429 || (code >= 500 && code < 600);
      default:
        return false;
    }
  }

  String get diagnosticDescription {
    switch (kind) {
      case LemonErrorKind.http:
        return 'http(${statusCode ?? '?'}): ${message ?? '无响应消息'}';
      case LemonErrorKind.unauthorized:
        return 'unauthorized(${statusCode ?? '?'}): ${message ?? '登录态失效'}';
      case LemonErrorKind.transport:
        return 'transport: ${message ?? cause ?? '网络错误'}';
      case LemonErrorKind.decoding:
        return 'decoding: ${message ?? '解析失败'}';
      case LemonErrorKind.fileNotFound:
        return 'fileNotFound: ${message ?? '文件不存在'}';
      case LemonErrorKind.cancelled:
        return 'cancelled';
      case LemonErrorKind.unknown:
        return 'unknown: ${message ?? cause ?? '未知错误'}';
    }
  }

  String get userMessage {
    switch (kind) {
      case LemonErrorKind.transport:
        return '网络连接失败：${message ?? '请检查网络'}';
      case LemonErrorKind.http:
        return '服务返回错误（HTTP ${statusCode ?? '?'}）：${message ?? '请稍后重试'}';
      case LemonErrorKind.unauthorized:
        return '登录已失效，请重新登录';
      case LemonErrorKind.decoding:
        return '数据解析失败：${message ?? ''}';
      case LemonErrorKind.fileNotFound:
        return '文件不存在或已被删除';
      case LemonErrorKind.cancelled:
        return '已取消';
      case LemonErrorKind.unknown:
        return '操作失败：${message ?? '未知错误'}';
    }
  }

  @override
  String toString() => diagnosticDescription;
}

LemonError lemonErrorFrom(Object error) {
  if (error is LemonError) return error;
  return LemonError(kind: LemonErrorKind.unknown, cause: error);
}

/// 滚动诊断日志（内存环形缓冲，脱敏规则与 Swift 端一致）。
class Diagnostics {
  Diagnostics({this.maxEntries = 800});

  final int maxEntries;
  final List<DiagnosticEntry> _entries = [];

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  void log(String category, String message, {String level = 'info'}) {
    _entries.add(
      DiagnosticEntry(
        time: DateTime.now(),
        level: level,
        category: category,
        message: Redactor.scrub(message),
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  void logError(String category, LemonError error) =>
      log(category, error.diagnosticDescription, level: 'error');

  void clear() => _entries.clear();

  String summary({int limit = 100}) {
    final list = _entries.length > limit
        ? _entries.sublist(_entries.length - limit)
        : _entries;
    return list
        .map((e) => '[${e.time.toIso8601String()}] [${e.level}] [${e.category}] ${e.message}')
        .join('\n');
  }

  static final Diagnostics shared = Diagnostics();
}

class DiagnosticEntry {
  DiagnosticEntry({
    required this.time,
    required this.level,
    required this.category,
    required this.message,
  });

  final DateTime time;
  final String level;
  final String category;
  final String message;
}

/// 导出/展示前脱敏。
class Redactor {
  static final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+');
  static final RegExp _kv = RegExp(
    r'(token|sign|signature|auth|key|secret)=([^&\s"]+)',
    caseSensitive: false,
  );

  static String scrub(String text) => text
      .replaceAll(_bearer, 'Bearer ***')
      .replaceAllMapped(_kv, (m) => '${m.group(1)}=***');
}
