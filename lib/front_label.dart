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

import 'models.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Candidate + search
// ─────────────────────────────────────────────────────────────────────────────

class Candidate {
  final String barcode, name, brand;
  final String? imageUrl;
  double score = 0;
  Candidate(this.barcode, this.name, this.brand, this.imageUrl);

  /// Brand + product name, e.g. "Cheetos Crunchy".
  String get display => withBrand(brand, name);
}

/// Open Food Facts answers HTTP 503 when an IP exceeds its limit
/// (10 searches per minute) or when the server is overloaded.
class RateLimitException extends LookupException {
  RateLimitException()
      : super('Open Food Facts is busy or limiting searches (10 per minute). '
            'Wait about a minute, then try again.');
}

class FrontLabelSearch {
  static const _headers = {'User-Agent': 'NutriCompare/1.0 (flutter app)'};

  /// Remembers results per query so repeating a search costs no request.
  static final Map<String, List<Candidate>> _cache = {};

  Future<List<Candidate>> search(String text) async {
    final cached = _cache[text];
    if (cached != null) return cached;
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
    if (res.statusCode == 503 || res.statusCode == 429) {
      throw RateLimitException();
    }
    if (res.statusCode != 200) {
      throw LookupException('Product database error (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (json['products'] as List?) ?? const [];
    String s(dynamic v) => (v as String?)?.trim() ?? '';
    return _cache[text] = [
      for (final p in list.cast<Map<String, dynamic>>())
        if (s(p['code']).isNotEmpty && s(p['product_name']).isNotEmpty)
          Candidate(s(p['code']), s(p['product_name']),
              s(p['brands']).split(',').first.trim(), p['image_front_small_url'] as String?),
    ];
  }

  /// Runs queries one at a time and merges the results by barcode. Stops as
  /// soon as there are [enough] candidates, and stops immediately when the
  /// server says it is limiting us, so one search uses as few requests as
  /// possible.
  Future<List<Candidate>> searchMany(List<String> queries, {int enough = 8}) async {
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
        if (merged.length >= enough) break;
      } on RateLimitException {
        if (merged.isNotEmpty) break; // show what we already have
        rethrow;
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

/// Letters a and b count as "the same" if equal or an OCR look-alike (0/o...).
bool _alike(String x, String y) => x == y || _confusablePairs.contains('$x$y');

/// Longest common subsequence: the most letters of [a] that appear in [b] in
/// the same order, even when other letters are mixed in between.
/// lcsLength('chocolate', 'chocolyate') == 9.
int lcsLength(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = _alike(a[i - 1], b[j - 1])
          ? prev[j - 1] + 1
          : math.max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

String _digitsToLetters(String s) {
  const map = {
    '0': 'o', '1': 'i', '2': 'z', '3': 'e', '4': 'a', '5': 's', '6': 'g', '8': 'b', '9': 'g',
  };
  return s.split('').map((c) => map[c] ?? c).join();
}

/// Share of two-letter groups the words have in common (Dice coefficient).
/// Used only as a guard against scattered, unrelated letter matches.
double _bigramDice(String a, String b) {
  if (a.length < 2 || b.length < 2) return 1;
  final counts = <String, int>{};
  for (var i = 0; i < a.length - 1; i++) {
    final g = a.substring(i, i + 2);
    counts[g] = (counts[g] ?? 0) + 1;
  }
  var shared = 0;
  for (var j = 0; j < b.length - 1; j++) {
    final g = b.substring(j, j + 2);
    final c = counts[g] ?? 0;
    if (c > 0) {
      shared++;
      counts[g] = c - 1;
    }
  }
  return 2 * shared / ((a.length - 1) + (b.length - 1));
}

/// 0..1 similarity between a (possibly jumbled) OCR word and a database word.
///
/// Letters found in the same order in both words (extra letters in between
/// are fine) are measured two ways and averaged:
///   - the share of the OCR word that matches the database word
///   - the share of the database word that matches the OCR word
/// "chocolyate" (OCR) vs "chocolate" (database): all 9 letters of "chocolate"
/// appear in order, so 9/10 of the OCR word and 9/9 of the database word
/// match, and the average is 95%.
/// OCR-aware edit distance covers swaps like "rn" for "m", and the better of
/// the two scores is used. If the words share almost no two-letter groups,
/// the match is likely scattered noise and the score is reduced.
double similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final common = lcsLength(a, b);
  final lcsScore = (common / a.length + common / b.length) / 2;
  final m = math.max(a.length, b.length);
  final edit = 1 - ocrDistance(a, b) / m;
  var s = math.max(lcsScore, edit).clamp(0.0, 1.0);
  if (_bigramDice(_digitsToLetters(a), _digitsToLetters(b)) < 0.2) s *= 0.7;
  return s;
}

double _sim(String a, String b) => similarity(a, b);

/// How well the OCR text matches "brand + name", tolerant of OCR mix-ups.
///
/// Averages two percentages, so only a real full match reaches 100%:
///   - how much of the OCR text is found in the database name
///   - how much of the database name is found in the OCR text
/// "chocolate" vs "Chocolate" is 100%, but "chocolate" vs "Hershey's
/// Chocolate Bar" is lower, because most of that name is not in the photo text.
double textScore(String ocr, Candidate c) {
  final ocrTokens = _norm(ocr).split(' ').where((t) => t.length >= 3).toList();
  var candTokens =
      _norm('${c.brand} ${c.name}').split(' ').where((t) => t.length >= 3).toList();
  if (candTokens.isEmpty) {
    candTokens =
        _norm('${c.brand} ${c.name}').split(' ').where((t) => t.isNotEmpty).toList();
  }
  if (ocrTokens.isEmpty || candTokens.isEmpty) return 0;

  // Average, over [from] words, of the best match found among [to] words.
  // Weak matches are mostly noise; don't let them add up.
  double coverage(List<String> from, List<String> to) {
    var sum = 0.0;
    for (final f in from) {
      var best = 0.0;
      for (final t in to) {
        best = math.max(best, _sim(f, t));
      }
      sum += best >= 0.6 ? best : 0;
    }
    return sum / from.length;
  }

  final tokenScore =
      (coverage(ocrTokens, candTokens) + coverage(candTokens, ocrTokens)) / 2;

  // Also compare the whole text with spaces removed, so words that OCR split
  // or glued together ("choco late", "cheetoscrunchy") still match. This is
  // already a two-way average (see similarity).
  final ocrAll = ocrTokens.join();
  final candAll = candTokens.join();
  final phraseScore = ocrAll.length >= 4 && candAll.length >= 4
      ? similarity(ocrAll, candAll)
      : 0.0;
  return math.max(tokenScore, phraseScore >= 0.6 ? phraseScore : 0);
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
  static const _maxQueries = 3; // Open Food Facts allows 10 searches/min

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
        title: Text(c.display, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (best) 'Best match',
          c.barcode,
        ].join(' · ')),
        trailing: Text('${(c.score * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => Navigator.of(context).pop(c.barcode),
      ),
    );
  }
}