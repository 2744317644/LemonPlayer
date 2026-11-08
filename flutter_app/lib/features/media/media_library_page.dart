import 'package:flutter/material.dart';
import 'package:lemon_media/lemon_media.dart';

import '../../app/session_store.dart';
import '../player/player_page.dart';

/// Phase 3：媒体库（扫描 → 分组 → Bangumi 匹配 → 海报墙）
class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key, required this.session});

  final SessionStore session;

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  bool _scanning = false;
  String? _status;
  String? _error;
  List<LibrarySeries> _series = [];

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _status = '正在扫描网盘…';
      _series = [];
    });
    try {
      final api = widget.session.createApi();
      final media = await api.listAllMedia(
        maxFolders: 2000,
        maxFiles: 50000,
      );
      final videos = videosFromScan(media.folders, media.files);
      var groups = LibraryScraper.group(videos);
      setState(() => _status = '找到 ${groups.length} 部番剧，匹配 Bangumi…');

      final bangumi = BangumiClient();
      final enriched = <LibrarySeries>[];
      for (var i = 0; i < groups.length; i++) {
        var item = groups[i];
        try {
          item = await LibraryScraper.enrich(item, bangumi);
        } catch (_) {
          // 单部匹配失败不影响扫描
        }
        enriched.add(item);
        if (mounted) {
          setState(() {
            _series = List.of(enriched);
            _status = '匹配 ${i + 1}/${groups.length}…';
          });
        }
      }
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = '共 ${enriched.length} 部番剧';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _scan, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scanning) const CircularProgressIndicator(),
            if (_scanning) const SizedBox(height: 12),
            Text(_status ?? '还没有媒体库'),
            const SizedBox(height: 16),
            if (!_scanning)
              FilledButton(onPressed: _scan, child: const Text('扫描网盘')),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_scanning) const LinearProgressIndicator(),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _status!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemCount: _series.length,
            itemBuilder: (context, index) {
              final item = _series[index];
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeriesDetailPage(
                      session: widget.session,
                      series: item,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.coverUrl == null
                            ? Container(
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: const Icon(Icons.movie, size: 36),
                              )
                            : Image.network(
                                item.coverUrl!,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.black12,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.movie, size: 36),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${item.episodes.length} 集'
                      '${item.year != null ? " · ${item.year}" : ""}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SeriesDetailPage extends StatelessWidget {
  const SeriesDetailPage({
    super.key,
    required this.session,
    required this.series,
  });

  final SessionStore session;
  final LibrarySeries series;

  @override
  Widget build(BuildContext context) {
    final files = series.episodes.map((e) => e.file).toList();
    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: ListView.separated(
        itemCount: series.episodes.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final episode = series.episodes[index];
          return ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(episode.displayName),
            subtitle: Text(
              episode.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerPage(
                  session: session,
                  file: episode.file,
                  videos: files,
                  startIndex: index,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
