import 'dart:convert';

import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_network/lemon_network.dart';

import 'device_identity.dart';
import 'models.dart';

class PlaybackLink {
  const PlaybackLink({required this.url, required this.headers});

  final Uri url;
  final Map<String, String> headers;

  static Map<String, String> playbackHeaders() => const {
        'Referer': 'https://www.guangyapan.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
      };
}

/// 用户态 API（api.guangyapan.com，Bearer access_token）。
class GuangyaUserApi {
  GuangyaUserApi({
    required this.accessToken,
    required this.identity,
    this.host = 'https://api.guangyapan.com',
    LemonHttpClient? http,
  }) : http = http ?? LemonHttpClient();

  final String accessToken;
  final DeviceIdentity identity;
  final String host;
  final LemonHttpClient http;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'did': identity.deviceId,
        'dt': '4',
        'Referer': 'https://www.guangyapan.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
      };

  Future<GuangyaPage> listFiles({
    String parentId = '',
    int page = 0,
    int pageSize = 100,
    int orderBy = 3,
    int sortType = 0,
    List<int> fileTypes = const [],
    int? resType,
  }) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('$host/userres/v1/file/get_file_list'),
        headers: _headers,
        body: {
          'parentId': parentId,
          'page': page,
          'pageSize': pageSize,
          'orderBy': orderBy,
          'sortType': sortType,
          'fileTypes': fileTypes,
          if (resType != null) 'resType': resType,
        },
      ),
    );
    if (!response.isSuccess) {
      throw LemonError(
        kind: response.statusCode == 401 || response.statusCode == 403
            ? LemonErrorKind.unauthorized
            : LemonErrorKind.http,
        statusCode: response.statusCode,
        message: _snippet(response.body),
      );
    }
    final json = response.decodeJson();
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const LemonError(
        kind: LemonErrorKind.decoding,
        message: '文件列表缺少 data',
      );
    }
    final list = (data['list'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GuangyaFile.fromJson)
        .toList();
    return GuangyaPage(
      total: (data['total'] as num?)?.toInt() ?? list.length,
      items: list,
    );
  }

  Future<PlaybackLink> playbackURL(String fileId) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('$host/userres/v1/get_res_download_url'),
        headers: _headers,
        body: {'fileId': fileId},
      ),
    );
    if (!response.isSuccess) {
      throw LemonError(
        kind: response.statusCode == 401 || response.statusCode == 403
            ? LemonErrorKind.unauthorized
            : LemonErrorKind.http,
        statusCode: response.statusCode,
        message: _snippet(response.body),
      );
    }
    final json = response.decodeJson();
    final data = json['data'];
    String? raw;
    if (data is Map<String, dynamic>) {
      final signed = data['signedURL'] as String?;
      final download = data['downloadUrl'] as String?;
      if (signed != null && signed.isNotEmpty) {
        raw = signed;
      } else if (download != null && download.isNotEmpty) {
        raw = download;
      }
    }
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null) {
      throw const LemonError(
        kind: LemonErrorKind.decoding,
        message: '响应缺少 signedURL',
      );
    }
    return PlaybackLink(url: uri, headers: PlaybackLink.playbackHeaders());
  }

  static String _snippet(String text) {
    final trimmed = text.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}

/// 解析直链响应（便于单测）。
PlaybackLink parsePlaybackResponse(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const LemonError(kind: LemonErrorKind.decoding, message: '响应不是对象');
  }
  final code = (json['code'] as num?)?.toInt() ?? 0;
  if (code != 0) {
    throw LemonError(
      kind: code == 117 ? LemonErrorKind.unauthorized : LemonErrorKind.http,
      statusCode: code == 117 ? 401 : null,
      message: '${json['msg'] ?? '未知错误'}',
    );
  }
  final data = json['data'];
  if (data is! Map<String, dynamic>) {
    throw const LemonError(kind: LemonErrorKind.decoding, message: '缺少 data');
  }
  final raw = (data['signedURL'] as String?)?.isNotEmpty == true
      ? data['signedURL'] as String
      : data['downloadUrl'] as String?;
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null) {
    throw const LemonError(kind: LemonErrorKind.decoding, message: '直链为空');
  }
  return PlaybackLink(url: uri, headers: PlaybackLink.playbackHeaders());
}
