import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration options for SVGA caching
class SVGACacheConfig {
  /// Maximum number of cached files (default: 100)
  final int maxCacheSize;

  /// Cache expiration time in days (default: 7 days)
  final int cacheExpirationDays;

  /// Maximum size per cached file in bytes (default: 10MB)
  final int maxFileSizeBytes;

  const SVGACacheConfig({
    this.maxCacheSize = 100,
    this.cacheExpirationDays = 7,
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10MB
  });
}

/// Metadata for cached SVGA files
class SVGACacheEntry {
  final String url;
  final String filePath;
  final DateTime cacheTime;
  final int fileSize;

  const SVGACacheEntry({
    required this.url,
    required this.filePath,
    required this.cacheTime,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'filePath': filePath,
        'cacheTime': cacheTime.millisecondsSinceEpoch,
        'fileSize': fileSize,
      };

  factory SVGACacheEntry.fromJson(Map<String, dynamic> json) => SVGACacheEntry(
        url: json['url'],
        filePath: json['filePath'],
        cacheTime: DateTime.fromMillisecondsSinceEpoch(json['cacheTime']),
        fileSize: json['fileSize'],
      );
}

/// Manages caching of SVGA files downloaded from network
class SVGACacheManager {
  static SVGACacheManager? _instance;
  static SVGACacheManager get instance => _instance ??= SVGACacheManager._();

  SVGACacheManager._();

  SVGACacheConfig _config = const SVGACacheConfig();
  Directory? _cacheDirectory;
  SharedPreferences? _prefs;

  /// Initialize the cache manager with custom configuration
  Future<void> initialize([SVGACacheConfig? config]) async {
    _config = config ?? const SVGACacheConfig();
    _cacheDirectory = await _getCacheDirectory();
    _prefs = await SharedPreferences.getInstance();

    // Clean expired cache on initialization
    await _cleanExpiredCache();
  }

  /// Get cached file bytes if available and not expired
  Future<Uint8List?> getCachedFile(String url) async {
    await _ensureInitialized();

    final cacheKey = _generateCacheKey(url);
    final cacheEntry = await _getCacheEntry(cacheKey);

    if (cacheEntry == null) return null;

    // Check if cache is expired
    final now = DateTime.now();
    final expirationTime = cacheEntry.cacheTime.add(
      Duration(days: _config.cacheExpirationDays),
    );

    if (now.isAfter(expirationTime)) {
      await _removeCacheEntry(cacheKey);
      return null;
    }

    // Check if file still exists
    final file = File(cacheEntry.filePath);
    if (!await file.exists()) {
      await _removeCacheEntry(cacheKey);
      return null;
    }

    try {
      return await file.readAsBytes();
    } catch (e) {
      // File corrupted, remove from cache
      await _removeCacheEntry(cacheKey);
      return null;
    }
  }

  /// Cache downloaded file bytes
  Future<void> cacheFile(String url, Uint8List bytes) async {
    await _ensureInitialized();

    // Check file size limit
    if (bytes.length > _config.maxFileSizeBytes) {
      return; // Don't cache files that are too large
    }

    final cacheKey = _generateCacheKey(url);
    final fileName = '$cacheKey.svga';
    final filePath = '${_cacheDirectory!.path}/$fileName';

    try {
      // Write file to disk
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      // Store cache metadata
      final cacheEntry = SVGACacheEntry(
        url: url,
        filePath: filePath,
        cacheTime: DateTime.now(),
        fileSize: bytes.length,
      );

      await _storeCacheEntry(cacheKey, cacheEntry);

      // Clean old cache if needed
      await _cleanOldCacheIfNeeded();
    } catch (e) {
      // Failed to cache, continue silently
    }
  }

  /// Clear all cached files
  Future<void> clearCache() async {
    await _ensureInitialized();

    try {
      // Remove all cache files
      if (await _cacheDirectory!.exists()) {
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create();
      }

      // Clear metadata
      await _prefs!.clear();
    } catch (e) {
      // Failed to clear cache, continue silently
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();

    final cacheKeys = _prefs!.getKeys().where((key) => key.startsWith('svga_cache_')).toList();
    int totalFiles = cacheKeys.length;
    int totalSize = 0;
    int expiredFiles = 0;

    final now = DateTime.now();

    for (final key in cacheKeys) {
      try {
        final cacheEntry = await _getCacheEntry(key.substring('svga_cache_'.length));
        if (cacheEntry != null) {
          totalSize += cacheEntry.fileSize;

          final expirationTime = cacheEntry.cacheTime.add(
            Duration(days: _config.cacheExpirationDays),
          );

          if (now.isAfter(expirationTime)) {
            expiredFiles++;
          }
        }
      } catch (e) {
        // Skip corrupted entries
      }
    }

    return {
      'totalFiles': totalFiles,
      'totalSizeBytes': totalSize,
      'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      'expiredFiles': expiredFiles,
      'maxCacheSize': _config.maxCacheSize,
      'cacheExpirationDays': _config.cacheExpirationDays,
    };
  }

  // Private methods

  Future<void> _ensureInitialized() async {
    if (_cacheDirectory == null || _prefs == null) {
      await initialize();
    }
  }

  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appDir.path}/svga_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _generateCacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<SVGACacheEntry?> _getCacheEntry(String cacheKey) async {
    final json = _prefs!.getString('svga_cache_$cacheKey');
    if (json == null) return null;

    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return SVGACacheEntry.fromJson(data);
    } catch (e) {
      // Remove corrupted entry
      await _prefs!.remove('svga_cache_$cacheKey');
      return null;
    }
  }

  Future<void> _storeCacheEntry(String cacheKey, SVGACacheEntry entry) async {
    final json = jsonEncode(entry.toJson());
    await _prefs!.setString('svga_cache_$cacheKey', json);
  }

  Future<void> _removeCacheEntry(String cacheKey) async {
    final cacheEntry = await _getCacheEntry(cacheKey);
    if (cacheEntry != null) {
      // Remove file
      try {
        final file = File(cacheEntry.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // File deletion failed, continue
      }
    }

    // Remove metadata
    await _prefs!.remove('svga_cache_$cacheKey');
  }

  Future<void> _cleanExpiredCache() async {
    final cacheKeys = _prefs!.getKeys().where((key) => key.startsWith('svga_cache_')).toList();
    final now = DateTime.now();

    for (final key in cacheKeys) {
      final cacheKey = key.substring('svga_cache_'.length);
      final cacheEntry = await _getCacheEntry(cacheKey);

      if (cacheEntry != null) {
        final expirationTime = cacheEntry.cacheTime.add(
          Duration(days: _config.cacheExpirationDays),
        );

        if (now.isAfter(expirationTime)) {
          await _removeCacheEntry(cacheKey);
        }
      }
    }
  }

  Future<void> _cleanOldCacheIfNeeded() async {
    final cacheKeys = _prefs!.getKeys().where((key) => key.startsWith('svga_cache_')).toList();

    if (cacheKeys.length <= _config.maxCacheSize) return;

    // Get all cache entries with timestamps
    final entries = <String, SVGACacheEntry>{};
    for (final key in cacheKeys) {
      final cacheKey = key.substring('svga_cache_'.length);
      final cacheEntry = await _getCacheEntry(cacheKey);
      if (cacheEntry != null) {
        entries[cacheKey] = cacheEntry;
      }
    }

    // Sort by cache time (oldest first)
    final sortedEntries = entries.entries.toList()..sort((a, b) => a.value.cacheTime.compareTo(b.value.cacheTime));

    // Remove oldest entries to fit within max cache size
    final entriesToRemove = sortedEntries.length - _config.maxCacheSize;
    for (int i = 0; i < entriesToRemove; i++) {
      await _removeCacheEntry(sortedEntries[i].key);
    }
  }
}
