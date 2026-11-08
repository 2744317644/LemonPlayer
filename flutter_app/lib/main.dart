import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app/session_store.dart';
import 'features/login/login_page.dart';
import 'home_shell.dart';

/// Phase 0：验证 Flutter + media_kit（libmpv）在 Windows 上的播放与 ASS 字幕。
/// - 默认播放 HLS 示例并挂载 assets/demo.ass
/// - 可切换播放 MKV 示例
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  final session = SessionStore();
  await session.load();
  runApp(LemonApp(session: session));
}

/// Phase 1 应用壳：未登录→登录页；已登录→网盘浏览。
class LemonApp extends StatelessWidget {
  const LemonApp({super.key, required this.session});

  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return MaterialApp(
          title: 'LemonPlayer',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFB7299),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: session.isLoggedIn
              ? HomeShell(session: session)
              : LoginPage(session: session),
        );
      },
    );
  }
}

const hlsUrl =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8';
const mkvUrl =
    'https://test-videos.co.uk/vids/bigbuckbunny/mkv/720/Big_Buck_Bunny_720_10s_1MB.mkv';

class Phase0App extends StatefulWidget {
  const Phase0App({super.key});

  @override
  State<Phase0App> createState() => _Phase0AppState();
}

class _Phase0AppState extends State<Phase0App> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(libass: true),
  );
  late final VideoController _controller = VideoController(_player);
  String _status = '初始化中…';
  String _current = 'HLS';
  bool _assAttached = false;
  String _subtitleState = '-';
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _play(mkvUrl, 'MKV');
    _player.stream.error.listen((error) {
      if (mounted) setState(() => _status = '播放错误：$error');
    });
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.stream.subtitle.listen((tracks) {
      if (mounted) {
        setState(() => _subtitleState = tracks.isEmpty ? '无' : tracks.join(', '));
      }
    });
  }

  Future<File> _writeDemoAss() async {
    final text = await rootBundle.loadString('assets/demo.ass');
    final dir = Directory(r'C:\LemonPhase0');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}demo.ass');
    await file.writeAsString(text);
    return file;
  }

  Future<void> _play(String url, String label) async {
    setState(() {
      _status = '加载 $label…';
      _current = label;
      _assAttached = false;
      _subtitleState = '-';
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    final ass = await _writeDemoAss();
    await _player.open(Media(url), play: true);
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(ass.uri.toString(), title: 'Demo ASS'),
    );
    final sub = _player.state.track.subtitle;
    if (mounted) {
      setState(() {
        _status = '$label 播放中（ASS 已挂载）';
        _assAttached = true;
        _subtitleState = sub.uri
            ? 'uri:${sub.title ?? sub.id}'
            : (sub.id == 'no' ? '关闭' : 'id:${sub.id}');
      });
    }
    _captureAfterDelay();
  }

  Future<void> _captureAfterDelay() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    try {
      final bytes = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true,
      );
      if (bytes == null) {
        if (mounted) setState(() => _status = '截图失败：bytes=null');
        return;
      }
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lemon_phase0_shot.png',
      );
      await file.writeAsBytes(bytes);
      if (mounted) setState(() => _status = '截图已保存：${file.path}');
    } catch (error) {
      if (mounted) setState(() => _status = '截图异常：$error');
    }
  }

  Future<void> _playMkv() => _play(mkvUrl, 'MKV');

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: Video(controller: _controller, controls: NoVideoControls),
            ),
            Positioned(
              left: 24,
              top: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PHASE0 media_kit',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ASS-CHECK 你好世界（应为画面字幕）',
                    style: TextStyle(color: Colors.yellow.shade300, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前：$_current',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '状态：$_status',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    'ASS已挂载：$_assAttached  字幕轨：$_subtitleState',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '播放：$_playing  位置：${_position.inSeconds}s / ${_duration.inSeconds}s',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              bottom: 24,
              child: Row(
                children: [
                  FilledButton(
                    onPressed: () => _play(hlsUrl, 'HLS'),
                    child: const Text('播放 HLS + ASS'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _playMkv,
                    child: const Text('播放 MKV + ASS'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
