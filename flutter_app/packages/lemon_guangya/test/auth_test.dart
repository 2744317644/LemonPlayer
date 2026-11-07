import 'package:test/test.dart';
import 'package:lemon_guangya/lemon_guangya.dart';

void main() {
  test('设备码响应解析', () {
    final code = DeviceCode.fromJson({
      'device_code': 'dc',
      'user_code': 'USER-CODE',
      'expires_in': 120,
      'interval': 2,
      'verification_uri_complete': 'https://www.guangyapan.com/__/auth/device?code=USER-CODE',
    });
    expect(code.deviceCode, 'dc');
    expect(code.userCode, 'USER-CODE');
    expect(code.qrContent, contains('USER-CODE'));
  });

  test('轮询 pending/authorized/expired 解析', () {
    final pending = DevicePollResult.decode(
      400,
      '{"error":"authorization_pending"}',
    );
    expect(pending.status, DevicePollStatus.pending);

    final authorized = DevicePollResult.decode(
      200,
      '{"access_token":"a","refresh_token":"r","expires_in":3600,"sub":"u1"}',
    );
    expect(authorized.status, DevicePollStatus.authorized);
    expect(authorized.token?.accessToken, 'a');
    expect(authorized.token?.subject, 'u1');

    final expired = DevicePollResult.decode(
      400,
      '{"error":"expired_token"}',
    );
    expect(expired.status, DevicePollStatus.expired);
  });

  test('TokenBundle 宽容解析（data 嵌套）', () {
    final token = TokenBundle.decodeLenient(
      '{"data":{"access_token":"x","refresh_token":"y","expires_in":60}}',
    );
    expect(token?.accessToken, 'x');
    expect(token?.refreshToken, 'y');
  });

  test('直链响应解析 signedURL/downloadUrl 回退', () {
    final signed = parsePlaybackResponse(
      '{"msg":"ok","data":{"signedURL":"https://cdn.example/a.mkv?sig=1"}}',
    );
    expect(signed.url.host, 'cdn.example');
    expect(signed.headers['Referer'], 'https://www.guangyapan.com/');

    final download = parsePlaybackResponse(
      '{"msg":"ok","data":{"downloadUrl":"https://cdn.example/b.mkv"}}',
    );
    expect(download.url.path, '/b.mkv');
  });

  test('设备身份随机值格式', () {
    final identity = DeviceIdentity.random();
    expect(identity.deviceId, hasLength(32));
    expect(identity.sign, startsWith('wdi10.${identity.deviceId}'));
    expect(identity.sign.length, 'wdi10.'.length + 32 + 32);
  });
}
