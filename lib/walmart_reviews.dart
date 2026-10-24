import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

class WalmartReviewsButton extends StatelessWidget {
  final Product product;

  const WalmartReviewsButton({
    super.key,
    required this.product,
  });

  Future<void> _openWalmart(BuildContext context) async {
    final query = '${product.brand} ${product.name} ${product.barcode}';

    final uri = Uri.https(
      'www.walmart.com',
      '/search',
      {'q': query.trim()},
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Walmart.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _openWalmart(context),
      icon: const Icon(Icons.rate_review_outlined),
      label: const Text('Find Walmart Reviews'),
    );
  }
}