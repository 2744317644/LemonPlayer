import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lemon_guangya/lemon_guangya.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登录态（Phase 1：SharedPreferences；移动端后续换 secure storage）。
class SessionStore extends ChangeNotifier {
  static const _kAccess = 'lemon.access_token';
  static const _kRefresh = 'lemon.refresh_token';
  static const _kExpires = 'lemon.expires_at_ms';
  static const _kIdentity = 'lemon.device_identity';

  String? accessToken;
  String? refreshToken;
  int? expiresAtMs;
  DeviceIdentity identity = DeviceIdentity.random();

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_kAccess);
    refreshToken = prefs.getString(_kRefresh);
    expiresAtMs = prefs.getInt(_kExpires);
    final rawIdentity = prefs.getString(_kIdentity);
    if (rawIdentity != null) {
      try {
        identity = DeviceIdentity.fromJson(
          jsonDecode(rawIdentity) as Map<String, dynamic>,
        );
      } catch (_) {
        identity = DeviceIdentity.random();
      }
    }
    await _persistIdentity();
  }

  Future<void> saveTokens(TokenBundle bundle) async {
    accessToken = bundle.accessToken;
    refreshToken = bundle.refreshToken;
    expiresAtMs =
        DateTime.now().millisecondsSinceEpoch + bundle.expiresIn * 1000;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, accessToken!);
    await prefs.setString(_kRefresh, refreshToken ?? '');
    await prefs.setInt(_kExpires, expiresAtMs!);
    await _persistIdentity();
    notifyListeners();
  }

  Future<void> savePastedToken(String token) async {
    accessToken = token.trim();
    refreshToken = '';
    expiresAtMs = DateTime.now().millisecondsSinceEpoch + 3600 * 1000;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, accessToken!);
    await prefs.setString(_kRefresh, '');
    await prefs.setInt(_kExpires, expiresAtMs!);
    await _persistIdentity();
    notifyListeners();
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    expiresAtMs = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kExpires);
    notifyListeners();
  }

  GuangyaUserApi createApi() {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('未登录');
    }
    return GuangyaUserApi(accessToken: token, identity: identity);
  }

  Future<void> _persistIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIdentity, jsonEncode(identity.toJson()));
  }
}
