import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_model_info.dart';

enum LocalModelStatus {
  notDownloaded,
  downloading,
  ready,
  error,
}

class DownloadProgress {
  final double progress; // 0.0 to 1.0
  final int bytesDownloaded;
  final int totalBytes;
  final double speedMBps;
  final String statusText;

  const DownloadProgress({
    required this.progress,
    required this.bytesDownloaded,
    required this.totalBytes,
    this.speedMBps = 0.0,
    this.statusText = '',
  });

  String get formattedDownloaded {
    return '${(bytesDownloaded / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedTotal {
    if (totalBytes <= 0) return 'Unknown';
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class DownloadCancelledException implements Exception {
  final String message;
  const DownloadCancelledException([this.message = 'Download cancelled by user.']);
  @override
  String toString() => message;
}

class LocalModelManager {
  static final LocalModelManager _instance = LocalModelManager._internal();
  factory LocalModelManager() => _instance;
  LocalModelManager._internal();

  static const String _prefActiveModelId = 'local_ai_selected_model_id';

  HttpClient? _downloadClient;
  bool _isCancelled = false;
  String? _currentlyDownloadingModelId;

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get downloadProgressStream =>
      _progressController.stream;

  DownloadProgress _lastProgress = const DownloadProgress(
    progress: 0.0,
    bytesDownloaded: 0,
    totalBytes: 0,
  );
  DownloadProgress get lastProgress => _lastProgress;

  String? get currentlyDownloadingModelId => _currentlyDownloadingModelId;

  /// Get the directory where local models are stored
  Future<Directory> get _modelsDirectory async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${docsDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// Get the currently active local model info
  Future<LocalModelInfo> getActiveModel() async {
    final prefs = await SharedPreferences.getInstance();
    final modelId = prefs.getString(_prefActiveModelId);
    if (modelId != null) {
      final model = LocalModelInfo.getById(modelId);
      if (model != null) return model;
    }
    return LocalModelInfo.getDefaultModel();
  }

  /// Set the active local model
  Future<void> setActiveModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveModelId, modelId);
  }

  /// Get the local file path for a model
  Future<File> getModelFile(LocalModelInfo model) async {
    final dir = await _modelsDirectory;
    return File('${dir.path}/${model.filename}');
  }

  /// Check if a model file is downloaded and ready
  Future<bool> isModelReady(LocalModelInfo model) async {
    final file = await getModelFile(model);
    if (!await file.exists()) return false;
    final length = await file.length();
    // Verify file has non-trivial size (at least 50 MB)
    return length > 50 * 1024 * 1024;
  }

  /// Get the status of a specific model
  Future<LocalModelStatus> getModelStatus(LocalModelInfo model) async {
    if (_currentlyDownloadingModelId == model.id) {
      return LocalModelStatus.downloading;
    }
    final ready = await isModelReady(model);
    return ready ? LocalModelStatus.ready : LocalModelStatus.notDownloaded;
  }

  /// Opens an HTTP download stream trying primary and fallback mirror URLs
  Future<HttpClientResponse> _openDownloadStream(
    HttpClient client,
    List<String> urls,
  ) async {
    Object? lastError;
    for (final rawUrl in urls) {
      if (_isCancelled) throw const DownloadCancelledException();
      try {
        String currentUrl = rawUrl;
        int redirectCount = 0;
        const maxRedirects = 8;

        while (redirectCount < maxRedirects) {
          if (_isCancelled) throw const DownloadCancelledException();
          final uri = Uri.parse(currentUrl);
          final request = await client.getUrl(uri);
          request.followRedirects = false;
          request.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
          );
          request.headers.set('Accept', '*/*');
          request.headers.set('Accept-Encoding', 'identity');

          final response = await request.close();

          if (response.statusCode >= 300 && response.statusCode < 400) {
            final location = response.headers.value('location');
            if (location != null && location.isNotEmpty) {
              currentUrl = Uri.parse(currentUrl).resolve(location).toString();
              redirectCount++;
              developer.log(
                'Redirecting to CDN ($redirectCount): $currentUrl',
                name: 'LocalModelManager',
              );
              continue;
            }
          }

          if (response.statusCode == 200 || response.statusCode == 206) {
            developer.log(
              'Connected to model download stream ($rawUrl)',
              name: 'LocalModelManager',
            );
            return response;
          } else {
            developer.log(
              'Candidate URL $rawUrl returned HTTP ${response.statusCode}',
              name: 'LocalModelManager',
            );
            lastError = Exception('Download server returned HTTP ${response.statusCode}');
            break; // Try next candidate URL
          }
        }
      } catch (e) {
        if (_isCancelled) throw const DownloadCancelledException();
        developer.log('Failed connecting to $rawUrl: $e', name: 'LocalModelManager');
        lastError = e;
      }
    }

    if (_isCancelled) throw const DownloadCancelledException();
    throw lastError ?? Exception('All download servers could not be reached');
  }

  /// Download a model with streaming progress and mirror fallback support
  Future<bool> downloadModel(
    LocalModelInfo model, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (_currentlyDownloadingModelId != null) {
      throw Exception(
        'Another model download is already in progress: $_currentlyDownloadingModelId',
      );
    }

    _isCancelled = false;
    _currentlyDownloadingModelId = model.id;

    final client = HttpClient();
    client.autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 25);
    _downloadClient = client;

    final targetFile = await getModelFile(model);
    final tempFile = File('${targetFile.path}.tmp');

    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    final candidateUrls = [
      model.downloadUrl,
      ...model.fallbackUrls,
    ];

    developer.log(
      'Starting download for ${model.name} (${candidateUrls.length} mirrors available)',
      name: 'LocalModelManager',
    );

    IOSink? sink;
    try {
      final response = await _openDownloadStream(client, candidateUrls);

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : model.sizeInBytes;
      int bytesDownloaded = 0;
      final activeSink = tempFile.openWrite();
      sink = activeSink;

      final startTime = DateTime.now();
      DateTime lastUpdate = startTime;
      int bytesSinceLastUpdate = 0;
      double currentSpeedMBps = 0.0;

      await for (final chunk in response) {
        if (_isCancelled) {
          developer.log('Download cancelled by user. Cleaning storage...', name: 'LocalModelManager');
          try {
            await activeSink.close();
          } catch (_) {}
          sink = null;
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
          if (await targetFile.exists()) {
            try {
              await targetFile.delete();
            } catch (_) {}
          }
          _currentlyDownloadingModelId = null;
          throw const DownloadCancelledException();
        }

        activeSink.add(chunk);
        bytesDownloaded += chunk.length;
        bytesSinceLastUpdate += chunk.length;

        final now = DateTime.now();
        final elapsedSinceUpdate = now.difference(lastUpdate).inMilliseconds;
        if (elapsedSinceUpdate >= 300 || bytesDownloaded == totalBytes) {
          if (elapsedSinceUpdate > 0) {
            currentSpeedMBps = (bytesSinceLastUpdate / (1024 * 1024)) /
                (elapsedSinceUpdate / 1000.0);
          }
          lastUpdate = now;
          bytesSinceLastUpdate = 0;

          final progressVal = totalBytes > 0
              ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0)
              : 0.0;

          _lastProgress = DownloadProgress(
            progress: progressVal,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speedMBps: currentSpeedMBps,
            statusText:
                '${(progressVal * 100).toStringAsFixed(1)}% (${(bytesDownloaded / (1024 * 1024)).toStringAsFixed(0)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB)',
          );

          _progressController.add(_lastProgress);
          onProgress?.call(_lastProgress);
        }
      }

      await activeSink.flush();
      await activeSink.close();
      sink = null;

      // Rename temp file to final destination
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      await setActiveModel(model.id);
      _currentlyDownloadingModelId = null;

      _lastProgress = DownloadProgress(
        progress: 1.0,
        bytesDownloaded: totalBytes,
        totalBytes: totalBytes,
        statusText: 'Download Complete',
      );
      _progressController.add(_lastProgress);

      developer.log(
        'Model ${model.name} downloaded successfully (${targetFile.path})',
        name: 'LocalModelManager',
      );
      return true;
    } catch (e) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      // Ensure all partial temporary files are wiped from disk
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
          developer.log('Deleted partial temp file (${tempFile.path})', name: 'LocalModelManager');
        } catch (_) {}
      }
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      _currentlyDownloadingModelId = null;

      if (_isCancelled || e is DownloadCancelledException) {
        developer.log('Download was cancelled cleanly, storage cleaned.', name: 'LocalModelManager');
        throw const DownloadCancelledException();
      }

      developer.log('Error downloading model: $e', name: 'LocalModelManager');
      rethrow;
    } finally {
      try {
        _downloadClient?.close(force: true);
      } catch (_) {}
      _downloadClient = null;
      _currentlyDownloadingModelId = null;
    }
  }

  /// Cancel any active download and purge temp storage
  void cancelDownload() {
    _isCancelled = true;
    try {
      _downloadClient?.close(force: true);
    } catch (_) {}
    _downloadClient = null;
    _currentlyDownloadingModelId = null;
  }

  /// Delete a model file from disk
  Future<bool> deleteModel(LocalModelInfo model) async {
    try {
      final file = await getModelFile(model);
      if (await file.exists()) {
        await file.delete();
        developer.log('Deleted model ${model.name}', name: 'LocalModelManager');
        return true;
      }
      return false;
    } catch (e) {
      developer.log('Error deleting model: $e', name: 'LocalModelManager');
      return false;
    }
  }

  /// Get total disk space used by all downloaded models
  Future<int> getTotalModelsDiskUsage() async {
    try {
      final dir = await _modelsDirectory;
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
