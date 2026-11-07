import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/theme.dart';
import 'cities.dart';
import 'preferences.dart';

class CitySearch extends StatefulWidget {
  const CitySearch({super.key, required this.appearance});

  final AppearanceController appearance;

  @override
  State<CitySearch> createState() => _CitySearchState();
}

class _CitySearchState extends State<CitySearch> {
  Future<CityCatalog>? _catalog;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= DefaultAssetBundle.of(context)
        .loadString('assets/cities/cities.tsv')
        .then(CityCatalog.parse);
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
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            FutureBuilder<CityCatalog>(
              future: _catalog,
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
                final matches = snapshot.data!.search(_query);
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
}
