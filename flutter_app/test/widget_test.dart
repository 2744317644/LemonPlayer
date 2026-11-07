import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_player/main.dart';

void main() {
  test('Phase0 样例地址有效', () {
    expect(hlsUrl, contains('m3u8'));
    expect(mkvUrl, contains('.mkv'));
  });
}
