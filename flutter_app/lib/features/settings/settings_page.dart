import 'package:flutter/material.dart';

import '../../app/session_store.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});

  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('光鸭云盘'),
            subtitle: Text(
              session.isLoggedIn
                  ? '已登录（token ${session.accessToken?.length ?? 0} 字符）'
                  : '未登录',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('设备 ID'),
            subtitle: Text(
              session.identity.deviceId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Flutter 版'),
            subtitle: const Text('Phase 3 · media_kit + 光鸭用户 API'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await session.logout();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已退出登录')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
