# SVGAPlayer-Flutter AI Coding Instructions

## Architecture Overview

This is a Flutter package that renders SVGA animations (exported from Adobe Animate/After Effects) using CustomPainter. The core architecture consists of:

- **Parser layer** (`parser.dart`): Decodes compressed SVGA files from URLs/assets using protobuf
- **Player layer** (`player.dart`): Main animation controller and widget implementation  
- **Painter layer** (`painter.dart`): CustomPainter that renders frames using Canvas operations
- **Proto definitions** (`proto/`): Generated protobuf classes for SVGA file format
- **Dynamic entities** (`dynamic_entity.dart`): Runtime customization (text, images, custom drawing)

## Key Components

### SVGAAnimationController
Extends Flutter's `AnimationController` with SVGA-specific functionality:
- Manages `MovieEntity` lifecycle with auto-disposal
- Calculates duration from FPS and frame count (defaults to 20fps if 0)
- Handles canvas clearing state via `_canvasNeedsClear`

### Rendering Flow
1. `SVGAParser` inflates zlib-compressed bytes → protobuf `MovieEntity`
2. Images are pre-decoded and cached during parsing
3. `_SVGAPainter` renders frame-by-frame using precalculated transforms
4. Canvas scaling applies `BoxFit` to match widget bounds

### Dynamic Content System
Runtime customization via `SVGADynamicEntity`:
```dart
entity.dynamicItem
  ..setText(TextPainter(...), "banner")  // Replace text by key
  ..setImage(uiImage, "avatar")          // Replace image by key  
  ..setHidden(true, "layer_name")        // Hide/show layers
  ..setDynamicDrawer(customDrawer, "key") // Custom Canvas drawing
```

## Critical Patterns

### File Structure Convention
- Main library exports in `svgaplayer_flutter.dart` 
- Player components use `part of 'player.dart'` pattern
- Protobuf files auto-generated, don't edit manually
- Example app demonstrates all major usage patterns

### Performance Considerations
- Transform matrices pre-calculated in `_precalculateTransforms()`
- Path and transform caching with HashMap for repeated elements
- Timeline profiling enabled in debug mode only
- FilterQuality.high required for web/CanvasKit, FilterQuality.low for mobile

### Error Handling
- Parser catches decode failures and reports via FlutterError
- Controllers check disposal state before operations
- Invalid SVGA files validated (viewBox > 0, frames >= 1)
- Network loading failures handled in simple player

## Development Workflows

### Running Examples
```bash
cd example
flutter run  # Test with built-in samples + remote SVGA files
```

### Testing New SVGA Files
Add to `example/lib/constants.dart` samples list, or test URLs directly in `SVGASimpleImage(resUrl: "...")`.

### Protocol Buffer Updates
Regenerate proto files if `svga.proto` changes:
```bash
protoc --dart_out=lib/proto svga.proto
```

### Performance Profiling
Timeline tasks automatically capture decode/render metrics in debug builds - check Flutter DevTools timeline.

## Common Integration Patterns

### Simple Usage (Auto-playing)
```dart
SVGASimpleImage(resUrl: "https://example.com/animation.svga")
```

### Advanced Control
```dart
// Controller lifecycle matches widget lifecycle
final controller = SVGAAnimationController(vsync: this);
controller.videoItem = await SVGAParser.shared.decodeFromAssets("animation.svga");
controller.repeat(); // or .forward(), .reverse()
// Always dispose in widget.dispose()
```

### Dynamic Content
```dart
final videoItem = await SVGAParser.shared.decodeFromURL(url);
videoItem.dynamicItem.setText(textPainter, "text_layer_key");
controller.videoItem = videoItem; // Apply changes
```

### Caching Network Files
```dart
// Initialize cache manager (typically in main())
await SVGACacheManager.instance.initialize(
  SVGACacheConfig(
    maxCacheSize: 50,
    cacheExpirationDays: 7,
    maxFileSizeBytes: 5 * 1024 * 1024,
  ),
);

// Network calls automatically use cache
final videoItem = await SVGAParser.shared.decodeFromURL(url); // Uses cache by default
final videoItem2 = await SVGAParser.shared.decodeFromURL(url, useCache: false); // Skip cache

// Cache management
final stats = await SVGACacheManager.instance.getCacheStats();
await SVGACacheManager.instance.clearCache();
```

## Package Dependencies
- `protobuf`: SVGA file format parsing
- `archive`: ZLib decompression  
- `path_drawing`: SVG path rendering
- `http`: Remote file loading
- `path_provider`: Cache directory access
- `shared_preferences`: Cache metadata storage
- `crypto`: Cache key generation

## Platform Considerations
- Web builds require FilterQuality.high for proper CanvasKit rendering
- iOS/Android use FilterQuality.low for performance
- `allowDrawingOverflow` controls canvas bounds (null = allow overflow for compatibility)