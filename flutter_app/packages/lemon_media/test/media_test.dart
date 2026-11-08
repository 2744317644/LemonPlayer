import 'package:test/test.dart';
import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:lemon_media/lemon_media.dart';

void main() {
  GuangyaFile file(String id, String name, String parentId) => GuangyaFile(
        id: id,
        parentId: parentId,
        name: name,
        size: 100,
        kind: GuangyaFileKind.video,
      );

  test('文件名解析：集号/季/标题', () {
    final parsed = parseMediaName(
      '[DBD-Raws][孤独摇滚!][08][1080P][BDRip][HEVC-10bit][FLAC].mkv',
    );
    expect(parsed.episode, 8);
    expect(parsed.title, contains('孤独摇滚'));
    expect(parseSeason('Sousou no Frieren S02'), 2);
    expect(parseMediaName('Show - 12.mkv').episode, 12);
  });

  test('目录规则：Fonts/OP/ED 向上取父目录', () {
    final folders = {
      'series': const LibraryFolderNode(id: 'series', parentId: '', name: '葬送的芙莉莲'),
      'fonts': const LibraryFolderNode(id: 'fonts', parentId: 'series', name: 'Fonts'),
      'op': const LibraryFolderNode(id: 'op', parentId: 'series', name: 'OP'),
    };
    expect(SeriesFolderResolver.resolveSeriesFolder('fonts', folders)?.id, 'series');
    expect(SeriesFolderResolver.resolveSeriesFolder('op', folders)?.id, 'series');
    expect(SeriesFolderResolver.isNoiseFolder('Fonts'), isTrue);
    expect(SeriesFolderResolver.isNoiseFolder('OP&ED'), isTrue);
    expect(SeriesFolderResolver.isNoiseFile('[NCOP] a.mkv'), isTrue);
    expect(SeriesFolderResolver.isNoiseFile('[NCED] b.mkv'), isTrue);
    expect(SeriesFolderResolver.isNoiseFile('Show - 01.mkv'), isFalse);
  });

  test('季数识别与相似度', () {
    expect(TitleMatcher.extractSeason('约会大作战 第三季'), 3);
    expect(TitleMatcher.extractSeason('五等分の花嫁∬'), 2);
    expect(TitleMatcher.seasonMentioned('约会大作战 第三季', 3), isTrue);
    expect(TitleMatcher.similarity('孤独摇滚', '孤独摇滚！'), greaterThan(0.6));
  });

  test('匹配优先正确季', () {
    final candidates = ['约会大作战', '约会大作战 第二季', '约会大作战 第三季'];
    expect(TitleMatcher.pickBest('约会大作战 第三季', candidates), 2);
    expect(TitleMatcher.pickBest('约会大作战 第四季', candidates), isNull);
  });

  test('按目录分组 + 排除 NCOP/NCED 文件', () {
    final videos = [
      LibraryVideo(
        file: file('1', 'Show - 01.mkv', 'series'),
        seriesFolderId: 'series',
        seriesFolderName: '[Group] Show',
      ),
      LibraryVideo(
        file: file('2', 'Show - 02.mkv', 'series'),
        seriesFolderId: 'series',
        seriesFolderName: '[Group] Show',
      ),
      LibraryVideo(
        file: file('3', '[NCOP] Show.mkv', 'series'),
        seriesFolderId: 'series',
        seriesFolderName: '[Group] Show',
      ),
    ];
    final series = LibraryScraper.group(videos);
    expect(series.length, 1);
    expect(series.first.episodes.length, 2);
  });

  test('扫描结果还原目录树', () {
    final folders = [
      GuangyaFile(
        id: 'root',
        parentId: '',
        name: '番剧',
        size: 0,
        kind: GuangyaFileKind.folder,
      ),
      GuangyaFile(
        id: 'series',
        parentId: 'root',
        name: '孤独摇滚！',
        size: 0,
        kind: GuangyaFileKind.folder,
      ),
    ];
    final files = [
      file('1', 'Show - 01.mkv', 'series'),
      file('2', '[NCOP] a.mkv', 'series'),
      file('3', 'lrc.mkv', 'root'),
    ];
    final videos = videosFromScan(folders, files);
    expect(videos.length, 2);
    expect(videos.first.seriesFolderName, '孤独摇滚！');
  });
}
