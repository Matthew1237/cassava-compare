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
// Design principle: the app shows facts and differences and leaves the
// decision to the user. The one exception is the "Best overall choice" card
// on the compare screen: a relative score (low sugar, fat and cholesterol,
// high protein, few risk-classified ingredients) that is only meaningful
// within the group of products being compared, with a per-factor breakdown.
//
// File layout
// -----------
//   main.dart            app shell, scanner screen, home screen
//   models.dart          Metric, Nutrition, Review, Product, helpers
//   services.dart        Open Food Facts lookup, ReviewProvider, ReviewAnalyzer
//   compare_screen.dart  compare screen, best-overall score, nutrition/review widgets
//   product_search.dart  search for a product by name
//   product_sheet.dart   product details: price, similar products
//   watchlist.dart       allergens / diet / nutrients the user watches
//   saved.dart           saved comparisons, remembered prices, share text
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'compare_screen.dart';
import 'models.dart';
import 'product_search.dart';
import 'product_sheet.dart';
import 'saved.dart';
import 'services.dart';
import 'watchlist.dart';

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

/// Rapid scan: the camera stays open and every new barcode goes to [onCode],
/// which adds it to the basket and returns a status line and the product
/// that was added (null when nothing was added).
class ScannerScreen extends StatefulWidget {
  final Future<(String, Product?)> Function(String code) onCode;
  const ScannerScreen({super.key, required this.onCode});

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
  final _textPainter = TextPainter(textDirection: TextDirection.ltr);
  bool _busy = false;
  bool _found = false;
  bool _zoomed = false;
  bool _stuck = false;
  String? _status;
  Product? _last;
  int _added = 0;
  final _seen = <String>{};

  /// The barcode just read and the camera frame size, for the highlight.
  (Barcode, Size)? _hit;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _armHint();
  }

  /// Shows a tip if nothing has been read for a while.
  void _armHint() {
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_busy) setState(() => _stuck = true);
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final barcode = capture.barcodes.where((b) => (b.rawValue ?? '').isNotEmpty).firstOrNull;
    if (barcode == null || _seen.contains(barcode.rawValue)) return;
    HapticFeedback.mediumImpact();
    _hit = (barcode, capture.size);
    await _handle(barcode.rawValue!);
  }

  Future<void> _handle(String code) async {
    _busy = true;
    _seen.add(code);
    _hintTimer?.cancel();
    setState(() {
      _found = true;
      _stuck = false;
      _status = 'Looking up $code…';
    });
    final (msg, added) = await widget.onCode(code);
    if (!mounted) return;
    if (added == null) _seen.remove(code); // allow a retry after an error
    setState(() {
      _status = msg;
      if (added != null) {
        _last = added;
        _added++;
      }
    });
    // Keep the highlight briefly so the read is visible, then scan the next pack.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _found = false;
      _hit = null;
    });
    _busy = false;
    _armHint();
  }

  Future<void> _typeNumber() async {
    final code = await askBarcode(context);
    if (code != null && !_busy) await _handle(code);
  }

  Future<void> _toggleZoom() async {
    setState(() => _zoomed = !_zoomed);
    await _controller.setZoomScale(_zoomed ? 0.4 : 0);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _textPainter.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        // A wide window suits 1D barcodes; sit it above the tray, not dead centre.
        final w = math.min(box.maxWidth - 48, 340.0);
        final window = Rect.fromCenter(
            center: Offset(box.maxWidth / 2, box.maxHeight * 0.38), width: w, height: w * 0.6);
        final hit = _hit;
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              tapToFocus: true,
              // Read only inside the window (with some slack), so the pack
              // next to it on the shelf isn't scanned by accident.
              scanWindow: window.inflate(24),
              errorBuilder: (context, error) => _CameraError(error),
            ),
            CustomPaint(painter: _ViewfinderPainter(window, _found ? _readGreen : cream)),
            if (hit != null && _found)
              CustomPaint(
                painter: BarcodePainter(
                  barcodeCorners: hit.$1.corners,
                  barcodeSize: hit.$1.size,
                  barcodeValue: '',
                  boxFit: BoxFit.cover,
                  cameraPreviewSize: hit.$2,
                  color: _readGreen,
                  style: PaintingStyle.stroke,
                  textPainter: _textPainter,
                  deviceOrientation: _controller.value.deviceOrientation,
                ),
              ),
            if (!_found)
              Positioned.fromRect(
                rect: window,
                child: Center(child: _ScanLine(width: w - 40, travel: window.height - 40)),
              ),
            // Instruction just under the window.
            Positioned(
              left: 24,
              right: 24,
              top: window.bottom + 16,
              child: Text(
                _stuck
                    ? 'Having trouble? Try the torch, move a little further away, or type the number.'
                    : 'Fit the barcode inside the frame',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, child: _topBar(context)),
            Positioned(left: 0, right: 0, bottom: 0, child: _tray(context)),
          ],
        );
      }),
    );
  }

  Widget _topBar(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close scanner',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              const Text('Scan products',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_added > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$_added added',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      );

  /// Thumb-reach controls above a card with the last product read.
  Widget _tray(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = _last;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundControl(
                  icon: Icons.dialpad, label: 'Type number', onTap: _busy ? null : _typeNumber),
              const SizedBox(width: 28),
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (_, state, _) {
                  final on = state.torchState == TorchState.on;
                  return _RoundControl(
                    icon: on ? Icons.flashlight_on : Icons.flashlight_off_outlined,
                    label: on ? 'Torch on' : 'Torch',
                    active: on,
                    onTap: state.torchState == TorchState.unavailable
                        ? null
                        : () => _controller.toggleTorch(),
                  );
                },
              ),
              const SizedBox(width: 28),
              _RoundControl(
                icon: _zoomed ? Icons.zoom_out : Icons.zoom_in,
                label: _zoomed ? 'Zoom out' : 'Zoom in',
                active: _zoomed,
                onTap: _toggleZoom,
              ),
            ],
          ),
        ),
        Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey('$_status${last?.barcode}'),
                      children: [
                        if (last != null)
                          ProductThumb(last, size: 48)
                        else
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.shopping_basket_outlined, color: cs.onSurfaceVariant),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                last?.name ?? 'Nothing scanned yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _status ?? 'Each pack you scan goes straight into your basket.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_added == 0 ? 'Done' : 'Done · $_added added'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _readGreen = Color(0xFF6BD49A);

/// Asks for a barcode number. Returns its digits, or null when cancelled or
/// when nothing numeric was entered (pasted text like "abc 123" keeps "123").
Future<String?> askBarcode(BuildContext context) async {
  final controller = TextEditingController();
  final raw = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter barcode'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g. 5449000000996'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Look up')),
      ],
    ),
  );
  final digits = raw?.replaceAll(RegExp(r'\D'), '') ?? '';
  return digits.isEmpty ? null : digits;
}

/// A round camera control with a label underneath.
class _RoundControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _RoundControl({required this.icon, required this.label, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? cream : Colors.black.withValues(alpha: 0.5),
          shape: const CircleBorder(),
          child: IconButton(
            iconSize: 24,
            padding: const EdgeInsets.all(14),
            icon: Icon(icon, color: active ? _spruce : Colors.white),
            tooltip: label,
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4)])),
      ],
    );
  }
}

/// Dims the camera everywhere except a rounded window with corner brackets.
class _ViewfinderPainter extends CustomPainter {
  final Rect window;
  final Color color;
  const _ViewfinderPainter(this.window, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = window;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(20));
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
    const l = 34.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + dy * l)
          ..lineTo(c.dx, c.dy + dy * 14)
          ..quadraticBezierTo(c.dx, c.dy, c.dx + dx * 14, c.dy)
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
  /// Product database; tests pass a fake.
  final OpenFoodFactsService? service;
  const HomeScreen({super.key, this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _off = widget.service ?? OpenFoodFactsService();
  final ReviewProvider _reviews = NoReviewProvider();
  final List<Product> _items = [];
  bool _busy = false;
  WatchList _watch = const WatchList();
  Map<String, (double, double?)> _prices = {};

  /// Last barcode Open Food Facts didn't have, offered as "add it" in a toast.
  String? _missing;

  @override
  void initState() {
    super.initState();
    WatchList.load().then((w) {
      if (mounted) setState(() => _watch = w);
    });
    PriceStore.load().then((p) => _prices = p);
  }

  void _toast(String msg, {String? missingCode}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        action: missingCode == null
            ? null
            : SnackBarAction(label: 'Add it', onPressed: () => _addToOpenFoodFacts(missingCode)),
      ));
  }

  /// Open Food Facts' own page for the barcode offers "Add a product".
  Future<void> _addToOpenFoodFacts(String code) async {
    final ok = await launchUrl(Uri.https('world.openfoodfacts.org', '/product/$code'),
        mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open the browser.');
  }

  /// Adds a product and toasts the result.
  Future<void> _addAndToast(String code) async {
    final (msg, _) = await _addBarcode(code);
    final missing = _missing;
    _missing = null;
    _toast(msg, missingCode: missing);
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScannerScreen(onCode: (code) async {
        final (msg, added) = await _addBarcode(code);
        return (msg, added ? _items.last : null);
      }),
    ));
    final missing = _missing;
    _missing = null;
    if (missing != null) {
      _toast('$missing isn\'t in Open Food Facts yet.', missingCode: missing);
    }
  }

  Future<void> _openWatchList() async {
    final w = await Navigator.of(context)
        .push<WatchList>(MaterialPageRoute(builder: (_) => WatchListScreen(initial: _watch)));
    if (w != null && mounted) setState(() => _watch = w);
  }

  Future<void> _openSaved() async {
    // An old "Removed … Undo" would otherwise follow onto the saved list.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final c = await Navigator.of(context)
        .push<SavedComparison>(MaterialPageRoute(builder: (_) => const SavedScreen()));
    if (c == null || !mounted) return;
    final previous = List.of(_items); // offered back via Undo
    setState(_items.clear);
    var loaded = 0;
    for (final code in c.barcodes) {
      final (_, added) = await _addBarcode(code);
      if (added) loaded++;
    }
    _missing = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Loaded "${c.name}": $loaded of ${c.barcodes.length} products.'),
        action: previous.isEmpty
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  if (mounted) {
                    setState(() => _items
                      ..clear()
                      ..addAll(previous));
                  }
                },
              ),
      ));
  }

  Future<void> _editPrice(Product p) async {
    final r = await askPrice(context, p);
    if (r == null || !mounted) return;
    final (price, grams) = r;
    setState(() {
      p.price = price;
      if (grams != null) p.quantityGrams = grams;
    });
    if (price == null) {
      _prices.remove(p.barcode);
    } else {
      _prices[p.barcode] = (price, grams);
    }
    await PriceStore.set(p.barcode, price, grams);
  }

  void _openProduct(Product p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductSheet(
        product: p,
        service: _off,
        watch: _watch,
        onAdd: _addAndToast,
        onEditPrice: _editPrice,
        inBasket: (code) => _items.any((i) => i.barcode == code),
      ),
    );
  }

  Future<void> _enterManually() async {
    final code = await askBarcode(context);
    if (code != null) await _addAndToast(code);
  }

  Future<void> _bySearch() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProductSearchScreen()),
    );
    if (code != null) await _addAndToast(code);
  }

  /// Looks the barcode up and adds it to the basket. Returns a short status
  /// line and whether the product was added.
  Future<(String, bool)> _addBarcode(String code) async {
    if (_items.any((p) => p.barcode == code)) {
      return ('That product is already added.', false);
    }
    setState(() => _busy = true);
    try {
      final p = await _off.lookup(code);
      if (!mounted) return ('', false);
      if (p == null) {
        _missing = code;
        return ('Barcode $code is not a valid food product.', false);
      }
      p.color = productPalette[_items.length % productPalette.length];
      if (_prices[code] case (final price, final grams)) {
        p.price = price;
        if (grams != null) p.quantityGrams = grams;
      }
      try {
        p.reviews = await _reviews.reviewsFor(p);
      } catch (_) {
        // Reviews are optional; nutrition still works without them.
      }
      if (!mounted) return ('', false);
      setState(() => _items.add(p));
      final flags = watchFlags(p, _watch).where((f) => f.level != FlagLevel.unknown);
      return (
        flags.isEmpty ? 'Added ${p.name}' : 'Added ${p.name} · ${flags.first.text}',
        true,
      );
    } on LookupException catch (e) {
      return (e.message, false);
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
      builder: (_) => CompareScreen(products: List.of(_items), watch: _watch),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Saved comparisons',
            onPressed: _busy ? null : _openSaved,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: !_watch.isEmpty,
              smallSize: 8,
              child: const Icon(Icons.health_and_safety_outlined),
            ),
            tooltip: 'My watch-list',
            onPressed: _openWatchList,
          ),
          const SizedBox(width: 4),
        ],
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
            'Scan two or more products to see their nutrition side by side, '
            'with a best overall pick you can check against the details.',
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
                  onPressed: _busy ? null : _bySearch,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
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
                Text('Tap for details · swipe to remove',
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                [
                                  // Price first: long category names would cut it off.
                                  if (p.pricePer100g case final v?) '${v.toStringAsFixed(2)} / 100 g',
                                  p.category,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (watchFlags(p, _watch) case final flags when flags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: WatchFlagChips(flags),
                              ),
                          ],
                        ),
                        onTap: () => _openProduct(p),
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