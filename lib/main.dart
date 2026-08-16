import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'state/app_theme.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    const channel = MethodChannel('com.pinkmusic.app/permissions');
    await channel.invokeMethod('requestNotificationPermission');
  } catch (e) {
    debugPrint('Permission error: $e');
  }

  final services = AppServices();
  AppServices.instance = services;

  late PinkAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init(
      builder: () => PinkAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.pinkmusic.app.channel.audio',
        androidNotificationChannelName: 'Pink Music 播放控制',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // 状态栏/超级岛小图标（通知 compact view 与灵动岛均需要）
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    ) ;
    debugPrint('AudioService.init OK');
  } catch (e) {
    debugPrint('AudioService.init error: $e');
    audioHandler = PinkAudioHandler();
  }

  bool initOk = false;
  try {
    await services.init();
    initOk = true;
    debugPrint('AppServices.init OK');
  } catch (e) {
    debugPrint('AppServices.init error: $e');
    services.initError = '$e';
  }

  if (initOk) {
    audioHandler.attach();
  }

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
