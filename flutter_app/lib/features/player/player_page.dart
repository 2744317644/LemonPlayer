import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/session_store.dart';

/// Phase 2：VidHub 风格播放页
/// - 单击显示/隐藏控制层；双击左/中/右快退、播放暂停、快进
/// - 底部进度条（点击/拖动 seek）+ 倍速/字幕/音轨面板
/// - 同目录剧集队列（上一集/下一集/选集）
/// - 自动匹配同目录字幕（ASS/SRT/VTT），ASS 走 libass
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.session,
    required this.file,
    this.videos = const [],
    this.startIndex = 0,
  });

  final SessionStore session;
  final GuangyaFile file;
  final List<GuangyaFile> videos;
  final int startIndex;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(libass: true),
  );
  late final VideoController _controller = VideoController(_player);
  late final List<GuangyaFile> _videos = widget.videos.isEmpty
      ? [widget.file]
      : widget.videos;
  late int _index = widget.videos.isEmpty
      ? 0
      : widget.startIndex.clamp(0, widget.videos.length - 1);

  bool _loading = true;
  bool _playing = false;
  bool _controlsVisible = true;
  bool _seeking = false;
  String? _error;
  String? _subtitleStatus;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  double? _scrubTarget;

  List<GuangyaFile> _subtitleFiles = [];
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;

  GuangyaFile get _current => _videos[_index];
  bool get _hasQueue => _videos.length > 1;

  @override
  void initState() {
    super.initState();
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _positionSub = _player.stream.position.listen((position) {
      if (mounted && !_seeking) setState(() => _position = position);
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _errorSub = _player.stream.error.listen((error) {
      if (mounted) setState(() => _error = error);
    });
    _openCurrent();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _openCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
      _subtitleStatus = null;
      _subtitleFiles = [];
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      final api = widget.session.createApi();
      final link = await api.playbackURL(_current.id);
      await _player.open(
        Media(link.url.toString(), httpHeaders: link.headers),
        play: true,
      );
      if (mounted) setState(() => _loading = false);
      await _loadSubtitleCandidates(api);
      await _autoAttachSubtitle(api);
      _scheduleHide();
    } on LemonError catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.userMessage;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _loadSubtitleCandidates(GuangyaUserApi api) async {
    try {
      final page = await api.listFiles(
        parentId: _current.parentId,
        pageSize: 200,
      );
      final subs = page.items.where((f) {
        final lower = f.name.toLowerCase();
        return lower.endsWith('.ass') ||
            lower.endsWith('.ssa') ||
            lower.endsWith('.srt') ||
            lower.endsWith('.vtt');
      }).toList();
      if (mounted) setState(() => _subtitleFiles = subs);
    } catch (_) {
      // 字幕列表失败不影响播放
    }
  }

  Future<void> _autoAttachSubtitle(GuangyaUserApi api) async {
    final candidate = _bestSubtitle();
    if (candidate == null) {
      if (mounted) setState(() => _subtitleStatus = '字幕：同目录未找到');
      return;
    }
    final file = await _materializeSubtitle(api, candidate);
    if (file == null) return;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(file.uri.toString(), title: candidate.name),
    );
    if (mounted) setState(() => _subtitleStatus = '字幕：${candidate.name}');
  }

  GuangyaFile? _bestSubtitle() {
    if (_subtitleFiles.isEmpty) return null;
    final videoEpisode = _episodeNumber(_current.name);
    final videoBase = _baseName(_current.name);
    final scored = <(int, GuangyaFile)>[];
    for (final sub in _subtitleFiles) {
      var score = 0;
      final subBase = _baseName(sub.name);
      if (subBase.isNotEmpty && videoBase.contains(subBase)) score += 3;
      final subEpisode = _episodeNumber(sub.name);
      if (videoEpisode != null && subEpisode == videoEpisode) score += 5;
      if (sub.name.toLowerCase().endsWith('.ass')) score += 2;
      if (sub.name.toLowerCase().contains('chs') ||
          sub.name.toLowerCase().contains('简')) {
        score += 1;
      }
      if (score > 0) scored.add((score, sub));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.first.$2;
  }

  /// 下载字幕到 ASCII 路径（中文用户名路径下 libass/mpv 可能打不开）。
  Future<File?> _materializeSubtitle(
    GuangyaUserApi api,
    GuangyaFile subtitle,
  ) async {
    try {
      final link = await api.playbackURL(subtitle.id);
      final client = HttpClient();
      final request = await client.getUrl(link.url);
      link.headers.forEach(request.headers.set);
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      client.close();
      final dirPath = Platform.isWindows
          ? r'C:\LemonPlayerSubs'
          : '${Directory.systemTemp.path}/lemon_subs';
      final dir = Directory(dirPath);
      await dir.create(recursive: true);
      final ext = _extension(subtitle.name);
      final file = File('$dirPath/sub_${subtitle.id}.$ext');
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      if (mounted) setState(() => _subtitleStatus = '字幕下载失败');
      return null;
    }
  }

  Future<void> _attachSubtitle(GuangyaFile subtitle) async {
    final api = widget.session.createApi();
    final file = await _materializeSubtitle(api, subtitle);
    if (file == null) return;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(file.uri.toString(), title: subtitle.name),
    );
    if (mounted) {
      setState(() => _subtitleStatus = '字幕：${subtitle.name}');
      _scheduleHide();
    }
  }

  void _togglePlay() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _seekTo(Duration position) async {
    await _player.seek(position);
    if (mounted) setState(() => _position = position);
  }

  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _videos.length || index == _index) return;
    setState(() => _index = index);
    await _openCurrent();
  }

  void _showPanel(String title, List<Widget> children) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xEE1C1C1E),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
    _scheduleHide();
  }

  Widget _sheetTile(String title, {VoidCallback? onTap, IconData? icon}) {
    return ListTile(
      dense: true,
      leading: icon == null ? null : Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.of(context).pop();
        onTap?.call();
      },
    );
  }

  void _openSubtitlePanel() {
    _showPanel('字幕', [
      _sheetTile('关闭字幕', icon: Icons.subtitles_off, onTap: () {
        _player.setSubtitleTrack(SubtitleTrack.no());
        setState(() => _subtitleStatus = '字幕：关闭');
      }),
      ..._subtitleFiles.map((sub) {
        return _sheetTile(sub.name, icon: Icons.subtitles, onTap: () {
          _attachSubtitle(sub);
        });
      }),
      if (_subtitleFiles.isEmpty)
        const ListTile(
          dense: true,
          title: Text(
            '同目录未找到字幕文件',
            style: TextStyle(color: Colors.white54),
          ),
        ),
    ]);
  }

  void _openSpeedPanel() {
    final current = _player.state.rate;
    _showPanel('播放速度', [
      for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
        _sheetTile(
          '${rate}x${(rate - current).abs() < 0.01 ? "  ✓" : ""}',
          icon: Icons.speed,
          onTap: () => _player.setRate(rate),
        ),
    ]);
  }

  void _openAudioPanel() {
    final tracks = _player.state.tracks.audio;
    _showPanel('音轨', [
      for (final track in tracks)
        _sheetTile(track.title ?? track.id, icon: Icons.audiotrack, onTap: () {
          _player.setAudioTrack(track);
        }),
      if (tracks.isEmpty)
        const ListTile(
          dense: true,
          title: Text('无音轨信息', style: TextStyle(color: Colors.white54)),
        ),
    ]);
  }

  void _openEpisodePanel() {
    _showPanel('选集', [
      for (var i = 0; i < _videos.length; i++)
        _sheetTile(
          '${i == _index ? "▶ " : "   "}${_videos[i].name}',
          onTap: () => _switchTo(i),
        ),
    ]);
  }

  static String? _episodeNumber(String name) {
    final patterns = [
      RegExp(r'\[(\d{1,4})(?:v\d)?\]'),
      RegExp(r'第(\d{1,4})[话話集]'),
      RegExp(r'[\s\-_][Ee][Pp]?(\d{1,4})(?:[^\d]|$)'),
      RegExp(r'[\s\-_](\d{1,4})(?:v\d)?(?:[^\d]|$)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).toLowerCase();
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : 'srt';
  }

  static String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _duration.inMilliseconds > 0
        ? _duration
        : Duration.zero;
    final maxMs =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
    final valueMs =
        (_scrubTarget ?? _position.inMilliseconds.toDouble()).clamp(0.0, maxMs).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final width = MediaQuery.sizeOf(context).width;
          final dx = details.localPosition.dx;
          if (dx < width * 0.33) {
            _seekTo(_position - const Duration(seconds: 10));
          } else if (dx > width * 0.66) {
            _seekTo(_position + const Duration(seconds: 10));
          } else {
            _togglePlay();
          }
        },
        onDoubleTap: () {},
        child: Stack(
          children: [
            Positioned.fill(
              child: _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Video(controller: _controller, controls: NoVideoControls),
            ),
            if (_controlsVisible) ...[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _topBar(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _bottomBar(maxMs, valueMs),
              ),
              Center(
                child: IconButton(
                  iconSize: 68,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black38,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
              ),
            ],
            if (_subtitleStatus != null)
              Positioned(
                right: 16,
                top: 64,
                child: Text(
                  _subtitleStatus!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                _current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (_hasQueue)
              IconButton(
                icon: const Icon(Icons.playlist_play, color: Colors.white),
                tooltip: '选集',
                onPressed: _openEpisodePanel,
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(double maxMs, double valueMs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _format(Duration(milliseconds: valueMs.round())),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: Colors.amber,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: valueMs,
                      max: maxMs,
                      onChangeStart: (_) {
                        setState(() {
                          _seeking = true;
                          _hideTimer?.cancel();
                        });
                      },
                      onChanged: (value) {
                        setState(() => _scrubTarget = value);
                      },
                      onChangeEnd: (value) {
                        setState(() {
                          _seeking = false;
                          _scrubTarget = null;
                        });
                        _seekTo(Duration(milliseconds: value.round()));
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
                Text(
                  _format(_duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                  tooltip: '快退 10 秒',
                  onPressed: () =>
                      _seekTo(_position - const Duration(seconds: 10)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  color: Colors.white,
                  iconSize: 32,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
                const SizedBox(width: 8),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                  tooltip: '快进 10 秒',
                  onPressed: () =>
                      _seekTo(_position + const Duration(seconds: 10)),
                ),
                const SizedBox(width: 20),
                TextButton(
                  onPressed: _openSpeedPanel,
                  child: Text(
                    '${_player.state.rate}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.audiotrack),
                  tooltip: '音轨',
                  onPressed: _openAudioPanel,
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.subtitles),
                  tooltip: '字幕',
                  onPressed: _openSubtitlePanel,
                ),
                if (_hasQueue)
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next),
                    tooltip: '下一集',
                    onPressed: () => _switchTo(_index + 1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
