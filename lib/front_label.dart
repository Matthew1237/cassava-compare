// Front-of-pack recognition for NutriCompare.
//
// Flow: photo of the front of the pack
//   -> on-device OCR reads brand/name text
//   -> Open Food Facts text search (full text, the biggest lines on their own,
//      and "repaired" variants where common OCR mix-ups are undone)
//   -> candidates are ranked by an OCR-aware similarity: letters that OCR
//      commonly confuses (0/o, 1/l/i, 5/s, rn/m, vv/w, ...) cost little to
//      substitute, so "D0RIT0S" is nearly an exact match for "Doritos"
//   -> best match is shown first; the user taps to confirm.
//
// Setup:
//   flutter pub add image_picker google_mlkit_text_recognition
//
// Integration in HomeScreen:
//
//   Future<void> _byFrontLabel() async {
//     final code = await Navigator.of(context).push<String>(MaterialPageRoute(
//         builder: (_) => FrontLabelScreen(service: _off)));
//     if (code != null) await _addBarcode(code);
//   }

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Candidate + search
// ─────────────────────────────────────────────────────────────────────────────

class Candidate {
  final String barcode, name, brand;
  final String? imageUrl;
  double score = 0;
  Candidate(this.barcode, this.name, this.brand, this.imageUrl);
}

class FrontLabelSearch {
  static const _headers = {'User-Agent': 'NutriCompare/1.0 (flutter app)'};

  Future<List<Candidate>> search(String text) async {
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': text,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '20',
      'fields': 'code,product_name,brands,image_front_small_url',
    });
    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
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

  /// Runs several queries and merges the results by barcode.
  Future<List<Candidate>> searchMany(List<String> queries) async {
    final merged = <String, Candidate>{};
    LookupException? lastError;
    var anySucceeded = false;
    for (final q in queries) {
      if (q.trim().isEmpty) continue;
      try {
        for (final c in await search(q)) {
          merged.putIfAbsent(c.barcode, () => c);
        }
        anySucceeded = true;
      } on LookupException catch (e) {
        lastError = e;
      }
    }
    if (!anySucceeded && lastError != null) throw lastError;
    return merged.values.toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OCR helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Up to 4 distinct text lines, largest print first (brand is usually biggest).
List<String> ocrLines(RecognizedText t) {
  final scored = <MapEntry<String, double>>[];
  for (final block in t.blocks) {
    for (final line in block.lines) {
      final clean = line.text
          .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ \-&\x27]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (clean.length >= 3 && RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(clean)) {
        scored.add(MapEntry(clean, line.boundingBox.height));
      }
    }
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  final out = <String>[];
  for (final e in scored) {
    if (!out.contains(e.key)) out.add(e.key);
    if (out.length == 4) break;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// OCR-aware text similarity
// ─────────────────────────────────────────────────────────────────────────────

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Characters OCR commonly mistakes for each other. Any two characters in the
/// same group are cheap to substitute.
const _confusionGroups = [
  'o0q', 'il1j', 's5', 'g96', 'z2', 'b68', 'ce', 'co', 'uv', 'nh', 'ft', 'a4', 'e3',
];

/// Multi-character mix-ups: (two letters, one letter) the OCR may swap.
const _multiConfusions = [
  ('rn', 'm'),
  ('vv', 'w'),
  ('cl', 'd'),
  ('ii', 'u'),
];

const _confusableCost = 0.3; // single-character look-alike
const _multiCost = 0.4; // rn <-> m style

final Set<String> _confusablePairs = () {
  final s = <String>{};
  for (final g in _confusionGroups) {
    for (var i = 0; i < g.length; i++) {
      for (var j = 0; j < g.length; j++) {
        if (i != j) s.add('${g[i]}${g[j]}');
      }
    }
  }
  return s;
}();

/// Edit distance where look-alike substitutions are cheap.
double ocrDistance(String a, String b) {
  if (a == b) return 0;
  final n = a.length, m = b.length;
  if (n == 0) return m.toDouble();
  if (m == 0) return n.toDouble();

  final d = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i.toDouble();
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j.toDouble();
  }

  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final ca = a[i - 1], cb = b[j - 1];
      final sub = ca == cb
          ? 0.0
          : (_confusablePairs.contains('$ca$cb') ? _confusableCost : 1.0);
      var best = math.min(
        d[i - 1][j - 1] + sub,
        math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
      );
      for (final (two, one) in _multiConfusions) {
        // a has the two letters, b has the single letter
        if (i >= 2 && a.substring(i - 2, i) == two && cb == one) {
          best = math.min(best, d[i - 2][j - 1] + _multiCost);
        }
        // a has the single letter, b has the two letters
        if (j >= 2 && ca == one && b.substring(j - 2, j) == two) {
          best = math.min(best, d[i - 1][j - 2] + _multiCost);
        }
      }
      d[i][j] = best;
    }
  }
  return d[n][m];
}

double _sim(String a, String b) {
  final m = math.max(a.length, b.length);
  return m == 0 ? 0 : (1 - ocrDistance(a, b) / m).clamp(0.0, 1.0);
}

/// How well the OCR text matches "brand + name", tolerant of OCR mix-ups.
double textScore(String ocr, Candidate c) {
  final ocrTokens = _norm(ocr).split(' ').where((t) => t.length >= 3).toList();
  final candTokens =
      _norm('${c.brand} ${c.name}').split(' ').where((t) => t.isNotEmpty).toList();
  if (ocrTokens.isEmpty || candTokens.isEmpty) return 0;
  var sum = 0.0;
  for (final o in ocrTokens) {
    var best = 0.0;
    for (final t in candTokens) {
      best = math.max(best, _sim(o, t));
    }
    // Weak token matches are mostly noise; don't let them add up.
    sum += best >= 0.6 ? best : 0;
  }
  return sum / ocrTokens.length;
}

/// Extra search phrases with common OCR mix-ups undone, so the database can
/// find the product even when the raw text contains no real word.
List<String> repairedQueries(String text) {
  const digitToLetter = {
    '0': 'o', '1': 'i', '5': 's', '8': 'b', '2': 'z', '4': 'a', '6': 'g', '9': 'g',
  };
  final lower = text.toLowerCase();

  // Digits inside a word that also has letters are almost certainly letters.
  final tokens = lower.split(' ').map((t) {
    final letters = RegExp(r'[a-z]').allMatches(t).length;
    final hasDigit = RegExp(r'[0-9]').hasMatch(t);
    if (letters >= 2 && hasDigit) {
      return t.split('').map((ch) => digitToLetter[ch] ?? ch).join();
    }
    return t;
  }).join(' ');

  final merged = lower.replaceAll('rn', 'm').replaceAll('vv', 'w');

  final out = <String>[];
  for (final v in [tokens, merged]) {
    if (v != lower && !out.contains(v)) out.add(v);
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class FrontLabelScreen extends StatefulWidget {
  final OpenFoodFactsService service;
  const FrontLabelScreen({super.key, required this.service});

  @override
  State<FrontLabelScreen> createState() => _FrontLabelScreenState();
}

class _FrontLabelScreenState extends State<FrontLabelScreen> {
  static const _maxQueries = 5; // Open Food Facts rate-limits search

  final _search = FrontLabelSearch();
  final _query = TextEditingController();
  List<Candidate> _results = [];
  bool _busy = false;
  String? _message;

  List<String> _lines = []; // OCR lines, biggest first
  String _autoQuery = ''; // text generated from OCR (to detect user edits)

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
      _results = [];
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(shot.path));
      _lines = ocrLines(text);
      _autoQuery = _lines.take(3).join(' ');
      if (_autoQuery.isEmpty) {
        setState(() => _message = 'No readable text found. Try again or type the brand.');
      } else {
        _query.text = _autoQuery;
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
      // Full text, the biggest lines on their own (usually the brand), and
      // versions with OCR mix-ups repaired. If the user edited the text,
      // trust their edit and only add its repaired forms.
      final queries = <String>[q];
      if (q == _autoQuery) queries.addAll(_lines.take(2));
      queries.addAll(repairedQueries(q));
      final unique = queries.toSet().take(_maxQueries).toList();

      final found = await _search.searchMany(unique);
      for (final c in found) {
        c.score = textScore(q, c);
      }
      found.sort((a, b) => b.score.compareTo(a.score));

      if (!mounted) return;
      setState(() {
        _results = found;
        if (found.isEmpty) {
          _message = 'No matches. Edit the text (brand + product name) and search again.';
        }
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
          const SizedBox(height: 6),
          Text(
            'Get close, keep the brand name sharp, and avoid glare.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
          if (_busy)
            const Padding(
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
            Text('Best matches first. Tap the one that matches your pack.',
                style: Theme.of(context).textTheme.labelLarge),
          for (var i = 0; i < _results.length; i++) _tile(context, _results[i], i == 0),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Candidate c, bool best) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: best ? cs.primaryContainer.withValues(alpha: 0.5) : null,
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
                    errorBuilder: (_, _, _) => const Icon(Icons.shopping_bag_outlined)),
          ),
        ),
        title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (best) 'Best match',
          if (c.brand.isNotEmpty) c.brand,
          c.barcode,
        ].join(' · ')),
        trailing: Text('${(c.score * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => Navigator.of(context).pop(c.barcode),
      ),
    );
  }
}