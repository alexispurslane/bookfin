import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/theme.dart';
import 'appearance.dart';
import 'cities.dart';
import 'preferences.dart';

class CitySearch extends StatefulWidget {
  const CitySearch({
    super.key,
    required this.appearance,
    this.start = CityFinder.start,
  });

  final AppearanceController appearance;

  /// Starts the finder that answers this page's searches, from the text of
  /// the bundled city list.
  final Future<CityFinder> Function(String source) start;

  @override
  State<CitySearch> createState() => _CitySearchState();
}

/// The search page, which owns its finder and shows the answer to the
/// latest query.
class _CitySearchState extends State<CitySearch> {
  Future<CityFinder>? _finder;

  /// The number of the latest query, so that an answer to an older one is
  /// dropped.
  int _asked = 0;

  /// The query whose answer the page shows, and that answer.
  String _query = '';
  List<SelectedLocation> _matches = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finder ??= DefaultAssetBundle.of(context)
        .loadString('assets/cities/cities.tsv')
        .then(widget.start);
  }

  @override
  void dispose() {
    _finder?.then((finder) => finder.close(), onError: (Object _) {});
    super.dispose();
  }

  Future<void> _search(String query) async {
    final asked = ++_asked;
    final List<SelectedLocation> matches;
    try {
      matches = await (await _finder!).search(query);
    } on FormatException {
      // The page already shows that the city list could not be read.
      return;
    }
    if (!mounted || asked != _asked) return;
    setState(() {
      _query = query;
      _matches = matches;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose city')),
    body: SafeArea(
      child: BookfinSurface(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                decoration: const InputDecoration(
                  labelText: 'Search cities',
                  hintText: 'City, region or country',
                  prefixIcon: Icon(Icons.search),
                  counterText: '',
                ),
                onChanged: _search,
              ),
            ),
            FutureBuilder<CityFinder>(
              future: _finder,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'City data could not be read. Your appearance choice is unchanged. Use system appearance or a manual choice.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return KeyedSubtree(
                  // The key names the query that the shown answer is for.
                  key: ValueKey(('city results', _query)),
                  child: _answer(),
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text(
                'Offline city search · GeoNames · CC BY 4.0\nCities over 15,000 people and capitals; coverage varies. No device location or network lookup.',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// The answer to [_query]: its matches, or a hint when it has none.
  Widget _answer() {
    final matches = _matches;
    if (matches.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          _query.trim().isEmpty
              ? 'Enter a city name. You can add a region or country.'
              : 'No matching city. Try a nearby larger city.',
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: matches.length + 1,
      itemBuilder: (context, index) {
        if (index == matches.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Up to 30 matches. Add a region or country to narrow your search.',
            ),
          );
        }
        final city = matches[index];
        return Material(
          type: MaterialType.transparency,
          child: ListTile(
            title: Text(city.name),
            onTap: () {
              unawaited(widget.appearance.selectLocation(city));
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }
}
