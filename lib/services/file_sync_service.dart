// yicksync/lib/services/file_sync_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yicksync/services/onedrive_service.dart';

/// 文件清单的数据模型
/// 用于记录一个文件夹内所有文件的状态
class FileManifest {
  /// 存储文件信息的 Map
  /// Key: 文件的相对路径, e.g., "My Notes/meeting.md"
  /// Value: 文件的元数据 (哈希值_最后修改时间戳)
  final Map<String, String> files;

  FileManifest({required this.files});

  /// 从 JSON 对象创建 FileManifest 实例
  factory FileManifest.fromJson(Map<String, dynamic> json) {
    return FileManifest(files: Map<String, String>.from(json['files'] ?? {}));
  }

  /// 将 FileManifest 实例转换为 JSON 对象
  Map<String, dynamic> toJson() => {'files': files};
}


/// 核心同步服务类
class FileSyncService {
  final OneDriveService _oneDriveService;
  
  FileSyncService(this._oneDriveService);

  // --- 配置项 ---
  final String _remoteBaseFolder = "YICKsync_Obsidian";
  final String _manifestFileName = ".manifest.json"; // 使用.开头，使其成为隐藏文件
  late final String _localBasePath;

  /// 初始化服务，设置本地文件夹路径
  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _localBasePath = '${directory.path}/ObsidianVault';
    await Directory(_localBasePath).create(recursive: true);
    print('本地同步目录: $_localBasePath');
  }

  /// 核心同步方法
  Future<void> sync() async {
    await init();

    print('1. 正在生成本地文件清单...');
    final localManifest = await _generateLocalManifest();

    print('2. 正在下载远程文件清单...');
    final remoteManifest = await _getRemoteManifest() ?? FileManifest(files: {});

    print('3. 正在对比本地与远程文件...');
    final Set<String> processedFiles = {};

    // --- 上传和冲突检测 ---
    for (var localEntry in localManifest.files.entries) {
      final localPath = localEntry.key;
      final localMeta = localEntry.value;
      final remoteMeta = remoteManifest.files[localPath];
      
      processedFiles.add(localPath);

      if (remoteMeta == null) {
        print('   [上传] 新文件: $localPath');
        await _uploadFile(localPath);
      } else {
        if (localMeta != remoteMeta) {
            print('   [上传] 更新文件: $localPath');
            await _uploadFile(localPath);
        }
      }
    }

    // --- 下载检测 ---
    for (var remoteEntry in remoteManifest.files.entries) {
      final remotePath = remoteEntry.key;
      if (!processedFiles.contains(remotePath)) {
        print('   [下载] 新文件: $remotePath');
        await _downloadFile(remotePath);
      }
    }
    
    print('4. 正在上传最新的文件清单...');
    final finalManifest = await _generateLocalManifest();
    await _uploadRemoteManifest(finalManifest);

    print('同步完成!');
  }

  // --- 内部辅助方法 ---

  Future<FileManifest> _generateLocalManifest() async {
    final filesMap = <String, String>{};
    final directory = Directory(_localBasePath);
    if (!await directory.exists()) {
      return FileManifest(files: {});
    }
    final allFiles = directory.listSync(recursive: true);

    for (var entity in allFiles) {
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        final hash = sha1.convert(bytes).toString();
        final lastModified = await entity.lastModified();
        final relativePath = entity.path.substring(_localBasePath.length + 1).replaceAll('\\', '/');
        
        // 忽略我们自己的清单文件
        if (relativePath == _manifestFileName) continue;

        filesMap[relativePath] = '${hash}_${lastModified.millisecondsSinceEpoch}';
      }
    }
    return FileManifest(files: filesMap);
  }

  Future<FileManifest?> _getRemoteManifest() async {
    final remotePath = '$_remoteBaseFolder/$_manifestFileName';
    final bytes = await _oneDriveService.downloadFile(remotePath);
    if (bytes != null) {
      try {
        return FileManifest.fromJson(json.decode(utf8.decode(bytes)));
      } catch (e) {
        print('解析远程 manifest.json 失败: $e');
        return null;
      }
    }
    return null;
  }

  Future<void> _uploadRemoteManifest(FileManifest manifest) async {
    final remotePath = '$_remoteBaseFolder/$_manifestFileName';
    final stringData = JsonEncoder.withIndent('  ').convert(manifest.toJson());
    final bytes = utf8.encode(stringData);
    await _oneDriveService.uploadFile(bytes, remotePath);
  }

  Future<void> _uploadFile(String relativePath) async {
    final localFile = File('$_localBasePath/$relativePath');
    final bytes = await localFile.readAsBytes();
    final remotePath = '$_remoteBaseFolder/$relativePath';
    await _oneDriveService.uploadFile(bytes, remotePath);
  }

  Future<void> _downloadFile(String relativePath) async {
    final remotePath = '$_remoteBaseFolder/$relativePath';
    final bytes = await _oneDriveService.downloadFile(remotePath);
    if (bytes != null) {
      final localFile = File('$_localBasePath/$relativePath');
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes);
    }
  }
}