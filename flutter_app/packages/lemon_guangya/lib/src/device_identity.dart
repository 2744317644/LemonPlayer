import 'dart:math';

/// 光鸭设备标识（did 为 32 位 hex；sign 形如 `wdi10.<did><32 hex>`）。
/// 与账号 token 绑定，必须持久化，不能每次登录重新生成。
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.sign});

  final String deviceId;
  final String sign;

  factory DeviceIdentity.random({Random? random}) {
    final deviceId = _randomHex(16, random);
    return DeviceIdentity(
      deviceId: deviceId,
      sign: 'wdi10.$deviceId${_randomHex(16, random)}',
    );
  }

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
        deviceId: json['deviceId'] as String? ?? '',
        sign: json['sign'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'sign': sign};

  static String _randomHex(int bytes, Random? random) {
    final source = random ?? Random.secure();
    return List.generate(
      bytes,
      (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
