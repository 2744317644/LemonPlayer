import 'dart:convert';
import 'dart:io';

import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:lemon_media/lemon_media.dart';

/// Phase 3 后端验证：从本机已登录会话读 token（不打印），扫描网盘并跑刮削。
Future<void> main() async {
  final prefsPath =
      '${Platform.environment['APPDATA']}\\com.lemonplayer\\lemon_player\\shared_preferences.json';
  final prefs = jsonDecode(File(prefsPath).readAsStringSync()) as Map<String, dynamic>;
  final token = prefs['flutter.lemon.access_token'] as String?;
  final identityJson =
      prefs['flutter.lemon.device_identity'] as String?;
  if (token == null || token.isEmpty) {
    stderr.writeln('未登录：缺少 access_token');
    exitCode = 2;
    return;
  }
  final identity = identityJson == null
      ? DeviceIdentity.random()
      : DeviceIdentity.fromJson(
          jsonDecode(identityJson) as Map<String, dynamic>,
        );

  final api = GuangyaUserApi(accessToken: token, identity: identity);
  stdout.writeln('扫描网盘（限制 400 目录 / 12000 文件）…');
  final media = await api.listAllMedia(maxFolders: 400, maxFiles: 12000);
  stdout.writeln('目录 ${media.folders.length}，文件 ${media.files.length}');

  final videos = videosFromScan(media.folders, media.files);
  stdout.writeln('可播放视频 ${videos.length}');

  final groups = LibraryScraper.group(videos);
  stdout.writeln('分组 ${groups.length} 部番剧');

  final bangumi = BangumiClient();
  var enriched = 0;
  for (var i = 0; i < groups.length && i < 8; i++) {
    var item = groups[i];
    try {
      item = await LibraryScraper.enrich(item, bangumi);
      if (item.bangumiId != null) enriched++;
    } catch (error) {
      stdout.writeln('  [匹配失败] ${item.title}: $error');
    }
    final samples = item.episodes
        .take(3)
        .map((e) => '${e.episode ?? "?"}:${e.displayName}')
        .join(' | ');
    stdout.writeln(
      '  ${item.title}（${item.episodes.length} 集，bangumi=${item.bangumiId ?? "-"}，'
      'year=${item.year ?? "-"}）$samples',
    );
  }
  stdout.writeln('前 8 部匹配成功 $enriched 部');
}