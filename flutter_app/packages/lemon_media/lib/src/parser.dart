/// 文件名解析：标题 / 季 / 集。
class ParsedMedia {
  const ParsedMedia({required this.title, this.season, this.episode});

  final String title;
  final int? season;
  final int? episode;
}

final _bracket = RegExp(r'\[[^\]]*\]');
final _round = RegExp(r'\([^)]*\)');
final _quality = RegExp(
  r'\b(\d{3,4}p|4k|8bit|10bit|hevc|avc|x264|x265|h264|h265|bdrip|webrip|web-dl|bluray|flac|aac|chs|cht)\b',
  caseSensitive: false,
);
final _seasonCn = RegExp(r'第([0-9一二三四五六七八九十]+)季');
final _seasonEn = RegExp(r'\b(season\s*\d{1,2}|s\d{1,2})\b', caseSensitive: false);
final _episodeBracket = RegExp(r'\[(\d{1,4})(?:v\d)?\]');
final _episodeCn = RegExp(r'第(\d{1,4})[话話集]');
final _episodeSpaced = RegExp(r'[\s\-_](\d{1,4})(?:v\d)?(?:[^\d]|$)');

const _cnDigits = {
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
};

int? parseSeason(String name) {
  final cn = _seasonCn.firstMatch(name);
  if (cn != null) {
    final raw = cn.group(1)!;
    final number = int.tryParse(raw);
    if (number != null) return number;
    return _cnDigits[raw];
  }
  final en = _seasonEn.firstMatch(name);
  if (en != null) {
    final digits = RegExp(r'\d{1,2}').firstMatch(en.group(1)!);
    if (digits != null) return int.tryParse(digits.group(0)!);
  }
  return null;
}

int? parseEpisode(String name) {
  for (final pattern in [_episodeBracket, _episodeCn, _episodeSpaced]) {
    final match = pattern.firstMatch(name);
    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      if (value != null) return value;
    }
  }
  return null;
}

/// 把文件名清洗成可搜索标题。
String cleanTitle(String raw) {
  var text = raw;
  final dot = text.lastIndexOf('.');
  if (dot > 0) text = text.substring(0, dot);
  text = text.replaceAll(_bracket, ' ');
  text = text.replaceAll(_round, ' ');
  text = text.replaceAll(_quality, ' ');
  text = text.replaceAll(_seasonCn, ' ');
  text = text.replaceAll(_seasonEn, ' ');
  text = text.replaceAll(RegExp(r'[_\.]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll(RegExp(r'^[\-–—~·:：,，\s]+'), '');
  text = text.replaceAll(RegExp(r'[\-–—~·:：,，\s]+$'), '');
  // 去集号尾部（如 " - 01" / " 01"）
  text = text.replaceAll(RegExp(r'\s+\d{1,4}(?:v\d)?$'), '');
  return text.isEmpty ? raw : text;
}

ParsedMedia parseMediaName(String name) {
  return ParsedMedia(
    title: cleanTitle(name),
    season: parseSeason(name),
    episode: parseEpisode(name),
  );
}
