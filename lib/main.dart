// yicksync/lib/main.dart (最终修正版)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yicksync/services/background_service.dart';
import 'package:yicksync/services/file_sync_service.dart';
import 'package:yicksync/services/onedrive_service.dart';

Future<void> main() async {
  // 确保 Flutter 小部件绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // --- 平台判断 ---
  // 只有在安卓平台，我们才初始化后台服务和请求权限
  if (!kIsWeb && Platform.isAndroid) {
    // 请求通知权限 (Android 13+ 需要)
    await Permission.notification.request();

    // 初始化后台服务
    await initializeBackgroundService();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YICKsync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final OneDriveService _oneDriveService = OneDriveService();
  late final FileSyncService _fileSyncService;
  bool _isLoggedIn = false;
  String _status = '正在初始化...';
  bool _isSyncing = false;
  bool _isMobile = false; // 用于判断是否在移动端

  @override
  void initState() {
    super.initState();
    _fileSyncService = FileSyncService(_oneDriveService);
    // 判断平台，以便在UI上给出提示
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _isMobile = true;
    }
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    await _oneDriveService.init();
    setState(() {
      _isLoggedIn = _oneDriveService.isLoggedIn;
      if (!_isMobile) {
        _status = '后台服务仅支持安卓/iOS平台';
      } else {
        _status =
            _isLoggedIn ? '已登录: ${_oneDriveService.username ?? ''}' : '未登录';
      }
    });
  }

  void _login() async {
    if (!_isMobile) return;

    setState(() {
      _status = '正在获取登录码...';
    });

    void showLoginDialog(String userCode, String verificationUrl) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('登录 OneDrive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在浏览器中打开以下链接:'),
              const SizedBox(height: 8),
              SelectableText(
                verificationUrl,
                style: const TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
              ),
              const SizedBox(height: 16),
              const Text('并输入以下代码完成授权:'),
              const SizedBox(height: 8),
              Center(
                child: SelectableText(
                  userCode,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => launchUrl(Uri.parse(verificationUrl),
                  mode: LaunchMode.externalApplication),
              child: const Text('打开链接'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我已授权'),
            ),
          ],
        ),
      );
    }

    final success = await _oneDriveService.signInWithDeviceCode(
      onCodeCreated: showLoginDialog,
    );

    setState(() {
      _isLoggedIn = success;
      if (success) {
        _status = '登录成功！用户: ${_oneDriveService.username ?? ''}';
      } else {
        _status = '登录失败或已取消';
      }
    });
  }

  void _logout() async {
    if (!_isMobile) return;
    await _oneDriveService.signOut();
    setState(() {
      _isLoggedIn = false;
      _status = '已退出登录';
    });
  }

  void _sync() async {
    if (!_isMobile) return;
    if (!_isLoggedIn) {
      setState(() {
        _status = '请先登录！';
      });
      return;
    }
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _status = '同步开始，请稍候...';
    });

    try {
      await _fileSyncService.sync();
      setState(() {
        _status = '同步成功！';
      });
    } catch (e) {
      setState(() {
        _status = '同步失败: $e';
      });
      print('同步错误详情: $e');
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YICKsync for Obsidian'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '当前状态:',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (!_isMobile || !_isLoggedIn)
                ElevatedButton(
                  onPressed: _isMobile ? _login : null,
                  child: const Text('登录 OneDrive'),
                ),
              if (_isMobile && _isLoggedIn)
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _isSyncing ? null : _sync,
                      child: _isSyncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('立即同步'),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _logout,
                      child: const Text('退出登录'),
                    ),
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }
}