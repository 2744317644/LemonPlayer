import 'package:test/test.dart';
import 'package:lemon_guangya/lemon_guangya.dart';

void main() {
  test('开发者签名与固定向量一致', () {
    final sign = createDeveloperSign(
      clientId: 'testclient',
      clientSecret: 'testsecret',
      nonce: 'abc123',
      timestamp: 1700000000,
    );
    expect(
      sign,
      '9a4bac72b5fa98e8ce76fe620485524c3c1b5e2bc3cced493aa03f013273f399'
      'cf454b7e005b13fb08aa14422970b6056806b70c79c087fd7425953314d4c1eb',
    );
  });

  test('签名字段包含 client_id/nonce/timestamp/sign', () {
    final headers = developerSignHeaders(
      clientId: 'id',
      clientSecret: 'secret',
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      nonce: 'nonce1234567890ab',
    );
    expect(headers['client_id'], 'id');
    expect(headers['nonce'], 'nonce1234567890ab');
    expect(headers['timestamp'], '1700000000');
    expect(headers['sign'], hasLength(128));
  });

  test('文件列表响应解析（成功响应不带 code）', () {
    const body = '''
{"msg":"success","data":{"total":4,"list":[
 {"fileId":"1","fileName":"Live","resType":2,"parentId":"","depth":1},
 {"fileId":"2","fileName":"来自：云添加","resType":2,"parentId":""},
 {"fileId":"3","fileName":"番剧","resType":2,"parentId":""},
 {"fileId":"4","fileName":"ep01.mkv","resType":1,"fileType":2,"parentId":"3","fileSize":100}
]}}''';
    final page = parseFileListResponse(body);
    expect(page.total, 4);
    expect(page.items.length, 4);
    expect(page.items[1].isFolder, isTrue);
    expect(page.items[3].isPlayable, isTrue);
    expect(page.items[3].name, 'ep01.mkv');
  });

  test('fileKind 映射', () {
    expect(GuangyaFile.fromJson({'fileId': 'a', 'resType': 2}).isFolder, isTrue);
    expect(
      GuangyaFile.fromJson({'fileId': 'b', 'resType': 1, 'fileType': 2})
          .isPlayable,
      isTrue,
    );
    expect(
      GuangyaFile.fromJson({'fileId': 'c', 'resType': 1, 'fileType': 6}).kind,
      GuangyaFileKind.other,
    );
  });
}
