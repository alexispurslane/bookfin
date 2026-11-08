import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../foundation/listenable_selector.dart';
import '../foundation/theme.dart';
import 'book_cover.dart';
import 'book_page.dart';
import 'layout.dart';
import 'library_services.dart';
import 'model.dart';
import 'controller.dart';
import 'screen.dart' show LibrarySelector, TabFrame, TabPage;
import 'shelf.dart';

/// The Library tab below its top bar: filters, then the grouped shelf. A tap
/// on an entry goes to [onOpen].
class LibraryShelf extends StatefulWidget {
  const LibraryShelf({super.key, required this.services, required this.onOpen});
  final LibraryServices services;
  final ValueChanged<ShelfItem> onOpen;
  @override
  State<LibraryShelf> createState() => _LibraryShelfState();
}

class _LibraryShelfState extends State<LibraryShelf> {
  ShelfFilter _filter = ShelfFilter.all;

  /// The shelf follows the catalog's library, and whether Jellyfin can be
  /// reached. While it cannot, the shelf shows only downloaded books, and
  /// the chosen filter stays for the next refresh that reaches Jellyfin.
  /// Download state changes the shelf only through the downloaded books,
  /// and only when a download starts, finishes or goes away, because
  /// [CatalogLibrary.shelf] keeps the same list otherwise. Each entry follows
  /// its own book.
  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final catalog = services.catalog;
    return ValueListenableBuilder(
      valueListenable: catalog.libraryNotifier,
      builder: (context, library, _) => ListenableSelector(
        listenable: catalog.statusNotifier,
        select: () =>
            catalog.statusNotifier.value.reach == CatalogReach.unreachable,
        builder: (context, offline, _) {
          final filter = offline ? ShelfFilter.downloaded : _filter;
          return ListenableSelector(
            listenable: Listenable.merge([
              if (filter == ShelfFilter.downloaded) ?services.downloads?.phases,
            ]),
            select: () => library.shelf(filter, services.editionDownloaded),
            builder: (context, items, _) => _build(context, items, filter),
          );
        },
      ),
    );
  }

  Widget _build(
    BuildContext context,
    List<ShelfItem> items,
    ShelfFilter shown,
  ) {
    final services = widget.services;
    final catalog = services.catalog;
    return RefreshIndicator(
      // A pull during a refresh joins it and asks for its outcome.
      onRefresh: () => catalog.refresh(byUser: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: ShelfFilterChips(
              selected: _filter,
              onChanged: (filter) => setState(() => _filter = filter),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    catalog.accountNotifier.value.accessBlocked
                        ? 'Choose available book libraries to continue.'
                        : shown == ShelfFilter.downloaded
                        ? 'No downloaded books yet.'
                        : 'No books found.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            )
          else
            ShelfEntries(
              services: services,
              items: items,
              onOpen: widget.onOpen,
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + floatingBarInset(context)),
          ),
        ],
      ),
    );
  }
}

/// The row of shelf filters, which scrolls sideways when it does not fit. It
/// marks [selected], and reports a tap through [onChanged]. Its owner keeps
/// the choice.
class ShelfFilterChips extends StatelessWidget {
  const ShelfFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  /// The filter that the person chose. While Jellyfin cannot be reached, the
  /// shelf shows downloaded books, but this stays the chosen filter.
  final ShelfFilter selected;

  /// Reports the filter of a tapped chip.
  final ValueChanged<ShelfFilter> onChanged;

  /// The space around the row, inside its sideways scroll.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
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
              selected: selected == filter,
              onSelected: (_) => onChanged(filter),
            ),
          ),
      ],
    ),
  );
}

/// Library entries as a grid or a list, in the saved layout. A sliver. A tap
/// on an entry goes to [onOpen]. Each entry follows only its own books.
class ShelfEntries extends StatelessWidget {
  const ShelfEntries({
    super.key,
    required this.services,
    required this.items,
    required this.onOpen,
    this.showSeriesPosition = false,
    this.forceList = false,
  });
  final LibraryServices services;
  final List<ShelfItem> items;
  final ValueChanged<ShelfItem> onOpen;

  /// Labels each book with its position, for example "BOOK 2".
  final bool showSeriesPosition;
  final bool forceList;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: services.shelfLayout,
    builder: (context, layout, _) => _build(context, layout),
  );

  Widget _build(BuildContext context, ShelfLayout layout) {
    final compact = layout.density == LibraryDensity.compact;
    if (layout.view == LibraryView.grid && !forceList) {
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
            final rows = (items.length / columns).ceil();
            // Rows rather than a fixed-extent grid: each row is as tall as
            // its tallest tile, so short titles leave no empty band.
            return SliverList.separated(
              itemCount: rows,
              separatorBuilder: (_, _) => SizedBox(height: compact ? 14 : 20),
              itemBuilder: (context, row) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) SizedBox(width: spacing),
                    Expanded(
                      child: row * columns + column < items.length
                          ? _GridTile(
                              services: services,
                              item: items[row * columns + column],
                              onOpen: onOpen,
                              compact: compact,
                              showSeriesPosition: showSeriesPosition,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
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
          onOpen: onOpen,
          compact: compact,
          showSeriesPosition: showSeriesPosition,
        ),
      ),
    );
  }
}

/// Changes when what the library shows of [item] can change: the download
/// state and listening progress of its book, or of each book of its series.
Listenable _activity(LibraryServices services, ShelfItem item) =>
    switch (item) {
      ShelfBook(:final book) => services.bookActivity(book),
      ShelfSeries(:final books) => Listenable.merge([
        for (final book in books) services.bookActivity(book),
      ]),
    };

/// Whether the entry's book, or every book of its series, is downloaded.
bool _downloaded(LibraryServices services, ShelfItem item) => switch (item) {
  ShelfBook(:final book) => services.downloaded(book),
  ShelfSeries(:final books) => books.every(services.downloaded),
};

Widget _cover(ShelfItem item, {required bool downloaded, bool small = false}) =>
    switch (item) {
      ShelfBook(:final book) => BookCover.book(
        book,
        downloaded: downloaded,
        showText: !small,
      ),
      ShelfSeries(:final books, :final name) => BookCover(
        title: name,
        author: books.first.author,
        cover: books.map((book) => book.cover).nonNulls.firstOrNull,
        stacked: true,
        label: small ? null : '${books.length} books',
        downloaded: downloaded,
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
    required this.onOpen,
    required this.compact,
    required this.showSeriesPosition,
  });
  final LibraryServices services;
  final ShelfItem item;
  final ValueChanged<ShelfItem> onOpen;
  final bool compact;
  final bool showSeriesPosition;

  /// A tile follows only its own book or series, and rebuilds for download
  /// state and listening progress only when what it shows of them changes.
  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: _activity(services, item),
    select: () => (
      downloaded: _downloaded(services, item),
      progress: switch (item) {
        ShelfBook(:final book) => services.progress(book),
        ShelfSeries() => null,
      },
    ),
    builder: (context, shown, _) =>
        _build(context, shown.downloaded, shown.progress),
  );

  Widget _build(
    BuildContext context,
    bool downloaded,
    ({int elapsedMs, int totalMs})? progress,
  ) {
    final theme = Theme.of(context);
    final (title, subtitle, position) = switch (item) {
      ShelfBook(:final book) => (
        book.title,
        book.author,
        _position(book, showSeriesPosition),
      ),
      ShelfSeries(:final name, :final books) => (
        name,
        [
          if (books.first.author.isNotEmpty) books.first.author,
          '${books.length} books',
        ].join(' · '),
        null,
      ),
    };
    return Semantics(
      button: true,
      label: item is ShelfSeries ? 'Series $title' : title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onOpen(item),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _cover(item, downloaded: downloaded, small: compact),
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
                child: ProgressLine(
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
    required this.onOpen,
    required this.compact,
    required this.showSeriesPosition,
  });
  final LibraryServices services;
  final ShelfItem item;
  final ValueChanged<ShelfItem> onOpen;
  final bool compact;
  final bool showSeriesPosition;

  /// A row follows only its own book or series, and rebuilds for download
  /// state and listening progress only when what it shows of them changes.
  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: _activity(services, item),
    select: () => (
      downloaded: _downloaded(services, item),
      detail: switch (item) {
        ShelfBook(:final book) => services.summary(book),
        ShelfSeries(:final books) => [
          'Series · ${books.length} books',
          services.seriesSummary(item as ShelfSeries),
        ].where((part) => part.isNotEmpty).join(' · '),
      },
    ),
    builder: (context, shown, _) =>
        _build(context, shown.downloaded, shown.detail),
  );

  Widget _build(BuildContext context, bool downloaded, String detail) {
    final (title, author, position) = switch (item) {
      ShelfBook(:final book) => (
        book.title,
        book.author,
        _position(book, showSeriesPosition),
      ),
      ShelfSeries(:final name, :final books) => (
        name,
        books.first.author,
        null,
      ),
    };
    return BookRow(
      cover: _cover(item, downloaded: downloaded, small: true),
      stacked: item is ShelfSeries,
      title: title,
      author: author,
      position: position,
      detail: detail,
      compact: compact,
      semanticLabel: item is ShelfSeries ? 'Series $title' : title,
      onTap: () => onOpen(item),
    );
  }
}

/// One library entry as a list row: a small cover, the title, the author, and
/// a detail line. A screen can add a widget below the text, such as a
/// progress bar, and controls at the end of the row. Tapping the cover or the
/// text runs [onTap]. The end controls stay separate from that tap.
class BookRow extends StatelessWidget {
  const BookRow({
    super.key,
    required this.cover,
    required this.title,
    required this.onTap,
    this.author = '',
    this.position,
    this.detail = '',
    this.below,
    this.trailing,
    this.stacked = false,
    this.compact = false,
    this.semanticLabel,
  });
  final Widget cover;
  final String title;
  final VoidCallback onTap;
  final String author;

  /// A label above the title, for example "BOOK 2". It replaces the author.
  final String? position;
  final String detail;
  final Widget? below;
  final Widget? trailing;

  /// Leaves room above and right of the cover for a series stack.
  final bool stacked;
  final bool compact;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: semanticLabel ?? title,
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: compact ? 42 : 56,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: stacked ? 5 : 0,
                          right: stacked ? 6 : 0,
                        ),
                        child: cover,
                      ),
                    ),
                    SizedBox(width: compact ? 12 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (position != null)
                            Text(position!, style: _positionStyle(theme)),
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          if (below != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: below,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

TextStyle _positionStyle(ThemeData theme) => TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
  color: theme.colorScheme.primary,
);

/// The top bar action that switches between grid and list. It reports the
/// chosen view to [onChanged].
class LayoutToggle extends StatelessWidget {
  const LayoutToggle({
    super.key,
    required this.layout,
    required this.onChanged,
  });
  final ValueListenable<ShelfLayout> layout;
  final ValueChanged<LibraryView> onChanged;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: layout,
    builder: (context, shown, _) {
      final grid = shown.view == LibraryView.grid;
      return IconButton(
        tooltip: grid ? 'Show as list' : 'Show as grid',
        onPressed: () => onChanged(grid ? LibraryView.list : LibraryView.grid),
        icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
      );
    },
  );
}

/// Opens the page of [item]: a book's page or a series page. Only the page
/// controllers call this: [LibraryTab], [SearchPage] and [SeriesPage].
void _open(BuildContext context, LibraryServices services, ShelfItem item) =>
    switch (item) {
      ShelfBook(:final book) => openBook(context, services, book),
      ShelfSeries() => openSeries(context, services, item),
    };

/// The layout toggle of a page, which saves the view that it reports.
Widget _layoutToggle(LibraryServices services) => LayoutToggle(
  layout: services.shelfLayout,
  onChanged: (view) => services.layout.view = view,
);

void openSearch(BuildContext context, LibraryServices services) => unawaited(
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => services.coverScope(SearchPage(services: services)),
    ),
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
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The page frame stays as it is while the user types. The results follow
  /// the query and the catalog's library, and come from the library's search
  /// of the current query, so a result never belongs to an older query. Each
  /// row follows its own book.
  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final library = services.catalog.libraryNotifier;
    return services.page(
      context,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _query,
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
          ),
        ),
      ),
      body: ListenableSelector(
        listenable: Listenable.merge([_query, library]),
        select: () => (library: library.value, query: _query.text.trim()),
        builder: (context, shown, _) {
          if (shown.query.isEmpty) return const SizedBox.shrink();
          final results = shown.library.search(shown.query);
          if (results.isEmpty) {
            return Center(
              child: Text(
                'No books match “${shown.query}”.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              ShelfEntries(
                services: services,
                items: [for (final book in results) ShelfBook(book)],
                onOpen: (item) => _open(context, services, item),
                forceList: true,
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: floatingBarInset(context)),
              ),
            ],
          );
        },
      ),
    );
  }
}

void openSeries(
  BuildContext context,
  LibraryServices services,
  ShelfSeries series,
) => unawaited(
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => services.coverScope(
        SeriesPage(services: services, name: series.name),
      ),
    ),
  ),
);

/// One series in reading order. It reads the catalog's current library, so
/// it follows refreshes and corrections while it is open.
class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.services, required this.name});
  final LibraryServices services;
  final String name;

  /// The series follows the catalog's library. Its summary follows the
  /// download state and listening progress of its books, and each book
  /// follows its own.
  @override
  Widget build(BuildContext context) => services.page(
    context,
    appBar: AppBar(actions: [_layoutToggle(services)]),
    body: ValueListenableBuilder(
      valueListenable: services.catalog.libraryNotifier,
      builder: (context, library, _) {
        final series = library.series(name);
        if (series == null) {
          return const Center(
            child: Text('This series is not in the current library.'),
          );
        }
        final theme = Theme.of(context);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ListenableSelector(
                listenable: _activity(services, series),
                select: () => (
                  downloaded: _downloaded(services, series),
                  summary: services.seriesSummary(series),
                ),
                builder: (context, shown, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, right: 7),
                          child: _cover(series, downloaded: shown.downloaded),
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
                                if (series.books.first.author.isNotEmpty)
                                  series.books.first.author,
                                '${series.books.length} books',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                            if (shown.summary.isNotEmpty)
                              Text(
                                shown.summary,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ShelfEntries(
              services: services,
              items: [for (final book in series.books) ShelfBook(book)],
              onOpen: (item) => _open(context, services, item),
              showSeriesPosition: true,
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: 24 + floatingBarInset(context)),
            ),
          ],
        );
      },
    ),
  );
}

/// The Library tab: nothing while a restore reads the account's saved
/// catalog, then the library selector until the account has chosen book
/// libraries, then the shelf. Search and the layout toggle join the top bar
/// with the shelf. The tab opens the pages of the entries that the shelf
/// reports, and saves the view that the layout toggle reports.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key, required this.services});
  final LibraryServices services;

  /// The tab follows only the account, whether its saved catalog is still
  /// being read, and whether it chose book libraries.
  @override
  Widget build(BuildContext context) {
    final catalog = services.catalog;
    final account = catalog.accountNotifier;
    return ListenableSelector(
      listenable: account,
      select: () => (
        account: account.value.session?.scope.key,
        restoring: account.value.restoring,
        choosing: account.value.selected.isEmpty,
      ),
      builder: (context, library, _) => TabFrame(
        bar: AppBar(
          title: const Text('Library'),
          actions: [
            if (!library.restoring && !library.choosing) ...[
              IconButton(
                tooltip: 'Search',
                onPressed: () => openSearch(context, services),
                icon: const Icon(Icons.search_rounded),
              ),
              _layoutToggle(services),
              const SizedBox(width: 8),
            ],
          ],
        ),
        child: TabPage(
          catalog: catalog,
          playback: services.playback,
          child: library.restoring
              ? const SizedBox.shrink()
              : library.choosing
              ? LibrarySelector(
                  key: ValueKey(library.account),
                  catalog: catalog,
                )
              : LibraryShelf(
                  key: ValueKey(library.account),
                  services: services,
                  onOpen: (item) => _open(context, services, item),
                ),
        ),
      ),
    );
  }
}
