import 'package:flutter/material.dart';

import 'app.dart';
import 'audio/media_bridge.dart';
import 'state/app_theme.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = AppServices();
  AppServices.instance = services;

  // 系统媒体控制桥接（通知栏 / 锁屏 / 蓝牙耳机 / 系统媒体中心）。
  // 底层由 flutter_media_session（androidx.media3 MediaSessionService）提供。
  final bridge = PinkMediaBridge();

  try {
    await services.init();
    debugPrint('AppServices.init OK');
  } catch (e) {
    debugPrint('AppServices.init error: $e');
    services.initError = '$e';
  }

  // 媒体控制注册不依赖 services.init 成败：_sync 内部有 instanceReady 守卫，
  // 即使初始化任一步失败也保持注册（激活会话时插件自动请求通知权限）。
  bridge.attach();

  runApp(const PinkMusicApp());
}

class PinkMusicApp extends StatelessWidget {
  const PinkMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    return ListenableBuilder(
      listenable: svc.theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'Pink Music',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(svc.theme),
          home: const HomeShell(),
        );
      },
    );
  }
}