// Search for a product by name in Open Food Facts.
//
// Flow: the user types a brand and/or product name
//   -> Open Food Facts text search
//   -> if the full text finds too little (for example because of a typo in one
//      word), variants that leave out one word are tried as well
//   -> results are ranked by how closely they match what was typed
//   -> the user taps a result and its barcode is returned to the caller.
//
// Integration in HomeScreen:
//
//   Future<void> _bySearch() async {
//     final code = await Navigator.of(context).push<String>(
//         MaterialPageRoute(builder: (_) => const ProductSearchScreen()));
//     if (code != null) await _addBarcode(code);
//   }

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

class ProductSearch {
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
      // Only return products whose main product language is English.
      // We request `lang` so we can enforce the condition locally.
      'fields': 'code,product_name,brands,image_front_small_url,lang',
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
        if (s(p['code']).isNotEmpty &&
            s(p['product_name']).isNotEmpty &&
            s(p['lang']).toLowerCase() == 'en')
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
// Ranking: how closely a result matches what was typed
// ─────────────────────────────────────────────────────────────────────────────

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Standard edit distance (insert, delete, replace = 1 each).
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      cur[j] = math.min(sub, math.min(prev[j] + 1, cur[j - 1] + 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Longest common subsequence: the most letters of [a] that appear in [b] in
/// the same order, even when other letters are mixed in between.
int _lcsLength(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : math.max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Share of two-letter groups two words have in common (Dice coefficient).
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

/// 0..1 similarity between two words. Takes the better of:
///   - the shared in-order letters, as a share of both words (averaged)
///   - 1 minus the edit distance as a share of the longer word
/// and reduces the score when the words share almost no letter pairs.
double similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final common = _lcsLength(a, b);
  final lcsScore = (common / a.length + common / b.length) / 2;
  final edit = 1 - _editDistance(a, b) / math.max(a.length, b.length);
  var s = math.max(lcsScore, edit).clamp(0.0, 1.0);
  if (_bigramDice(a, b) < 0.2) s *= 0.7;
  return s;
}

/// How well the typed text matches "brand + name". Averages two directions so
/// only a real full match reaches 100%:
///   - how much of the typed text is found in the product name
///   - how much of the product name is found in the typed text
double textScore(String typed, Candidate c) {
  final typedTokens = _norm(typed).split(' ').where((t) => t.length >= 3).toList();
  var candTokens =
      _norm('${c.brand} ${c.name}').split(' ').where((t) => t.length >= 3).toList();
  if (candTokens.isEmpty) {
    candTokens =
        _norm('${c.brand} ${c.name}').split(' ').where((t) => t.isNotEmpty).toList();
  }
  if (typedTokens.isEmpty || candTokens.isEmpty) return 0;

  // Average, over [from] words, of the best match found among [to] words.
  // Weak matches are mostly noise, so they count as 0.
  double coverage(List<String> from, List<String> to) {
    var sum = 0.0;
    for (final f in from) {
      var best = 0.0;
      for (final t in to) {
        best = math.max(best, similarity(f, t));
      }
      sum += best >= 0.6 ? best : 0;
    }
    return sum / from.length;
  }

  final tokenScore =
      (coverage(typedTokens, candTokens) + coverage(candTokens, typedTokens)) / 2;

  // Also compare the whole text with spaces removed, so "cheetoscrunchy"
  // still matches "Cheetos Crunchy".
  final typedAll = typedTokens.join();
  final candAll = candTokens.join();
  final phraseScore = typedAll.length >= 4 && candAll.length >= 4
      ? similarity(typedAll, candAll)
      : 0.0;
  return math.max(tokenScore, phraseScore >= 0.6 ? phraseScore : 0);
}

/// Each variant leaves out one word, so one misspelled word
/// doesn't make the whole search come back empty.
/// "chocolate cheny chip" -> "cheny chip", "chocolate chip", "chocolate cheny".
List<String> dropOneQueries(String text) {
  final words = text.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.length < 2 || words.length > 5) return [];
  return [
    for (var i = 0; i < words.length; i++)
      (List.of(words)..removeAt(i)).join(' '),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  // Open Food Facts allows 10 searches/min. searchMany stops early once it has
  // enough candidates, so the extra queries only run when earlier ones fall short.
  static const _maxQueries = 4;

  final _search = ProductSearch();
  final _query = TextEditingController();
  List<Candidate> _results = [];
  bool _busy = false;
  bool _searched = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final queries = <String>[q, ...dropOneQueries(q)];
      final unique = queries.toSet().take(_maxQueries).toList();

      final found = await _search.searchMany(unique);
      for (final c in found) {
        c.score = textScore(q, c);
      }
      found.sort((a, b) => b.score.compareTo(a.score));

      if (!mounted) return;
      setState(() {
        _results = found;
        _searched = true;
        if (found.isEmpty) {
          _message = 'No matches. Try the brand and product name, or fewer words.';
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Search for a product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              labelText: 'Brand and product name',
              hintText: 'e.g. Quaker chewy chocolate chip',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: _busy ? null : _runSearch,
              ),
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
          if (!_searched && _message == null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Include the brand for the best results. Searches are limited to '
                'about 10 per minute.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 12),
          if (_results.isNotEmpty)
            Text('Best matches first. Tap the one you want.', style: tt.labelLarge),
          for (final c in _results) _tile(context, c),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Candidate c) {
    return Card(
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
                    errorBuilder: (_, _, _) => const Icon(Icons.shopping_bag_outlined)),
          ),
        ),
        title: Text(c.display, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(c.barcode),
        onTap: () => Navigator.of(context).pop(c.barcode),
      ),
    );
  }
}