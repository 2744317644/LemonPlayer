import 'package:flutter/material.dart';
import 'package:lemon_core/lemon_core.dart';
import 'package:lemon_guangya/lemon_guangya.dart';

import '../../app/session_store.dart';
import '../player/player_page.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.session});

  final SessionStore session;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late final GuangyaUserApi _api = widget.session.createApi();
  final List<({String id, String name})> _crumbs = [(id: '', name: '网盘')];
  List<GuangyaFile> _items = [];
  bool _loading = true;
  String? _error;

  String get _currentId => _crumbs.last.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listFiles(parentId: _currentId, pageSize: 200);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on LemonError catch (error) {
      if (!mounted) return;
      if (error.kind == LemonErrorKind.unauthorized) {
        await widget.session.logout();
        return;
      }
      setState(() {
        _loading = false;
        _error = error.userMessage;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _enter(GuangyaFile folder) async {
    _crumbs.add((id: folder.id, name: folder.name));
    _items = [];
    await _load();
  }

  Future<void> _goUp() async {
    if (_crumbs.length <= 1) return;
    _crumbs.removeLast();
    _items = [];
    await _load();
  }

  void _open(GuangyaFile file) {
    if (file.isFolder) {
      _enter(file);
      return;
    }
    if (!file.isPlayable) return;
    final queue = _items.where((item) => item.isPlayable).toList();
    final startIndex = queue.indexWhere((item) => item.id == file.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          session: widget.session,
          file: file,
          videos: queue,
          startIndex: startIndex < 0 ? 0 : startIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _crumbs.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: '上一级',
                onPressed: _goUp,
              )
            : null,
        title: Text(_crumbs.last.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') widget.session.logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        itemCount: 8,
        itemBuilder: (_, __) => const ListTile(
          leading: CircleAvatar(child: SizedBox(width: 18, height: 18)),
          title: SizedBox(
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFEEEEEE)),
            ),
          ),
          subtitle: SizedBox(
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFF5F5F5)),
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('空目录'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = _items[index];
          return ListTile(
            leading: Icon(
              file.isFolder
                  ? Icons.folder
                  : file.isPlayable
                      ? Icons.movie
                      : Icons.insert_drive_file,
              color: file.isFolder ? Colors.amber : null,
            ),
            title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              file.isFolder ? '文件夹' : _sizeText(file.size),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: file.isFolder
                ? const Icon(Icons.chevron_right)
                : (file.isPlayable ? const Icon(Icons.play_circle_outline) : null),
            onTap: () => _open(file),
          );
        },
      ),
    );
  }

  static String _sizeText(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
