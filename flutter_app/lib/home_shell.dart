import 'package:flutter/material.dart';

import '../app/session_store.dart';
import 'features/browse/browse_page.dart';
import 'features/media/media_library_page.dart';
import 'features/settings/settings_page.dart';

/// Phase 1-3 应用壳：网盘 / 媒体库 / 设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});

  final SessionStore session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          BrowsePage(session: widget.session),
          MediaLibraryPage(session: widget.session),
          SettingsPage(session: widget.session),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '网盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
