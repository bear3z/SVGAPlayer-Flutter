import 'package:flutter/material.dart';
import 'package:svgaplayer_3/svgaplayer_flutter.dart';
import 'package:svgaplayer_flutter_example/sample.dart';

import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SVGA cache with custom configuration
  await SVGACacheManager.instance.initialize(
    const SVGACacheConfig(
      maxCacheSize: 50, // Cache up to 50 files
      cacheExpirationDays: 7, // Files expire after 7 days
      maxFileSizeBytes: 5 * 1024 * 1024, // Don't cache files larger than 5MB
    ),
  );

  runApp(ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  HomeScreen({
    super.key,
  });

  /// Callback for register dynamic items.
  final dynamicSamples = <String, void Function(MovieEntity entity)>{
    "kingset.svga": (entity) => entity.dynamicItem
      ..setText(
        TextPainter(
          text: TextSpan(
            text: "Hello, World!",
            style: TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        "banner",
      )
    // ..setImageWithUrl(
    //     "https://github.com/PonyCui/resources/blob/master/svga_replace_avatar.png?raw=true",
    //     "99")
    // ..setDynamicDrawer((canvas, frameIndex) {
    //   canvas.drawRect(Rect.fromLTWH(0, 0, 88, 88),
    //       Paint()..color = Colors.red); // draw by yourself.
    // }, "banner"),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SVGA Flutter Samples'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'cache_stats':
                  _showCacheStats(context);
                  break;
                case 'clear_cache':
                  await SVGACacheManager.instance.clearCache();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared successfully')),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cache_stats',
                child: Text('Cache Statistics'),
              ),
              const PopupMenuItem(
                value: 'clear_cache',
                child: Text('Clear Cache'),
              ),
            ],
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: samples.length,
        separatorBuilder: (_, __) => Divider(),
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(samples[index].first),
            subtitle: Text(samples[index].last),
            onTap: () => _goToSample(
              context,
              samples[index],
            ),
          );
        },
      ),
    );
  }

  void _goToSample(context, List<String> sample) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return SVGASampleScreen(
            name: sample.first,
            image: sample.last,
            dynamicCallback: dynamicSamples[sample.first],
          );
        },
      ),
    );
  }

  void _showCacheStats(BuildContext context) async {
    try {
      final stats = await SVGACacheManager.instance.getCacheStats();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cache Statistics'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Files: ${stats['totalFiles']}'),
              Text('Total Size: ${stats['totalSizeMB']} MB'),
              Text('Expired Files: ${stats['expiredFiles']}'),
              const SizedBox(height: 8),
              Text('Max Cache Size: ${stats['maxCacheSize']} files'),
              Text('Cache Expiration: ${stats['cacheExpirationDays']} days'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading cache stats: $e')),
      );
    }
  }
}
