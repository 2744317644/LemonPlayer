import 'dart:convert';

import 'package:lemon_guangya/lemon_guangya.dart';

import 'bangumi.dart';
import 'matcher.dart';
import 'parser.dart';
import 'resolver.dart';

/// 一个视频文件 + 其所属番剧目录信息。
class LibraryVideo {
  const LibraryVideo({
    required this.file,
    this.seriesFolderId,
    this.seriesFolderName,
  });

  final GuangyaFile file;
  final String? seriesFolderId;
  final String? seriesFolderName;
}

class LibraryEpisode {
  const LibraryEpisode({
    required this.file,
    this.episode,
    this.title,
  });

  final GuangyaFile file;
  final int? episode;
  final String? title;

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (episode != null) return '第$episode话';
    return file.name;
  }
}

class LibrarySeries {
  const LibrarySeries({
    required this.id,
    required this.title,
    required this.folderName,
    required this.episodes,
    this.bangumiId,
    this.coverUrl,
    this.year,
    this.score,
  });

  final String id;
  final String title;
  final String folderName;
  final List<LibraryEpisode> episodes;
  final int? bangumiId;
  final String? coverUrl;
  final int? year;
  final double? score;
}

/// 按「番剧目录」分组，再匹配 Bangumi，生成媒体库条目。
class LibraryScraper {
  static List<LibrarySeries> group(List<LibraryVideo> videos) {
    final buckets = <String, List<LibraryVideo>>{};
    final meta = <String, ({String title, String folderName})>{};

    for (final video in videos) {
      if (SeriesFolderResolver.isNoiseFile(video.file.name)) continue;
      final parsed = parseMediaName(video.file.name);
      final folderId = video.seriesFolderId;
      final folderName = video.seriesFolderName;
      final key = (folderId != null && folderId.isNotEmpty)
          ? 'folder:$folderId#${parsed.season ?? 1}'
          : 'title:${parsed.title.toLowerCase()}#${parsed.season ?? 1}';
      buckets.putIfAbsent(key, () => []).add(video);
      meta.putIfAbsent(
        key,
        () => (
          title: folderName != null && folderName.isNotEmpty
              ? SeriesFolderResolver.cleanTitle(folderName)
              : parsed.title,
          folderName: folderName ?? '',
        ),
      );
    }

    final series = <LibrarySeries>[];
    for (final entry in buckets.entries) {
      final info = meta[entry.key]!;
      final episodes = entry.value
          .map((video) => LibraryEpisode(
                file: video.file,
                episode: parseMediaName(video.file.name).episode,
              ))
          .toList()
        ..sort((a, b) => (a.episode ?? 1 << 30)
            .compareTo(b.episode ?? 1 << 30));
      series.add(LibrarySeries(
        id: entry.key,
        title: info.title,
        folderName: info.folderName,
        episodes: episodes,
      ));
    }
    return series;
  }

  /// 匹配 Bangumi：搜索 → TitleMatcher 选最佳 → 拉分集标题。
  static Future<LibrarySeries> enrich(
    LibrarySeries series,
    BangumiClient bangumi,
  ) async {
    final subjects = await bangumi.searchSubjects(series.title);
    if (subjects.isEmpty) return series;
    final index = TitleMatcher.pickBest(
      series.title,
      subjects.map((s) => s.displayName).toList(),
    );
    if (index == null) return series;
    final subject = subjects[index];
    final titles = await bangumi.episodeTitles(subject.id);
    final episodes = series.episodes.map((episode) {
      final title = episode.episode == null ? null : titles[episode.episode!];
      return LibraryEpisode(
        file: episode.file,
        episode: episode.episode,
        title: title,
      );
    }).toList();
    return LibrarySeries(
      id: series.id,
      title: subject.displayName,
      folderName: series.folderName,
      episodes: episodes,
      bangumiId: subject.id,
      coverUrl: subject.coverUrl,
      year: int.tryParse((subject.date ?? '').split('-').first),
      score: subject.score,
    );
  }
}

/// 从 Guangya 扫描结果生成 LibraryVideo（还原目录树）。
List<LibraryVideo> videosFromScan(
  List<GuangyaFile> folders,
  List<GuangyaFile> files,
) {
  final folderMap = {
    for (final folder in folders)
      folder.id: LibraryFolderNode(
        id: folder.id,
        parentId: folder.parentId,
        name: folder.name,
      ),
  };
  final videos = <LibraryVideo>[];
  for (final file in files.where((f) => f.isPlayable)) {
    if (SeriesFolderResolver.isNoiseFile(file.name)) continue;
    final parent = folderMap[file.parentId];
    if (parent != null && SeriesFolderResolver.isNoiseFolder(parent.name)) {
      continue;
    }
    final resolved =
        SeriesFolderResolver.resolveSeriesFolder(file.parentId, folderMap);
    videos.add(LibraryVideo(
      file: file,
      seriesFolderId: resolved?.id,
      seriesFolderName: resolved?.name,
    ));
  }
  return videos;
}

String dumpSeriesJson(List<LibrarySeries> series) => jsonEncode([
      for (final item in series)
        {
          'title': item.title,
          'folder': item.folderName,
          'bangumiId': item.bangumiId,
          'cover': item.coverUrl,
          'episodes': [
            for (final episode in item.episodes)
              {
                'episode': episode.episode,
                'title': episode.title,
                'file': episode.file.name,
              }
          ],
        }
    ]);
