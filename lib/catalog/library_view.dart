import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/theme.dart';
import '../playback/screen.dart';
import 'book_cover.dart';
import 'book_page.dart';
import 'layout.dart';
import 'library_services.dart';
import 'model.dart';
import 'shelf.dart';

/// The Library tab below its top bar: filters, then the grouped shelf.
class LibraryShelf extends StatefulWidget {
  const LibraryShelf({super.key, required this.services});
  final LibraryServices services;
  @override
  State<LibraryShelf> createState() => _LibraryShelfState();
}

class _LibraryShelfState extends State<LibraryShelf> {
  ShelfFilter _filter = ShelfFilter.all;

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final catalog = services.catalog;
    final items = shelf(catalog.books, _filter, services.editionDownloaded);
    return RefreshIndicator(
      onRefresh: catalog.busy ? () async {} : catalog.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Row(
                children: [
                  for (final (filter, label) in [
                    (ShelfFilter.all, 'All'),
                    (ShelfFilter.audio, 'Audio'),
                    (ShelfFilter.ebooks, 'Ebooks'),
                    (ShelfFilter.downloaded, 'Downloaded'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!catalog.verified && catalog.cache?.completedAt != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Saved library · ${catalog.cache!.completedAt!.toLocal().toString().split('.').first}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    catalog.accessBlocked
                        ? 'Choose available book libraries to continue.'
                        : _filter == ShelfFilter.downloaded
                        ? 'No downloaded books yet.'
                        : 'No books found.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            )
          else
            ShelfEntries(services: services, items: items),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// Library entries as a grid or a list, in the saved layout. A sliver.
class ShelfEntries extends StatelessWidget {
  const ShelfEntries({
    super.key,
    required this.services,
    required this.items,
    this.showSeriesPosition = false,
    this.forceList = false,
  });
  final LibraryServices services;
  final List<ShelfItem> items;

  /// Labels each book with its position, for example "BOOK 2".
  final bool showSeriesPosition;
  final bool forceList;

  @override
  Widget build(BuildContext context) {
    final compact = services.layout.density == LibraryDensity.compact;
    if (services.layout.view == LibraryView.grid && !forceList) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final spacing = compact ? 10.0 : 14.0;
            final columns =
                ((constraints.crossAxisExtent + spacing) /
                        ((compact ? 112 : 168) + spacing))
                    .floor()
                    .clamp(compact ? 3 : 2, 8);
            final width =
                (constraints.crossAxisExtent - spacing * (columns - 1)) /
                columns;
            final scale = MediaQuery.textScalerOf(context);
            // The cover, the room a series stack needs above it, and the text
            // below it: a position label, two title lines, the author line,
            // and the progress line.
            final text =
                scale.scale(compact ? 11 : 12) * 1.5 +
                scale.scale(compact ? 13 : 15) * 1.2 * 2 +
                scale.scale(compact ? 10.5 : 12) * 1.5 +
                (compact ? 6 : 8) +
                9;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: compact ? 14 : 20,
                crossAxisSpacing: spacing,
                mainAxisExtent: width * 1.5 + 6 + text,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _GridTile(
                  services: services,
                  item: items[index],
                  compact: compact,
                  showSeriesPosition: showSeriesPosition,
                ),
                childCount: items.length,
              ),
            );
          },
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _ListRow(
          services: services,
          item: items[index],
          compact: compact,
          showSeriesPosition: showSeriesPosition,
        ),
      ),
    );
  }
}

void _open(BuildContext context, LibraryServices services, ShelfItem item) =>
    switch (item) {
      ShelfBook(:final book) => openBook(context, services, book),
      ShelfSeries() => openSeries(context, services, item),
    };

Widget _cover(LibraryServices services, ShelfItem item, {bool small = false}) =>
    switch (item) {
      ShelfBook(:final book) => BookCover.book(
        book,
        downloaded: services.downloaded(book),
        showText: !small,
      ),
      ShelfSeries(:final books, :final name) => BookCover(
        title: name,
        author: books.first.author,
        cover: books.map((book) => book.cover).nonNulls.firstOrNull,
        stacked: true,
        label: small ? null : '${books.length} books',
        downloaded: books.every(services.downloaded),
        showText: !small,
      ),
    };

String? _position(Book book, bool show) => show && book.seriesOrder != null
    ? 'BOOK ${seriesPosition(book.seriesOrder!)}'
    : null;

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.services,
    required this.item,
    required this.compact,
    required this.showSeriesPosition,
  });
  final LibraryServices services;
  final ShelfItem item;
  final bool compact;
  final bool showSeriesPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, subtitle, progress, position) = switch (item) {
      ShelfBook(:final book) => (
        book.title,
        book.author,
        services.progress(book),
        _position(book, showSeriesPosition),
      ),
      ShelfSeries(:final name, :final books) => (
        name,
        [
          if (books.first.author.isNotEmpty) books.first.author,
          '${books.length} books',
        ].join(' · '),
        null,
        null,
      ),
    };
    return Semantics(
      button: true,
      label: item is ShelfSeries ? 'Series $title' : title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(context, services, item),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _cover(services, item, small: compact),
            ),
            SizedBox(height: compact ? 6 : 8),
            if (position != null) Text(position, style: _positionStyle(theme)),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Source Serif 4',
                fontSize: compact ? 13 : 15,
                height: 1.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (progress != null && progress.totalMs > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ProgressLine(
                  value: progress.elapsedMs / progress.totalMs,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.services,
    required this.item,
    required this.compact,
    required this.showSeriesPosition,
  });
  final LibraryServices services;
  final ShelfItem item;
  final bool compact;
  final bool showSeriesPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, author, detail, position) = switch (item) {
      ShelfBook(:final book) => (
        book.title,
        book.author,
        services.summary(book),
        _position(book, showSeriesPosition),
      ),
      ShelfSeries(:final name, :final books) => (
        name,
        books.first.author,
        [
          'Series · ${books.length} books',
          services.seriesSummary(item as ShelfSeries),
        ].where((part) => part.isNotEmpty).join(' · '),
        null,
      ),
    };
    return Semantics(
      button: true,
      label: item is ShelfSeries ? 'Series $title' : title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(context, services, item),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 42 : 56,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: item is ShelfSeries ? 5 : 0,
                    right: item is ShelfSeries ? 6 : 0,
                  ),
                  child: _cover(services, item, small: true),
                ),
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (position != null)
                      Text(position, style: _positionStyle(theme)),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Source Serif 4',
                        fontSize: compact ? 15 : 17,
                        height: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (author.isNotEmpty && position == null)
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _positionStyle(ThemeData theme) => TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
  color: theme.colorScheme.primary,
);

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1),
      minHeight: 3,
      backgroundColor: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// The top bar action that switches between grid and list.
class LayoutToggle extends StatelessWidget {
  const LayoutToggle({super.key, required this.layout});
  final LibraryLayout layout;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: layout,
    builder: (context, _) {
      final grid = layout.view == LibraryView.grid;
      return IconButton(
        tooltip: grid ? 'Show as list' : 'Show as grid',
        onPressed: () =>
            layout.view = grid ? LibraryView.list : LibraryView.grid,
        icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
      );
    },
  );
}

void openSearch(BuildContext context, LibraryServices services) => unawaited(
  Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => SearchPage(services: services)),
  ),
);

/// Search across every book. Results are single books, never series.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.services});
  final LibraryServices services;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.services.changes,
    builder: (context, _) {
      final results = search(widget.services.catalog.books, _query);
      return Scaffold(
        bottomNavigationBar: widget.services.playback == null
            ? null
            : PlaybackMiniPlayer(playback: widget.services.playback!),
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search books, authors, series',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(99),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(99),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
        body: BookfinSurface(
          child: Material(
            type: MaterialType.transparency,
            child: _query.trim().isEmpty
                ? const SizedBox.shrink()
                : results.isEmpty
                ? Center(
                    child: Text(
                      'No books match “${_query.trim()}”.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      ShelfEntries(
                        services: widget.services,
                        items: [for (final book in results) ShelfBook(book)],
                        forceList: true,
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

void openSeries(
  BuildContext context,
  LibraryServices services,
  ShelfSeries series,
) => unawaited(
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SeriesPage(services: services, name: series.name),
    ),
  ),
);

/// One series in reading order. It reads the current catalog, so it follows
/// refreshes and corrections while it is open.
class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.services, required this.name});
  final LibraryServices services;
  final String name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.changes,
    builder: (context, _) {
      final series = shelf(
        services.catalog.books,
        ShelfFilter.all,
        services.editionDownloaded,
      ).whereType<ShelfSeries>().where((item) => item.name == name).firstOrNull;
      final theme = Theme.of(context);
      return Scaffold(
        bottomNavigationBar: services.playback == null
            ? null
            : PlaybackMiniPlayer(playback: services.playback!),
        appBar: AppBar(actions: [LayoutToggle(layout: services.layout)]),
        body: BookfinSurface(
          child: Material(
            type: MaterialType.transparency,
            child: series == null
                ? const Center(
                    child: Text('This series is not in the current library.'),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 92,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    right: 7,
                                  ),
                                  child: _cover(services, series),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      series.name,
                                      style: TextStyle(
                                        fontFamily: 'Source Serif 4',
                                        fontSize: 26,
                                        height: 1.1,
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        if (series
                                            .books
                                            .first
                                            .author
                                            .isNotEmpty)
                                          series.books.first.author,
                                        '${series.books.length} books',
                                      ].join(' · '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    if (services
                                        .seriesSummary(series)
                                        .isNotEmpty)
                                      Text(
                                        services.seriesSummary(series),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ShelfEntries(
                        services: services,
                        items: [
                          for (final book in series.books) ShelfBook(book),
                        ],
                        showSeriesPosition: true,
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
