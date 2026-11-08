import 'dart:io';

import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_network/lemon_network.dart';

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    this.nameCn,
    this.date,
    this.coverUrl,
    this.score,
  });

  final int id;
  final String name;
  final String? nameCn;
  final String? date;
  final String? coverUrl;
  final double? score;

  String get displayName =>
      (nameCn != null && nameCn!.isNotEmpty) ? nameCn! : name;
}

/// Bangumi v0 公开接口（搜索结果 + 分集标题）。
class BangumiClient {
  BangumiClient({LemonHttpClient? http})
      : http = http ??
            LemonHttpClient(
              config: HttpClientConfig(
                userAgent:
                    'LemonPlayer/0.1.0 (https://github.com/2744317644/LemonPlayer)',
                retryPolicy: const RetryPolicy(
                  maxAttempts: 3,
                  baseDelay: Duration(milliseconds: 800),
                ),
                proxy: _proxyFromEnvironment(),
              ),
            );

  static String? _proxyFromEnvironment() {
    final proxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'] ??
        Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];
    return (proxy == null || proxy.isEmpty) ? null : proxy;
  }

  final LemonHttpClient http;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  static final Uri _base = Uri.parse('https://api.bgm.tv');

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
    }
    _lastRequest = DateTime.now();
  }

  /// POST /v0/search/subjects（filter.type=[2] 动画）。
  Future<List<BangumiSubject>> searchSubjects(String keyword, {int limit = 5}) async {
    await _throttle();
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: _base.replace(
          path: '/v0/search/subjects',
          queryParameters: {'limit': '$limit', 'offset': '0'},
        ),
        headers: const {'Content-Type': 'application/json'},
        body: {
          'keyword': keyword,
          'filter': {
            'type': [2],
          },
        },
      ),
    );
    if (!response.isSuccess) {
      throw LemonError(
        kind: LemonErrorKind.http,
        statusCode: response.statusCode,
        message: 'Bangumi 搜索失败',
      );
    }
    final json = response.decodeJson();
    final data = json['data'];
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map((item) {
      final images = item['images'];
      String? cover;
      if (images is Map<String, dynamic>) {
        cover = images['large'] as String? ?? images['common'] as String?;
      }
      final rating = item['rating'];
      double? score;
      if (rating is Map<String, dynamic>) {
        score = (rating['score'] as num?)?.toDouble();
      }
      return BangumiSubject(
        id: (item['id'] as num).toInt(),
        name: '${item['name'] ?? ''}',
        nameCn: item['name_cn'] as String?,
        date: item['date'] as String?,
        coverUrl: cover,
        score: score,
      );
    }).toList();
  }

  /// 分集标题：ep 是本季集数（文件按本季编号），sort 是全系列集数。
  Future<Map<int, String>> episodeTitles(int subjectId) async {
    await _throttle();
    final response = await http.send(
      HttpRequestSpec(
        method: 'GET',
        uri: _base.replace(
          path: '/v0/episodes',
          queryParameters: {
            'subject_id': '$subjectId',
            'type': '0',
            'limit': '100',
            'offset': '0',
          },
        ),
        headers: const {'Accept': 'application/json'},
      ),
    );
    if (!response.isSuccess) return const {};
    final json = response.decodeJson();
    final data = json['data'];
    if (data is! List) return const {};
    final titles = <int, String>{};
    for (final item in data.whereType<Map<String, dynamic>>()) {
      final number =
          ((item['ep'] as num?) ?? (item['sort'] as num?))?.toInt() ?? 0;
      if (number <= 0) continue;
      final name = (item['name_cn'] as String?)?.isNotEmpty == true
          ? item['name_cn'] as String
          : item['name'] as String?;
      if (name != null && name.isNotEmpty) titles[number] = name;
    }
    return titles;
  }
}
