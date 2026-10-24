// Cassava — scan product barcodes and compare nutrition facts.
//
// How it works
// ------------
// A barcode (EAN-13 / UPC-A / ...) is only an ID number. It carries no
// nutrition data. The app reads the number with the camera, then looks the
// product up online in Open Food Facts (free, crowd-sourced database).
//
// Setup
// -----
//   flutter pub add http mobile_scanner
//   Android: add <uses-permission android:name="android.permission.INTERNET"/>
//            to android/app/src/main/AndroidManifest.xml (needed in release builds)
//   iOS:     add NSCameraUsageDescription to ios/Runner/Info.plist
//
// Reviews
// -------
// Open Food Facts has no reviews, and there is no free, open review source.
// Reviews sit behind the `ReviewProvider` interface. The default provider
// returns nothing, and the Reviews tab says so. Plug in a licensed review
// API there if you have one.
//
// Design principle: the app NEVER scores or ranks products. It shows facts
// and differences, and the user decides.
//
// File layout
// -----------
//   main.dart            app shell, scanner screen, home screen
//   models.dart          Metric, Nutrition, Review, Product, helpers
//   services.dart        Open Food Facts lookup, ReviewProvider, ReviewAnalyzer
//   compare_screen.dart  compare screen and its nutrition/review widgets
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'compare_screen.dart';
import 'front_label.dart';
import 'models.dart';
import 'services.dart';

void main() => runApp(const NutriCompareApp());

// ─────────────────────────────────────────────────────────────────────────────
// App shell
// ─────────────────────────────────────────────────────────────────────────────

class NutriCompareApp extends StatelessWidget {
  const NutriCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cassava',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

/// Brand colours, taken from the line-art logo: one green, one cream.
const leaf = Color(0xFF2E7D6B);
const cream = Color(0xFFF6EEDF);
const _spruce = Color(0xFF17302A);

ThemeData _theme(Brightness b) {
  final light = b == Brightness.light;
  final cs = ColorScheme.fromSeed(
    seedColor: leaf,
    brightness: b,
  ).copyWith(
    primary: light ? leaf : null,
    surface: light ? const Color(0xFFF2F4F1) : null,
    surfaceContainerLowest: light ? Colors.white : null,
    onSurface: light ? _spruce : null,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: cs);
  final t = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    textTheme: t.copyWith(
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: t.titleLarge?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.4, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLowest,
      margin: EdgeInsets.zero,
      // Soft white cards on a tinted page instead of a border on everything.
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      dividerColor: cs.outlineVariant.withValues(alpha: 0.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: cs.outlineVariant),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// The line-art logo: a cassava leaf inside scanner corners, drawn in code.
class CassavaMark extends StatelessWidget {
  final double size;
  final Color tile, line;
  const CassavaMark({super.key, this.size = 32, this.tile = leaf, this.line = cream});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Cassava logo',
        child: CustomPaint(size: Size.square(size), painter: _MarkPainter(tile, line)),
      );
}

class _MarkPainter extends CustomPainter {
  final Color tile, line;
  const _MarkPainter(this.tile, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the logo's 256-unit grid, then scaled.
    canvas.scale(size.width / 256);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 256, 256), const Radius.circular(58)),
        Paint()..color = tile);
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(128, 186), const Offset(128, 208), p);
    for (final (deg, ry) in [(-60.0, 34.0), (-30.0, 42.0), (0.0, 48.0), (30.0, 42.0), (60.0, 34.0)]) {
      canvas.save();
      canvas.translate(128, 186);
      canvas.rotate(deg * math.pi / 180);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -ry - 4), width: 20, height: ry * 2), p);
      canvas.restore();
    }
    for (final (x, y, dx, dy) in [
      (44.0, 44.0, 1.0, 1.0),
      (212.0, 44.0, -1.0, 1.0),
      (44.0, 212.0, 1.0, -1.0),
      (212.0, 212.0, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * 28)
          ..lineTo(x, y + dy * 12)
          ..quadraticBezierTo(x, y, x + dx * 12, y)
          ..lineTo(x + dx * 28, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.tile != tile || old.line != line;
}

// ─────────────────────────────────────────────────────────────────────────────
// Barcode scanner screen
// ─────────────────────────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _found = false;

  static const _window = Size(290, 170);

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    // Flash the frame green briefly so the read is visible, then return.
    setState(() => _found = true);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) Navigator.of(context).pop(code);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _found ? const Color(0xFF6BD49A) : cream;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan a barcode', style: TextStyle(color: Colors.white)),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(on ? Icons.flashlight_on : Icons.flashlight_off_outlined),
                color: on ? cream : Colors.white70,
                tooltip: on ? 'Turn torch off' : 'Turn torch on',
                onPressed: state.torchState == TorchState.unavailable
                    ? null
                    : () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error),
          ),
          CustomPaint(painter: _ViewfinderPainter(_window, frame)),
          if (!_found) const Center(child: _ScanLine(width: 250, travel: 150)),
          Positioned(
            left: 24,
            right: 24,
            bottom: 56,
            child: Column(
              children: [
                Text(
                  _found ? 'Got it' : 'Fit the barcode inside the frame',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hold steady about a hand\'s width away',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims the camera everywhere except a rounded window with corner brackets.
class _ViewfinderPainter extends CustomPainter {
  final Size window;
  final Color color;
  const _ViewfinderPainter(this.window, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCenter(
        center: size.center(Offset.zero), width: window.width, height: window.height);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size),
          Path()..addRRect(rr)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 30.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + dy * l)
          ..lineTo(c.dx, c.dy + dy * 12)
          ..quadraticBezierTo(c.dx, c.dy, c.dx + dx * 12, c.dy)
          ..lineTo(c.dx + dx * l, c.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.color != color || old.window != window;
}

/// A thin line sweeping the window, so the screen reads as "working".
class _ScanLine extends StatefulWidget {
  final double width, travel;
  const _ScanLine({required this.width, required this.travel});

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, (Curves.easeInOut.transform(_c.value) - 0.5) * widget.travel),
        child: child,
      ),
      child: Container(
        width: widget.width,
        height: 2,
        decoration: BoxDecoration(
          color: cream.withValues(alpha: 0.9),
          boxShadow: [BoxShadow(color: cream.withValues(alpha: 0.5), blurRadius: 8)],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError(this.error);

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                denied ? 'Camera access is off' : 'The camera could not start',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                denied
                    ? 'Allow camera access in Settings, or go back and type the barcode number.'
                    : 'Go back and type the barcode number instead.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home: scan / add products
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _off = OpenFoodFactsService();
  final ReviewProvider _reviews = NoReviewProvider();
  final List<Product> _items = [];
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code != null) await _addBarcode(code);
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 5449000000996'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Look up')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) await _addBarcode(code);
  }

  Future<void> _byFrontLabel() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FrontLabelScreen(service: _off)),
    );
    if (code != null) await _addBarcode(code);
  }

  Future<void> _addBarcode(String code) async {
    if (_items.any((p) => p.barcode == code)) {
      _toast('That product is already added.');
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await _off.lookup(code);
      if (!mounted) return;
      if (p == null) {
        _toast('Barcode $code was not found in Open Food Facts.');
      } else {
        p.color = productPalette[_items.length % productPalette.length];
        try {
          p.reviews = await _reviews.reviewsFor(p);
        } catch (_) {
          // Reviews are optional; nutrition still works without them.
        }
        if (!mounted) return;
        setState(() => _items.add(p));
      }
    } on LookupException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(Product p) {
    final i = _items.indexOf(p);
    setState(() => _items.removeAt(i));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed ${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted && !_items.contains(p)) {
              setState(() => _items.insert(i.clamp(0, _items.length), p));
            }
          },
        ),
      ));
  }

  void _openCompare() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CompareScreen(products: List.of(_items)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CassavaMark(size: 30),
            SizedBox(width: 10),
            Text('Cassava'),
          ],
        ),
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : _CompareBar(products: _items, busy: _busy, onCompare: _openCompare),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Compare before you buy', style: tt.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Scan two or more products to see their nutrition side by side. '
            'No scores — you decide.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _ScanHero(onTap: _busy ? null : _scan),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _enterManually,
                  icon: const Icon(Icons.dialpad),
                  label: const Text('Type number'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _byFrontLabel,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Front label'),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !_busy
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        const SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 12),
                        Text('Looking up product…', style: tt.bodyMedium),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 32),
          if (_items.isEmpty)
            const _EmptyBasket()
          else ...[
            Row(
              children: [
                Text('Your basket', style: tt.titleMedium),
                const SizedBox(width: 8),
                Text('${_items.length}',
                    style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text('Swipe to remove',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, p) in _items.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 76, color: cs.outlineVariant.withValues(alpha: 0.5)),
                    Dismissible(
                      key: ValueKey(p.barcode),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _remove(p),
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProductThumb(p, size: 46),
                            // The product's colour on every chart in the compare screen.
                            Positioned(
                              right: -3,
                              bottom: -3,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: p.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cs.surfaceContainerLowest, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.category, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove ${p.name}',
                          onPressed: () => _remove(p),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Nutrition data from Open Food Facts. It is crowd-sourced and may be '
            'incomplete or out of date.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The primary action, in the logo's green and cream.
class _ScanHero extends StatelessWidget {
  final VoidCallback? onTap;
  const _ScanHero({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: leaf,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                CassavaMark(size: 60, tile: _spruce),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scan a barcode',
                          style: TextStyle(
                              color: cream,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                      SizedBox(height: 4),
                      Text('Point your camera at the stripes on the pack',
                          style: TextStyle(color: Color(0xD9F6EEDF))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cream),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.shopping_basket_outlined, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text('Your basket is empty', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text('Scan the first product to start a comparison.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  final List<Product> products;
  final bool busy;
  final VoidCallback onCompare;
  const _CompareBar({required this.products, required this.busy, required this.onCompare});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = products.length >= 2;
    final shown = products.take(4).toList();
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // Overlapping colour dots, one per product.
              SizedBox(
                width: 14.0 * shown.length + 10,
                height: 24,
                child: Stack(
                  children: [
                    for (final (i, p) in shown.indexed)
                      Positioned(
                        left: i * 14.0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: p.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surfaceContainer, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ready ? '${products.length} products ready' : 'Add one more to compare',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: ready && !busy ? onCompare : null,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
