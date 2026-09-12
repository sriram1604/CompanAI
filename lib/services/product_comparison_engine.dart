import 'dart:async';
import 'dart:developer' as developer;
import 'package:url_launcher/url_launcher.dart';
import 'app_launcher_service.dart';
import 'screen_automation_service.dart';

class ProductItem {
  final String site;
  final String title;
  final double? price;
  final String rawPrice;
  final String? rating;
  final String? availability;

  ProductItem({
    required this.site,
    required this.title,
    this.price,
    required this.rawPrice,
    this.rating,
    this.availability,
  });

  Map<String, dynamic> toJson() => {
        'site': site,
        'title': title,
        'price': price,
        'rawPrice': rawPrice,
        'rating': rating,
        'availability': availability,
      };
}

class ProductComparisonState {
  final String query;
  final String country;
  final List<String> sites;
  int currentSiteIndex;
  final List<String> completedSites;
  final List<ProductItem> results;
  bool isCompleted;

  ProductComparisonState({
    required this.query,
    this.country = 'India',
    required this.sites,
    this.currentSiteIndex = 0,
    List<String>? completedSites,
    List<ProductItem>? results,
    this.isCompleted = false,
  })  : completedSites = completedSites ?? [],
        results = results ?? [];

  String? get currentSite {
    if (currentSiteIndex >= 0 && currentSiteIndex < sites.length) {
      return sites[currentSiteIndex];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'task': 'compare_products',
        'query': query,
        'country': country,
        'sites': sites,
        'current_site': currentSite,
        'completed_sites': completedSites,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

/// Orchestrates multi-site product searches and extracts VISIBLE pricing without hallucinating.
class ProductComparisonEngine {
  static final ProductComparisonEngine _instance = ProductComparisonEngine._internal();
  factory ProductComparisonEngine() => _instance;
  ProductComparisonEngine._internal();

  final AppLauncherService _apps = AppLauncherService();
  final ScreenAutomationService _screen = ScreenAutomationService();

  /// Execute a multi-site product search and comparison
  Future<String> searchAndCompareProducts({
    required String query,
    List<String>? targetSites,
    void Function(String progress)? onProgress,
  }) async {
    final sites = targetSites ?? _extractSites(query);
    final cleanQuery = _extractProductQuery(query);

    final state = ProductComparisonState(
      query: cleanQuery,
      sites: sites.isNotEmpty ? sites : ['amazon', 'flipkart', 'meesho'],
    );

    onProgress?.call('Starting product research for "$cleanQuery" across ${state.sites.join(", ")}...');

    for (int i = 0; i < state.sites.length; i++) {
      final site = state.sites[i];
      state.currentSiteIndex = i;
      onProgress?.call('Searching $site for "$cleanQuery"...');

      final items = await _searchSingleSite(site, cleanQuery);
      if (items.isNotEmpty) {
        state.results.addAll(items);
      }
      state.completedSites.add(site);
    }

    state.isCompleted = true;
    return _generateComparisonReport(state);
  }

  Future<List<ProductItem>> _searchSingleSite(String site, String query) async {
    final siteLower = site.toLowerCase();
    String searchUrl = '';

    if (siteLower.contains('amazon')) {
      searchUrl = 'https://www.amazon.in/s?k=${Uri.encodeComponent(query)}';
    } else if (siteLower.contains('flipkart')) {
      searchUrl = 'https://www.flipkart.com/search?q=${Uri.encodeComponent(query)}';
    } else if (siteLower.contains('meesho')) {
      searchUrl = 'https://www.meesho.com/search?q=${Uri.encodeComponent(query)}';
    } else {
      searchUrl = 'https://www.google.com/search?q=${Uri.encodeComponent("$query $site")}';
    }

    try {
      final uri = Uri.parse(searchUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await _apps.openUrl(searchUrl);
      }

      // Wait for page/app to render visible product elements
      await Future.delayed(const Duration(milliseconds: 3500));

      // Observe visible screen elements
      final nodes = await _screen.dumpScreen();
      return _extractVisibleProducts(site, query, nodes);
    } catch (e) {
      developer.log('Error scraping $site: $e', name: 'ProductComparisonEngine');
      return [];
    }
  }

  List<ProductItem> _extractVisibleProducts(String site, String query, List<Map<String, dynamic>> nodes) {
    final results = <ProductItem>[];
    String? currentTitle;
    double? currentPrice;
    String? currentRawPrice;
    String? currentRating;

    for (final node in nodes) {
      final text = (node['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;

      // Check for price pattern (e.g. ₹18,990, ₹1,299, Rs. 14,999, ₹499)
      final priceMatch = RegExp(r'(?:₹|Rs\.?|INR)\s*([\d,]+(?:\.\d{2})?)', caseSensitive: false).firstMatch(text);
      if (priceMatch != null) {
        final rawNum = priceMatch.group(1)!.replaceAll(',', '');
        final parsed = double.tryParse(rawNum);
        if (parsed != null && parsed > 50) { // filter trivial values
          currentPrice = parsed;
          currentRawPrice = '₹${priceMatch.group(1)}';
        }
      }

      // Check for rating pattern (e.g. 4.5 ★, 4.2 out of 5, 4.3)
      final ratingMatch = RegExp(r'(\d\.\d)\s*(?:★|stars?|out of 5)?', caseSensitive: false).firstMatch(text);
      if (ratingMatch != null && currentRating == null) {
        final val = double.tryParse(ratingMatch.group(1)!);
        if (val != null && val >= 1.0 && val <= 5.0) {
          currentRating = '${ratingMatch.group(1)}★';
        }
      }

      // Check for product title matching keywords
      final lowerText = text.toLowerCase();
      final keywords = query.toLowerCase().split(RegExp(r'\s+')).where((k) => k.length > 2);
      if (keywords.any((k) => lowerText.contains(k)) && !lowerText.startsWith('₹') && text.length > 8) {
        if (currentTitle == null || currentTitle.length < 15) {
          currentTitle = text;
        }
      }

      // Aggregate when we have title and price
      if (currentTitle != null && currentPrice != null) {
        results.add(ProductItem(
          site: site[0].toUpperCase() + site.substring(1),
          title: currentTitle.length > 60 ? '${currentTitle.substring(0, 60)}...' : currentTitle,
          price: currentPrice,
          rawPrice: currentRawPrice ?? '₹${currentPrice.toInt()}',
          rating: currentRating ?? 'N/A',
          availability: 'Visible in stock',
        ));

        currentTitle = null;
        currentPrice = null;
        currentRawPrice = null;
        currentRating = null;

        if (results.length >= 2) break; // Take top 2 visible results per platform
      }
    }

    // If no specific card parsed but price was seen
    if (results.isEmpty && currentPrice != null) {
      results.add(ProductItem(
        site: site[0].toUpperCase() + site.substring(1),
        title: query,
        price: currentPrice,
        rawPrice: currentRawPrice ?? '₹${currentPrice.toInt()}',
        rating: currentRating ?? 'N/A',
      ));
    }

    return results;
  }

  String _generateComparisonReport(ProductComparisonState state) {
    if (state.results.isEmpty) {
      return '🔎 Searched ${state.sites.join(", ")} for "${state.query}".\n\n'
          '⚠️ Could not extract clear visible prices from the rendered pages. Please inspect the open browser tabs.';
    }

    final buffer = StringBuffer();
    buffer.writeln('📊 **Product Price Comparison for "${state.query}"**\n');

    // Sort by price ascending to find cheapest
    final sorted = List<ProductItem>.from(state.results)
      ..sort((a, b) => (a.price ?? 999999).compareTo(b.price ?? 999999));

    final cheapest = sorted.firstWhere((p) => p.price != null, orElse: () => sorted.first);

    buffer.writeln('🏆 **Cheapest Option**: ${cheapest.site} at **${cheapest.rawPrice}**\n');
    buffer.writeln('| Platform | Product | Price | Rating |');
    buffer.writeln('| :--- | :--- | :--- | :--- |');

    for (final item in state.results) {
      buffer.writeln('| ${item.site} | ${item.title} | **${item.rawPrice}** | ${item.rating ?? "N/A"} |');
    }

    buffer.writeln('\n*Prices extracted live from visible on-screen listings.*');
    return buffer.toString();
  }

  List<String> _extractSites(String prompt) {
    final lower = prompt.toLowerCase();
    final sites = <String>[];
    if (lower.contains('amazon')) sites.add('amazon');
    if (lower.contains('flipkart')) sites.add('flipkart');
    if (lower.contains('meesho')) sites.add('meesho');
    return sites;
  }

  String _extractProductQuery(String prompt) {
    var clean = prompt;
    clean = clean.replaceAll(RegExp(r'^(?:search|find|compare|look for|check)\s+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+prices?\s+in\s+india', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+on\s+(?:amazon|flipkart|meesho|google|web|and|\s+|,)+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+and\s+tell\s+me\s+the\s+cheapest\s+.*$', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+and\s+compare\s+.*$', caseSensitive: false), '');
    return clean.trim();
  }
}
