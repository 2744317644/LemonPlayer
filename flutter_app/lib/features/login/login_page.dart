import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/session_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final SessionStore session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final GuangyaAuthClient _auth = GuangyaAuthClient(
    identity: widget.session.identity,
  );
  final _tokenController = TextEditingController();

  DeviceCode? _deviceCode;
  String _status = '正在获取登录二维码…';
  bool _busy = false;
  Timer? _pollTimer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    _requestCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _status = '正在获取登录二维码…';
      _deviceCode = null;
      _pollCount = 0;
    });
    try {
      final code = await _auth.requestDeviceCode();
      if (!mounted) return;
      setState(() {
        _deviceCode = code;
        _status = '请用光鸭云盘 App 扫码（或打开授权页输入代码）';
        _busy = false;
      });
      final interval = Duration(seconds: code.interval.clamp(2, 10));
      _pollTimer = Timer.periodic(interval, (_) => _poll(code));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '获取二维码失败：$error';
      });
    }
  }

  Future<void> _poll(DeviceCode code) async {
    if (!mounted) return;
    _pollCount++;
    final deadline = code.expiresIn;
    if (_pollCount * code.interval > deadline) {
      _pollTimer?.cancel();
      if (mounted) setState(() => _status = '二维码已过期，正在刷新…');
      await _requestCode();
      return;
    }
    try {
      final result = await _auth.poll(code.deviceCode);
      if (!mounted) return;
      switch (result.status) {
        case DevicePollStatus.pending:
          setState(() => _status = '等待扫码确认…');
        case DevicePollStatus.authorized:
          _pollTimer?.cancel();
          final token = result.token;
          if (token != null) {
            await widget.session.saveTokens(token);
            if (mounted) setState(() => _status = '登录成功');
          }
        case DevicePollStatus.expired:
          _pollTimer?.cancel();
          setState(() => _status = '二维码已过期，正在刷新…');
          await _requestCode();
        case DevicePollStatus.failed:
          _pollTimer?.cancel();
          setState(() => _status = '登录失败：${result.message ?? '未知错误'}');
      }
    } catch (error) {
      // 网络抖动：保持轮询，不直接退出
      if (mounted) setState(() => _status = '网络波动，继续等待…（$error）');
    }
  }

  Future<void> _loginWithPastedToken() async {
    final raw = _tokenController.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      // 校验格式：JWT 三段
      if (raw.split('.').length != 3) {
        setState(() {
          _busy = false;
          _status = 'Token 格式不对（应为 JWT 三段）';
        });
        return;
      }
      await widget.session.savePastedToken(raw);
      if (mounted) setState(() => _status = '已用 Token 登录');
    } catch (error) {
      if (mounted) setState(() => _status = 'Token 登录失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _deviceCode;
    return Scaffold(
      appBar: AppBar(title: const Text('登录光鸭云盘')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '扫码登录',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (code != null && code.qrContent.isNotEmpty)
                    QrImageView(
                      data: code.qrContent,
                      size: 220,
                      backgroundColor: Colors.white,
                    )
                  else if (_busy)
                    const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (code != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      '授权码：${code.userCode}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      code.verificationUrl ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _requestCode,
                    child: const Text('刷新二维码'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '临时接入（Windows 验证用）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '粘贴 access_token（JWT）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _loginWithPastedToken,
            child: const Text('使用 Token 登录'),
          ),
        ],
      ),
    );
  }
}
