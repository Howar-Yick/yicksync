// yicksync/lib/services/background_service.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:yicksync/services/file_sync_service.dart';
import 'package:yicksync/services/onedrive_service.dart';

// 1. 后台服务通信的入口点 (必须是顶级函数)
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // DartVM 在后台服务中的入口
  DartPluginRegistrant.ensureInitialized();
  
  // 如果是 Android 服务，需要显式设为前台服务
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // --- 核心同步逻辑 ---
  // 注意：后台任务中的 print 不会显示在 debug console，而是系统日志中
  // 为了方便调试，我们可以在同步前后显示通知
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      // 检查服务是否在前台运行
      if (await service.isForegroundService()) {
        
        // 执行同步任务前，需要重新实例化我们的服务
        // 因为后台 isolate 和 UI isolate 是隔离的
        final oneDriveService = OneDriveService();
        await oneDriveService.init(); // 初始化以加载 token

        // 只有登录后才执行同步
        if(oneDriveService.isLoggedIn) {
          final fileSyncService = FileSyncService(oneDriveService);
          
          flutterLocalNotificationsPlugin.show(
              888,
              'YICKsync 正在同步',
              '开始于 ${DateTime.now().hour}:${DateTime.now().minute}',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'yicksync_channel',
                  'YICKsync Service',
                  icon: 'ic_bg_service_small',
                  ongoing: true,
                ),
              ),
            );

          try {
            await fileSyncService.sync();
            print("后台服务：同步任务成功。");
          } catch (e) {
            print("后台服务：同步任务失败: $e");
          } finally {
             // 结束后可以更新通知或移除
            flutterLocalNotificationsPlugin.show(
              888,
              'YICKsync 服务正在运行',
              '上次同步于 ${DateTime.now().hour}:${DateTime.now().minute}',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'yicksync_channel',
                  'YICKsync Service',
                  icon: 'ic_bg_service_small',
                  ongoing: true,
                ),
              ),
            );
          }
        } else {
          print("后台服务：用户未登录，跳过同步。");
        }
      }
    }
  });
}

/// 初始化后台服务
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // 配置安卓服务的通知栏
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'yicksync_channel', // id
    'YICKsync Service', // title
    description: '此通道用于显示 YICKsync 的前台服务通知', // description
    importance: Importance.low, // 设置为 low，用户就不会感觉太打扰
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'yicksync_channel',
      initialNotificationTitle: 'YICKsync 服务已启动',
      initialNotificationContent: '正在等待定时同步任务...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // iOS 配置相对简单
      autoStart: true,
      onForeground: onStart,
    ),
  );
}