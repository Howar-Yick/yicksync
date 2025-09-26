// yicksync/lib/services/onedrive_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http; 
import 'package:shared_preferences/shared_preferences.dart';


// 定义一个回调函数类型，用于在UI层显示设备码信息
typedef OnCodeCreated = void Function(String userCode, String verificationUrl);

class OneDriveService {
  // ！！！关键：请用您在Azure Portal上注册的 Application (client) ID 替换这里的示例ID
  static const String _clientId = '09dc69e1-9dd1-419e-920e-7ed97fe26980'; // 保持不变

  static const String _tenant = 'consumers';
  static const String _authority = 'https://login.microsoftonline.com/$_tenant';
  static const String _scope = 'offline_access Files.ReadWrite.AppFolder openid profile';
  static const String _graph = 'https://graph.microsoft.com/v1.0';

  // --- 用于本地存储的键 ---
  static const _kAccessToken = 'od_access_token';
  static const _kRefreshToken = 'od_refresh_token';
  static const _kExpiresAt = 'od_expires_at';
  static const _kUsername = 'od_username';

  // --- 状态变量 ---
  bool get isLoggedIn => _isLoggedIn;
  bool _isLoggedIn = false;
  String? get username => _username;
  String? _username;

  // 初始化服务，检查登录状态
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getString(_kAccessToken) != null || prefs.getString(_kRefreshToken) != null;
    _username = prefs.getString(_kUsername);
  }

  // 使用设备码登录，现在通过回调函数与UI解耦
  Future<bool> signInWithDeviceCode({required OnCodeCreated onCodeCreated}) async {
    final codeRes = await http.post(
      Uri.parse('$_authority/oauth2/v2.0/devicecode'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId, 
        'scope': _scope,
        'mkt': 'zh-CN', // <--- 新增此行，建议使用中文市场
      },
    );

    if (codeRes.statusCode != 200) {
      print('获取设备码失败: ${codeRes.body}');
      return false;
    }

    final data = json.decode(codeRes.body) as Map<String, dynamic>;
    final deviceCode = data['device_code'] as String;
    final userCode = data['user_code'] as String; // <--- 我们需要这个
    final verifyUrl = data['verification_uri'] as String;
    int interval = (data['interval'] as num?)?.toInt() ?? 5;

    // 通过回调函数将验证信息传递给UI层
    onCodeCreated(userCode, verifyUrl);
    
    // 轮询以获取token
    while (true) {
      await Future.delayed(Duration(seconds: interval));
      final tokenRes = await http.post(
        Uri.parse('$_authority/oauth2/v2.0/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': _clientId,
          'device_code': deviceCode,
        },
      );

      final body = json.decode(tokenRes.body) as Map<String, dynamic>;
      if (tokenRes.statusCode == 200 && body['access_token'] != null) {
        await _saveTokens(body); // 保存Token
        return true;
      } else {
        final err = (body['error'] ?? '').toString();
        if (err == 'authorization_pending') {
          continue;
        } else if (err == 'slow_down') {
          interval += 2;
        } else {
          print('登录失败: $err');
          return false;
        }
      }
    }
  }

  // 登出
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kUsername);
    _isLoggedIn = false;
    _username = null;
  }

  // 上传文件 (通用)
  Future<bool> uploadFile(Uint8List bytes, String remotePath) async {
    final token = await _getValidAccessToken();
    if (token == null) return false;

    // 路径应该是 /<folder_name>/<file_name.ext>
    final uri = Uri.parse('$_graph/me/drive/special/approot:/$remotePath:/content');
    final res = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream', // 二进制流适用于任何文件
      },
      body: bytes,
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }
  
  // 下载文件 (通用)
  Future<Uint8List?> downloadFile(String remotePath) async {
    final token = await _getValidAccessToken();
    if (token == null) return null;

    final uri = Uri.parse('$_graph/me/drive/special/approot:/$remotePath:/content');
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    
    if (res.statusCode == 200) return res.bodyBytes;
    
    print('下载失败 (${res.statusCode}): ${res.body}');
    return null;
  }

  // 内部方法：保存认证信息
  Future<void> _saveTokens(Map<String, dynamic> body) async {
    final accessToken = body['access_token'] as String;
    final refreshToken = body['refresh_token'] as String?;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;

    // 获取用户名
    String? fetchedUsername;
    try {
      final me = await http.get(
        Uri.parse('$_graph/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (me.statusCode == 200) {
        final meJson = json.decode(me.body) as Map<String, dynamic>;
        fetchedUsername = (meJson['userPrincipalName'] ?? meJson['mail'] ?? meJson['displayName'])?.toString();
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, accessToken);
    if (refreshToken != null) await prefs.setString(_kRefreshToken, refreshToken);
    await prefs.setInt(_kExpiresAt, DateTime.now().add(Duration(seconds: expiresIn - 30)).millisecondsSinceEpoch);
    if (fetchedUsername != null) await prefs.setString(_kUsername, fetchedUsername);

    // 更新内部状态
    _isLoggedIn = true;
    _username = fetchedUsername;
  }
  
  // 内部方法：获取有效的访问令牌（如果过期会自动刷新）
  Future<String?> _getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    var access = prefs.getString(_kAccessToken);
    final expiresAtMs = prefs.getInt(_kExpiresAt) ?? 0;
    
    // 如果令牌未过期，直接返回
    if (access != null && DateTime.now().millisecondsSinceEpoch < expiresAtMs) {
      return access;
    }

    // 否则，尝试用刷新令牌获取新的访问令牌
    final refresh = prefs.getString(_kRefreshToken);
    if (refresh == null) return null; // 没有刷新令牌，无法继续

    final res = await http.post(
      Uri.parse('$_authority/oauth2/v2.0/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refresh,
        'scope': _scope,
      },
    );

    if (res.statusCode != 200) {
      print('刷新Token失败: ${res.body}');
      return null;
    }

    final body = json.decode(res.body) as Map<String, dynamic>;
    await _saveTokens(body); // 保存新的Tokens

    return prefs.getString(_kAccessToken);
  }
}