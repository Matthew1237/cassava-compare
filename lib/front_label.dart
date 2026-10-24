// Front-of-pack recognition for NutriCompare.
//
// Flow: photo of the front of the pack -> on-device OCR reads brand/name text
// -> text search in Open Food Facts -> user picks the matching candidate ->
// the barcode is returned and the normal lookup() fills in nutrition.
//
// Setup:
//   flutter pub add image_picker google_mlkit_text_recognition
//   iOS: add NSCameraUsageDescription (already needed for scanning).
//
// Integration in HomeScreen (add a third button next to "Type number"):
//
//   Future<void> _byFrontLabel() async {
//     final code = await Navigator.of(context).push<String>(MaterialPageRoute(
//         builder: (_) => FrontLabelScreen(service: _off)));
//     if (code != null) await _addBarcode(code);
//   }
//
// Notes:
//  - OCR reads printed text only. It does not identify logos or packaging
//    by shape, so stylized brand marks may need the text field edited.
//  - Open Food Facts asks apps to keep search traffic modest (search is
//    rate-limited), so search runs on a button press, not as-you-type.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'main.dart';

class Candidate {
  final String barcode, name, brand;
  final String? imageUrl;
  const Candidate(this.barcode, this.name, this.brand, this.imageUrl);
}

class FrontLabelSearch {
  Future<List<Candidate>> search(String text) async {
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': text,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '12',
      'fields': 'code,product_name,brands,image_front_small_url',
    });
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'User-Agent': 'NutriCompare/1.0 (flutter app)'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw LookupException('The search timed out. Check your connection.');
    } catch (_) {
      throw LookupException('Could not reach the product database. Are you online?');
    }
    if (res.statusCode != 200) {
      throw LookupException('Product database error (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (json['products'] as List?) ?? const [];
    String s(dynamic v) => (v as String?)?.trim() ?? '';
    return [
      for (final p in list.cast<Map<String, dynamic>>())
        if (s(p['code']).isNotEmpty && s(p['product_name']).isNotEmpty)
          Candidate(s(p['code']), s(p['product_name']),
              s(p['brands']).split(',').first.trim(), p['image_front_small_url'] as String?),
    ];
  }
}

/// Turns raw OCR text into a short search query: keeps the most
/// word-like lines (brand and product name are usually the largest text).
String queryFromOcr(RecognizedText t) {
  final lines = <String>[];
  for (final block in t.blocks) {
    for (final line in block.lines) {
      final clean = line.text.replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ \-&\x27]'), ' ').trim();
      if (clean.length >= 3 && RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(clean)) {
        lines.add(clean);
      }
    }
  }
  // Prefer lines with the tallest bounding boxes (big front-of-pack text).
  final scored = <MapEntry<String, double>>[];
  for (final block in t.blocks) {
    for (final line in block.lines) {
      final clean = line.text.replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ \-&\x27]'), ' ').trim();
      if (lines.contains(clean)) scored.add(MapEntry(clean, line.boundingBox.height));
    }
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored.take(3).map((e) => e.key).join(' ');
}

class FrontLabelScreen extends StatefulWidget {
  final OpenFoodFactsService service;
  const FrontLabelScreen({super.key, required this.service});

  @override
  State<FrontLabelScreen> createState() => _FrontLabelScreenState();
}

class _FrontLabelScreenState extends State<FrontLabelScreen> {
  final _search = FrontLabelSearch();
  final _query = TextEditingController();
  List<Candidate> _results = [];
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600);
    if (shot == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(shot.path));
      final q = queryFromOcr(text);
      if (q.isEmpty) {
        setState(() => _message = 'No readable text found. Try again or type the brand.');
      } else {
        _query.text = q;
        await _runSearch();
      }
    } catch (_) {
      setState(() => _message = 'Could not read the photo. Try again or type the brand.');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _search.search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _message = 'No matches. Edit the text (brand + product name) and search again.';
      });
    } on LookupException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Find by front label')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _takePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Photograph the front of the pack'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              labelText: 'Brand and product name',
              helperText: 'Read from the photo. Edit if the text is wrong.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.search), onPressed: _busy ? null : _runSearch),
            ),
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          if (_results.isNotEmpty)
            Text('Tap the one that matches your pack',
                style: Theme.of(context).textTheme.labelLarge),
          for (final c in _results)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: c.imageUrl == null
                        ? const Icon(Icons.shopping_bag_outlined)
                        : Image.network(c.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.shopping_bag_outlined)),
                  ),
                ),
                title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([if (c.brand.isNotEmpty) c.brand, c.barcode].join(' · ')),
                onTap: () => Navigator.of(context).pop(c.barcode),
              ),
            ),
        ],
      ),
    );
  }
}