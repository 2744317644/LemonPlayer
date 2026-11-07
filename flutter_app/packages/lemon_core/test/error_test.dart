import 'package:test/test.dart';
import 'package:lemon_core/lemon_core.dart';

void main() {
  test('http 错误状态码与可重试判断', () {
    final error = LemonError(
      kind: LemonErrorKind.http,
      statusCode: 503,
      message: 'busy',
    );
    expect(error.statusCode, 503);
    expect(error.isRetryable, isTrue);
    expect(error.diagnosticDescription, 'http(503): busy');

    expect(
      const LemonError(kind: LemonErrorKind.http, statusCode: 403)
          .isRetryable,
      isFalse,
    );
    expect(
      const LemonError(kind: LemonErrorKind.transport, message: 'timeout')
          .isRetryable,
      isTrue,
    );
  });

  test('脱敏 Bearer 与 token 参数', () {
    final scrubbed = Redactor.scrub(
      'Authorization: Bearer abc.def.ghi&access_token=secret123',
    );
    expect(scrubbed, contains('Bearer ***'));
    expect(scrubbed, isNot(contains('secret123')));
  });

  test('诊断日志保留最近条目', () {
    final diagnostics = Diagnostics(maxEntries: 3);
    for (var i = 0; i < 5; i++) {
      diagnostics.log('test', 'line $i');
    }
    expect(diagnostics.entries.length, 3);
    expect(diagnostics.entries.first.message, 'line 2');
    expect(diagnostics.summary(), contains('line 4'));
  });
}
