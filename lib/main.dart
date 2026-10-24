// NutriCompare — scan product barcodes and compare nutrition facts.
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
import 'package:flutter/material.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D6B),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
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

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan a barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Line up the barcode inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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

  void _remove(Product p) => setState(() => _items.remove(p));

  void _openCompare() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CompareScreen(products: List.of(_items)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canCompare = _items.length >= 2 && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NutriCompare', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canCompare ? _openCompare : null,
        icon: const Icon(Icons.compare_arrows),
        label: Text(_items.length >= 2
            ? 'Compare ${_items.length} products'
            : 'Scan at least 2 products'),
        backgroundColor: canCompare ? cs.primary : cs.surfaceContainerHighest,
        foregroundColor: canCompare ? cs.onPrimary : cs.onSurfaceVariant,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text('Compare what you\'re about to buy',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Scan each product\'s barcode. We look up its nutrition facts and '
            'show them side by side — you decide.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan barcode'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _enterManually,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Type number'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _byFrontLabel,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Find by front label'),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Looking up product…', style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 10),
                    LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(Icons.shopping_basket_outlined,
                      size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  Text('No products yet', style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          else ...[
            Text('Scanned products (${_items.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in _items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: ProductThumb(p),
                  title: Text(p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      [p.category, p.barcode].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove',
                    onPressed: () => _remove(p),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            'Nutrition data: Open Food Facts (crowd-sourced, may be incomplete or out of date).',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}