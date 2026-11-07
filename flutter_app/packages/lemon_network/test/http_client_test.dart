import 'package:test/test.dart';
import 'package:lemon_network/lemon_network.dart';

void main() {
  test('重试预算与状态码', () {
    const policy = RetryPolicy(maxAttempts: 3);
    expect(policy.shouldRetryStatus(503, 1), isTrue);
    expect(policy.shouldRetryStatus(503, 2), isTrue);
    expect(policy.shouldRetryStatus(503, 3), isFalse);
    expect(policy.shouldRetryStatus(403, 1), isFalse);
    expect(policy.shouldRetryStatus(429, 1), isTrue);
  });

  test('指数退避有上限', () {
    const policy = RetryPolicy(
      maxAttempts: 5,
      baseDelay: Duration(milliseconds: 500),
      maxDelay: Duration(seconds: 2),
    );
    expect(policy.delayForAttempt(1).inMilliseconds, 500);
    expect(policy.delayForAttempt(2).inMilliseconds, 1000);
    expect(policy.delayForAttempt(3).inMilliseconds, 2000);
    expect(policy.delayForAttempt(4).inMilliseconds, 2000);
  });

  test('HTTP 响应成功判断与 JSON 解码', () {
    final response = HttpResponseData(
      statusCode: 200,
      body: '{"msg":"success"}',
      headers: const {},
    );
    expect(response.isSuccess, isTrue);
    expect(response.decodeJson()['msg'], 'success');
  });
}
