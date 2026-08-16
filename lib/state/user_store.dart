import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/bilibili_api.dart';
import '../services/cookie_store.dart';
import '../services/http_client.dart';

/// 用户状态：二维码登录 + 收藏夹同步（对应原项目 src/stores/user.js）
class UserStore extends ChangeNotifier {
  final BilibiliApi api;
  final CookieStore cookies;

  UserStore(this.api, this.cookies);

  Map<String, dynamic>? userInfo;
  bool isLoggedIn = false;

  // 二维码状态
  String qrcodeUrl = '';
  String qrcodeKey = '';
  String qrcodeStatus = 'idle'; // idle | loading | waiting | scanned | success | expired | error
  String qrcodeMessage = '';
  bool isPolling = false;
  bool isSyncingFavorites = false;

  Timer? _pollTimer;
  int _pollCount = 0;

  String? get mid => userInfo?['mid']?.toString();
  String? get uname => userInfo?['uname'];
  String? get face => userInfo?['face'];

  // ---------- 登录 ----------

  Future<void> restoreFromCookies() async {
    await cookies.load();
    if (!cookies.hasSessdata) {
      isLoggedIn = false;
      notifyListeners();
      return;
    }
    await fetchUserInfo();
  }

  Future<bool> fetchUserInfo() async {
    try {
      final info = await api.getUserInfo();
      if (info['mid'] != null && info['mid'] != 0) {
        userInfo = info;
        isLoggedIn = true;
        await cookies.save();
        notifyListeners();
        return true;
      } else {
        // 登录失效
        await logout(clearCookies: true);
        return false;
      }
    } catch (e) {
      if (!isLoggedIn) {
        // 网络失败但本地有 cookie：保留状态
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> generateQrcode() async {
    if (isLoggedIn) return;
    qrcodeStatus = 'loading';
    qrcodeMessage = '正在获取二维码…';
    notifyListeners();
    try {
      final data = await api.generateQrcode();
      qrcodeUrl = data['url'] ?? '';
      qrcodeKey = data['qrcode_key'] ?? '';
      if (qrcodeUrl.isEmpty) {
        throw Exception('二维码获取失败');
      }
      qrcodeStatus = 'waiting';
      qrcodeMessage = '请使用哔哩哔哩 App 扫码登录';
      _pollCount = 0;
      _startPolling();
    } catch (e) {
      qrcodeStatus = 'error';
      qrcodeMessage = '二维码获取失败，请检查网络';
    }
    notifyListeners();
  }

  void _startPolling() {
    stopPolling();
    isPolling = true;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) async {
      if (qrcodeKey.isEmpty) return;
      _pollCount++;
      try {
        final data = await api.pollQrcode(qrcodeKey);
        final code = data['code'] ?? 86101;
        switch (code) {
          case 0:
            await _onLoginSuccess();
          case 86090:
            qrcodeStatus = 'scanned';
            qrcodeMessage = '已扫描，请在手机上确认';
            notifyListeners();
          case 86038:
            qrcodeStatus = 'expired';
            qrcodeMessage = '二维码已过期，点击刷新';
            stopPolling();
            notifyListeners();
          default:
            qrcodeStatus = 'waiting';
            qrcodeMessage = '请使用哔哩哔哩 App 扫码登录';
            notifyListeners();
        }
      } catch (e) {
        if (_pollCount > 15) {
          qrcodeStatus = 'error';
          qrcodeMessage = '轮询失败，请重试';
          stopPolling();
          notifyListeners();
        }
      }
    });
  }

  Future<void> _onLoginSuccess() async {
    stopPolling();
    qrcodeStatus = 'success';
    qrcodeMessage = '登录成功';
    notifyListeners();
    await fetchUserInfo();
    await syncFavorites();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    isPolling = false;
  }

  Future<void> logout({bool clearCookies = true}) async {
    stopPolling();
    userInfo = null;
    isLoggedIn = false;
    qrcodeUrl = '';
    qrcodeKey = '';
    qrcodeStatus = 'idle';
    qrcodeMessage = '';
    resetSmsLogin();
    if (clearCookies) {
      cookies.clear();
      await cookies.save();
    }
    notifyListeners();
  }

  // ---------- 短信验证码登录 ----------

  String smsPhone = '';
  String smsCaptchaKey = '';
  bool smsSent = false;
  String smsStatus = 'idle'; // idle | sending | sent | logging | success | error
  String smsMessage = '';

  /// 获取极验验证码参数（gt/challenge/token）
  Future<Map<String, dynamic>?> fetchSmsCaptcha() async {
    try {
      return await api.getSmsCaptcha();
    } catch (e) {
      debugPrint('获取验证码参数失败: $e');
      smsStatus = 'error';
      smsMessage = '获取人机验证失败，请重试';
      notifyListeners();
      return null;
    }
  }

  /// 发送短信验证码（内部会先经过极验人机验证）
  Future<bool> sendSmsCode(String phone, Map<String, dynamic> captcha,
      String validate, String seccode) async {
    smsPhone = phone;
    smsStatus = 'sending';
    smsMessage = '正在发送验证码…';
    notifyListeners();
    try {
      final data = await api.sendSmsCode(
        cid: 86,
        tel: phone,
        token: captcha['token']?.toString() ?? '',
        challenge: captcha['challenge']?.toString() ?? '',
        validate: validate,
        seccode: seccode,
      );
      smsCaptchaKey = data['captcha_key']?.toString() ?? '';
      smsSent = smsCaptchaKey.isNotEmpty;
      if (smsSent) {
        smsStatus = 'sent';
        smsMessage = '验证码已发送';
      } else {
        smsStatus = 'error';
        smsMessage = '发送验证码失败';
      }
    } catch (e) {
      debugPrint('发送短信失败: $e');
      smsStatus = 'error';
      smsMessage = _smsErrorMessage(e);
      smsSent = false;
    }
    notifyListeners();
    return smsSent;
  }

  /// 验证码登录
  Future<bool> loginWithSms(String phone, String code) async {
    if (smsCaptchaKey.isEmpty) return false;
    smsStatus = 'logging';
    smsMessage = '正在登录…';
    notifyListeners();
    try {
      await api.loginSms(
          cid: 86, tel: phone, code: code, captchaKey: smsCaptchaKey);
      await cookies.save(); // 持久化登录 Cookie
      smsStatus = 'success';
      smsMessage = '登录成功';
      notifyListeners();
      await fetchUserInfo();
      await syncFavorites();
      return true;
    } catch (e) {
      debugPrint('短信登录失败: $e');
      smsStatus = 'error';
      smsMessage = _smsErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  void resetSmsLogin() {
    smsPhone = '';
    smsCaptchaKey = '';
    smsSent = false;
    smsStatus = 'idle';
    smsMessage = '';
  }

  String _smsErrorMessage(Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 1002:
          return '手机号格式错误';
        case 1006:
          return '验证码错误';
        case 1007:
          return '验证码已过期';
        case 86203:
          return '发送次数已达上限，请稍后再试';
        case 2400:
          return '登录密钥错误，请重新获取验证码';
        case 2406:
          return '人机验证失败，请重试';
        default:
          return e.message;
      }
    }
    return '网络异常，请重试';
  }

  // ---------- 收藏夹 ----------

  /// 同步收藏夹列表到本地歌单
  Future<void> syncFavorites() async {
    final m = mid;
    if (!isLoggedIn || m == null) return;
    isSyncingFavorites = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.getFavFolderCreatedList(num.parse(m), 1, 50),
        api.getFavFolderCollectedList(num.parse(m), 1, 50),
      ]);
      final folders = <Map<String, dynamic>>[];
      const sources = ['created', 'collected'];
      for (var li = 0; li < results.length; li++) {
        for (final item in results[li]) {
          if (item['state'] != 0) continue;
          folders.add({
            'id': item['id'],
            'title': item['title'],
            'cover': item['cover'],
            'media_count': item['media_count'],
            'source': sources[li],
          });
        }
      }
      _mergeWithPlaylists(folders);
    } catch (e) {
      debugPrint('同步收藏夹失败: $e');
    }
    isSyncingFavorites = false;
    notifyListeners();
  }

  void _mergeWithPlaylists(List<Map<String, dynamic>> folders) {
    // 需要访问 PlaylistStore，通过回调注入
    onMergeFavorites?.call(folders);
  }

  void Function(List<Map<String, dynamic>> folders)? onMergeFavorites;

  /// 加载收藏夹全部资源（ids + infos 分块 50，防 -412）
  Future<List<Track>> loadAllFavoriteResources(Playlist playlist,
      {void Function(int current, int total, int loaded)? onProgress}) async {
    final mediaId = playlist.biliMediaId;
    if (mediaId == null) return [];
    final ids = await api.getFavResourceIds(num.parse(mediaId));
    final valid = ids
        .where((i) => (i['type'] ?? 0) == 2 || (i['type'] ?? 0) == 12)
        .toList();

    final tracks = <Track>[];
    var loaded = 0;
    for (var i = 0; i < valid.length; i += 50) {
      final chunk = valid.sublist(
          i, i + 50 > valid.length ? valid.length : i + 50);
      final resources = chunk.map((c) => '${c['id']}:${c['type']}').join(',');
      final infos = await api.getFavResourceInfos(resources);
      for (final info in infos) {
        final attr = info['attr'];
        final type = info['type'] ?? 0;
        if (attr != null && attr != 0) continue;
        if (type == 21 || type == 24) continue;
        final track = Track.fromFavResource(info);
        final dup = tracks.any((t) =>
            (track.bvid.isNotEmpty && t.bvid == track.bvid) ||
            (t.favId == track.favId && t.favType == track.favType));
        if (dup) continue;
        tracks.add(track);
      }
      loaded += chunk.length;
      onProgress?.call(loaded, valid.length, tracks.length);
    }
    return tracks;
  }
}
