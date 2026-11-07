import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Phase 0：验证 Flutter + media_kit（libmpv）在 Windows 上的播放与 ASS 字幕。
/// - 默认播放 HLS 示例并挂载 assets/demo.ass
/// - 可切换播放 MKV 示例
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  runApp(const Phase0App());
}

const hlsUrl =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8';
const mkvUrl =
    'https://test-videos.co.uk/vids/bigbuckbunny/mkv/720/Big_Buck_Bunny_720_10s_1MB.mkv';

class Phase0App extends StatefulWidget {
  const Phase0App({super.key});

  @override
  State<Phase0App> createState() => _Phase0AppState();
}

class _Phase0AppState extends State<Phase0App> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String _status = '初始化中…';
  String _current = 'HLS';
  bool _assAttached = false;

  @override
  void initState() {
    super.initState();
    _prepareSubtitleAndPlayHls();
    _player.stream.error.listen((error) {
      if (mounted) setState(() => _status = '播放错误：$error');
    });
  }

  Future<File> _writeDemoAss() async {
    final text = await rootBundle.loadString('assets/demo.ass');
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lemon_demo.ass',
    );
    await file.writeAsString(text);
    return file;
  }

  Future<void> _prepareSubtitleAndPlayHls() async {
    setState(() {
      _status = '加载 HLS…';
      _current = 'HLS';
    });
    final ass = await _writeDemoAss();
    await _player.open(Media(hlsUrl), play: true);
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(ass.uri.toString(), title: 'Demo ASS'),
    );
    if (mounted) {
      setState(() {
        _status = 'HLS 播放中（ASS 已挂载）';
        _assAttached = true;
      });
    }
  }

  Future<void> _playMkv() async {
    setState(() {
      _status = '加载 MKV…';
      _current = 'MKV';
    });
    await _player.open(Media(mkvUrl), play: true);
    final ass = await _writeDemoAss();
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(ass.uri.toString(), title: 'Demo ASS'),
    );
    if (mounted) {
      setState(() => _status = 'MKV 播放中（ASS 已挂载）');
    }
  }

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
                    'ASS已挂载：$_assAttached',
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
                    onPressed: _prepareSubtitleAndPlayHls,
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
