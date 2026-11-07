import 'package:flutter/material.dart';
import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/session_store.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.session, required this.file});

  final SessionStore session;
  final GuangyaFile file;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(libass: true),
  );
  late final VideoController _controller = VideoController(_player);
  bool _loading = true;
  String? _error;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final api = widget.session.createApi();
      final link = await api.playbackURL(widget.file.id);
      await _player.open(
        Media(link.url.toString(), httpHeaders: link.headers),
        play: true,
      );
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      });
      if (mounted) setState(() => _loading = false);
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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
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
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (!_loading)
              Center(
                child: IconButton(
                  iconSize: 64,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (_playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
