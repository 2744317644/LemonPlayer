import 'parser.dart';

/// 标题匹配：季数识别 + Levenshtein 相似度（对应 Swift 端 TitleMatcher）。
class TitleMatcher {
  static int? extractSeason(String title) {
    final season = parseSeason(title);
    if (season != null) return season;
    // ②/③/④/Ⅱ/Ⅲ/∬
    const markers = {'②': 2, '③': 3, '④': 4, 'Ⅱ': 2, 'Ⅲ': 3, '∬': 2};
    for (final entry in markers.entries) {
      if (title.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static bool seasonMentioned(String title, int season) {
    final markers = <String>[
      '第${season}季',
      'Season $season',
      'S${season.toString().padLeft(2, '0')}',
      'S$season',
    ];
    if (season == 2) markers.addAll(['②', 'Ⅱ', '∬', '第二季']);
    if (season == 3) markers.addAll(['③', 'Ⅲ', '第三季']);
    if (season == 4) markers.addAll(['④', 'Ⅳ', '第四季']);
    return markers.any(title.contains);
  }

  static String _normalize(String text) {
    return cleanTitle(text)
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-–—·:：,，!！?？]'), '')
        .replaceAll(RegExp(r'''['’"“”()（）\[\]【】]'''), '');
  }

  static double similarity(String a, String b) {
    final x = _normalize(a);
    final y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    final previous = List<int>.generate(y.length + 1, (i) => i);
    final current = List<int>.filled(y.length + 1, 0);
    for (var i = 1; i <= x.length; i++) {
      current[0] = i;
      for (var j = 1; j <= y.length; j++) {
        final cost = x[i - 1] == y[j - 1] ? 0 : 1;
        final insert = previous[j] + 1;
        final delete = current[j - 1] + 1;
        final replace = previous[j - 1] + cost;
        current[j] = insert < delete
            ? (insert < replace ? insert : replace)
            : (delete < replace ? delete : replace);
      }
      for (var k = 0; k <= y.length; k++) {
        previous[k] = current[k];
      }
    }
    final distance = previous[y.length];
    return 1 - distance / (x.length > y.length ? x.length : y.length);
  }

  /// 在候选标题里选最匹配；罗马音标题（无中文）相似度不达标时信任搜索第一条。
  static int? pickBest(String title, List<String> candidates) {
    final season = extractSeason(title);
    int? bestIndex;
    var bestScore = 0.0;
    for (var i = 0; i < candidates.length; i++) {
      var score = similarity(title, candidates[i]);
      if (season != null && season > 1) {
        if (seasonMentioned(candidates[i], season)) {
          score += 0.3;
        } else {
          final others = [2, 3, 4, 5]
              .where((s) => s != season && seasonMentioned(candidates[i], s));
          if (others.isNotEmpty) score -= 0.25;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex == null || bestScore < 0.55) {
      final hasHan = RegExp(r'[\u4e00-\u9fff]').hasMatch(title);
      if (!hasHan && candidates.isNotEmpty) return 0;
      return null;
    }
    if (season != null && season > 1) {
      final candidate = candidates[bestIndex];
      if (!seasonMentioned(candidate, season)) return null;
    }
    return bestIndex;
  }
}
