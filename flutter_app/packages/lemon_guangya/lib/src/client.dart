import 'dart:convert';

import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_network/lemon_network.dart';

import 'models.dart';
import 'sign.dart';

class GuangyaConfig {
  const GuangyaConfig({
    required this.clientId,
    required this.clientSecret,
    this.host = 'https://dapi.guangyapan.com',
  });

  final String clientId;
  final String clientSecret;
  final String host;
}

/// 光鸭开发者 API v1.1（dapi）客户端。
class GuangyaApi {
  GuangyaApi({
    required this.config,
    LemonHttpClient? http,
  }) : http = http ?? LemonHttpClient();

  final GuangyaConfig config;
  final LemonHttpClient http;

  Map<String, String> get _signedHeaders => developerSignHeaders(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
      );

  Future<GuangyaPage> listFiles({
    String parentId = '',
    int page = 0,
    int pageSize = 100,
    int orderBy = 3,
    int sortType = 0,
    List<int>? fileTypes,
  }) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('${config.host}/userres/v1/file/get_file_list'),
        headers: _signedHeaders,
        body: {
          'parentId': parentId,
          'page': page,
          'pageSize': pageSize,
          'orderBy': orderBy,
          'sortType': sortType,
          if (fileTypes != null) 'fileTypes': fileTypes,
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

  /// 递归扫描全盘（目录 + 文件）。
  Future<({List<GuangyaFile> folders, List<GuangyaFile> files})> listAllMedia({
    int pageSize = 100,
    int maxFolders = 2000,
    int maxFiles = 50000,
  }) async {
    final folders = <GuangyaFile>[];
    final files = <GuangyaFile>[];
    final queue = <String>[''];
    final visited = <String>{};

    while (queue.isNotEmpty && folders.length < maxFolders && files.length < maxFiles) {
      final parent = queue.removeAt(0);
      if (!visited.add(parent)) continue;
      var page = 0;
      while (page < 50) {
        final result = await listFiles(
          parentId: parent,
          page: page,
          pageSize: pageSize,
        );
        for (final item in result.items) {
          if (item.isFolder) {
            if (folders.length < maxFolders) {
              folders.add(item);
              queue.add(item.id);
            }
          } else if (files.length < maxFiles) {
            files.add(item);
          }
        }
        if (result.items.length < pageSize) break;
        page++;
      }
    }
    return (folders: folders, files: files);
  }

  Future<String> playbackURL(String fileId) async {
    final response = await http.send(
      HttpRequestSpec(
        method: 'POST',
        uri: Uri.parse('${config.host}/userres/v1/get_res_download_url'),
        headers: _signedHeaders,
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
    final url = data is Map<String, dynamic> ? data['signedURL'] as String? : null;
    if (url == null || url.isEmpty) {
      throw const LemonError(
        kind: LemonErrorKind.decoding,
        message: '响应缺少 signedURL',
      );
    }
    return url;
  }

  static String _snippet(String text) {
    final trimmed = text.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}

/// 解析文件列表响应（便于单测，不依赖网络）。
GuangyaPage parseFileListResponse(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const LemonError(kind: LemonErrorKind.decoding, message: '响应不是对象');
  }
  final data = json['data'];
  if (data is! Map<String, dynamic>) {
    throw const LemonError(kind: LemonErrorKind.decoding, message: '缺少 data');
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
