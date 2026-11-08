/// 媒体库目录节点（id/父 id/名称）。
class LibraryFolderNode {
  const LibraryFolderNode({
    required this.id,
    required this.parentId,
    required this.name,
  });

  final String id;
  final String parentId;
  final String name;
}

/// 目录 → 番剧规则：最底层目录一部番；附属目录向上取父目录。
class SeriesFolderResolver {
  static const noiseTokens = {
    'font', 'fonts', 'op', 'ops', 'ed', 'eds', 'oped', 'opeds',
    'sp', 'sps', 'special', 'specials', 'ncop', 'nced', 'nc', 'menu',
    'scan', 'scans', 'cd', 'cds', 'ost', 'soundtrack', 'music', 'mv',
    'pv', 'preview', 'cm', 'extras', 'extra', 'bonus', 'tokuten',
    'sub', 'subs', 'subtitle', 'subtitles', 'booklet', 'artbook', 'art',
    'creditless', 'clean', 'logo', 'trailer', 'teaser', 'sample',
  };

  static const noiseChinese = [
    '字体', '字幕', '特典', '映像', '番外', '原声', '画集', '周边',
    '歌词', '歌詞', '预告', '花絮', '扫描', '扫图', '音乐', '菜单',
  ];

  static const qualityTokens = {
    '1080p', '720p', '2160p', '480p', '4k', '8bit', '10bit', 'hevc',
    'avc', 'x264', 'x265', 'h264', 'h265', 'bdrip', 'webrip', 'web-dl',
    'bluray', 'flac', 'aac', 'chs', 'cht', '简繁', '简中', '繁中',
    '内封', '内嵌', '外挂', '双语',
  };

  static bool isNoiseFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    for (final keyword in noiseChinese) {
      if (trimmed.contains(keyword)) return true;
    }
    final tokens = trimmed
        .toLowerCase()
        .split(RegExp(r'[^0-9a-z]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return false;
    if (tokens.every(noiseTokens.contains)) return true;
    return tokens.length == 1 && noiseTokens.contains(tokens.first);
  }

  static bool isSeasonFolder(String name) {
    final lowered =
        name.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    if (RegExp(r'^(season|s)\d{1,2}$').hasMatch(lowered)) return true;
    return RegExp(r'^第[0-9一二三四五六七八九十]+季$').hasMatch(name);
  }

  static bool isQualityFolder(String name) {
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'[\[\]()（）【】_]'), ' ')
        .split(RegExp(r'[^0-9a-z\u4e00-\u9fff]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;
    final hits = words
        .where((w) =>
            qualityTokens.contains(w) || RegExp(r'^\d{3,4}p$').hasMatch(w))
        .length;
    return hits >= (words.length - 1).clamp(1, words.length);
  }

  static LibraryFolderNode? resolveSeriesFolder(
    String parentId,
    Map<String, LibraryFolderNode> folders, {
    int maxDepth = 8,
  }) {
    var current = parentId;
    LibraryFolderNode? last;
    var depth = 0;
    while (depth < maxDepth && current.isNotEmpty) {
      final node = folders[current];
      if (node == null) break;
      last = node;
      if (isNoiseFolder(node.name) ||
          isSeasonFolder(node.name) ||
          isQualityFolder(node.name)) {
        current = node.parentId;
        depth++;
        continue;
      }
      return node;
    }
    return last;
  }

  /// 文件名是否是 OP/ED/NCOP/NCED/PV/CM/SP 等附属视频。
  static bool isNoiseFile(String fileName) {
    final base = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final candidates = <String>[
      ...RegExp(r'[\[【（(]([^\]】）)]+)[\]】）)]')
          .allMatches(base)
          .map((m) => m.group(1) ?? ''),
      base,
    ];
    for (final candidate in candidates) {
      final lowered = candidate.toLowerCase();
      final tokens = lowered
          .split(RegExp(r'[^0-9a-z]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.any(noiseTokens.contains)) return true;
      if (RegExp(r'^(ncop|nced|op|ed|sp|pv|cm)\d{0,3}(?:[\s\-_]|$)')
          .hasMatch(lowered)) {
        return true;
      }
    }
    return false;
  }

  /// 目录名清洗成可搜索标题。
  static String cleanTitle(String raw) {
    var text = raw;
    for (final pattern in [
      RegExp(r'\[[^\]]*\]'),
      RegExp(r'\([^)]*\)'),
      RegExp(r'【[^】]*】'),
      RegExp(r'（[^）]*）'),
    ]) {
      text = text.replaceAll(pattern, ' ');
    }
    text = text.replaceAll(
      RegExp(
        r'\b(\d{3,4}p|4k|8bit|10bit|hevc|avc|x264|x265|h264|h265|bdrip|webrip|web-dl|bluray|flac|aac|chs|cht)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'[_\.]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'^[\-–—~·:：,，\s]+'), '');
    text = text.replaceAll(RegExp(r'[\-–—~·:：,，\s]+$'), '');
    if (text.isNotEmpty) return text;

    final candidates = RegExp(r'[\[【（(]([^\]】）)]+)[\]】）)]')
        .allMatches(raw)
        .map((m) => m.group(1) ?? '')
        .where((c) => c.isNotEmpty && !isNoiseFolder(c) && !isQualityFolder(c))
        .toList();
    if (candidates.isEmpty) return raw;
    candidates.sort((a, b) {
      var sa = a.length;
      var sb = b.length;
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(a)) sa += 20;
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(b)) sb += 20;
      if (a.contains(' ')) sa += 5;
      if (b.contains(' ')) sb += 5;
      return sb.compareTo(sa);
    });
    return candidates.first;
  }
}
