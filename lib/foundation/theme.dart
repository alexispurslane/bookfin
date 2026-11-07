import 'package:flutter/material.dart';

class BookfinThemeTransition extends StatelessWidget {
  const BookfinThemeTransition({
    super.key,
    required this.theme,
    required this.reduceMotion,
    required this.child,
  });

  final ThemeData theme;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<ThemeData>(
    tween: _ReadableThemeTween(end: theme),
    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
    curve: Curves.easeInOut,
    builder: (context, frame, child) => Theme(data: frame, child: child!),
    child: child,
  );
}

class _ReadableThemeTween extends Tween<ThemeData> {
  _ReadableThemeTween({required ThemeData super.end});

  @override
  ThemeData lerp(double progress) {
    if (progress == 0) return begin!;
    if (progress == 1) return end!;
    final theme = ThemeData.lerp(begin!, end!, progress);
    final scheme = theme.colorScheme;
    var surfaces = [
      scheme.surface,
      scheme.surfaceContainer,
      scheme.surfaceContainerLow,
    ];
    final blackWorks = surfaces.every(
      (surface) => _contrast(Colors.black, surface) >= 4.5,
    );
    final whiteWorks = surfaces.every(
      (surface) => _contrast(Colors.white, surface) >= 4.5,
    );
    if (!blackWorks && !whiteWorks) surfaces = List.filled(3, scheme.surface);
    final ink = _readable(scheme.onSurface, surfaces);
    final subtle = _readable(scheme.onSurfaceVariant, surfaces);
    final primary = _readable(scheme.primary, surfaces);
    final safeScheme = scheme.copyWith(
      surfaceContainer: surfaces[1],
      surfaceContainerHigh: surfaces[1],
      surfaceContainerHighest: surfaces[1],
      surfaceContainerLowest: surfaces[2],
      surfaceContainerLow: surfaces[2],
      onSurface: ink,
      onSurfaceVariant: subtle,
      primary: primary,
      secondary: primary,
      onPrimary: _readable(scheme.onPrimary, [primary]),
      onSecondary: _readable(scheme.onSecondary, [primary]),
      outline: _readable(scheme.outline, surfaces),
      error: _readable(scheme.error, surfaces),
    );
    return theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          animationDuration: Duration.zero,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: theme.outlinedButtonTheme.style?.copyWith(
          animationDuration: Duration.zero,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: theme.textButtonTheme.style?.copyWith(
          animationDuration: Duration.zero,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: theme.iconButtonTheme.style?.copyWith(
          animationDuration: Duration.zero,
        ),
      ),
      colorScheme: safeScheme,
      textTheme: theme.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            bodySmall: theme.textTheme.bodySmall?.copyWith(color: subtle),
            labelSmall: theme.textTheme.labelSmall?.copyWith(color: primary),
          ),
      progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
        color: primary,
        linearTrackColor: surfaces[1],
      ),
      appBarTheme: theme.appBarTheme.copyWith(foregroundColor: ink),
      bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: surfaces[2],
      ),
      chipTheme: theme.chipTheme.copyWith(
        selectedColor: primary,
        backgroundColor: surfaces[1],
      ),
    );
  }
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

Color _readable(Color preferred, List<Color> surfaces) {
  if (surfaces.every((surface) => _contrast(preferred, surface) >= 4.5)) {
    return preferred;
  }
  final target =
      surfaces.every((surface) => _contrast(Colors.black, surface) >= 4.5)
      ? Colors.black
      : Colors.white;
  for (var step = 1; step <= 100; step++) {
    final candidate = Color.lerp(preferred, target, step / 100)!;
    if (surfaces.every((surface) => _contrast(candidate, surface) >= 4.5)) {
      return candidate;
    }
  }
  return target;
}

ThemeData bookfinTheme(Brightness brightness, {bool reduceMotion = false}) {
  final night = brightness == Brightness.dark;
  final paper = Color(night ? 0xFF251E19 : 0xFFF6EFE2);
  final sheet = Color(night ? 0xFF302720 : 0xFFFFF9EF);
  final wash = Color(night ? 0xFF3B3027 : 0xFFEAE0CE);
  final ink = Color(night ? 0xFFDCC9A9 : 0xFF39291F);
  final subtle = Color(night ? 0xFFB09A7F : 0xFF715D4B);
  final sepia = Color(night ? 0xFFC5A079 : 0xFF775035);
  final line = Color(night ? 0xFF504234 : 0xFFD9CCB6);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: sepia,
    onPrimary: night ? paper : sheet,
    secondary: sepia,
    onSecondary: night ? paper : sheet,
    error: Color(night ? 0xFFFFB4A0 : 0xFF9D3423),
    onError: night ? paper : sheet,
    surface: paper,
    onSurface: ink,
    surfaceContainerLowest: sheet,
    surfaceContainerLow: sheet,
    surfaceContainer: wash,
    surfaceContainerHigh: wash,
    surfaceContainerHighest: wash,
    onSurfaceVariant: subtle,
    outline: Color(night ? 0xFFAC9377 : 0xFF90735B),
    outlineVariant: line,
    shadow: const Color(0xFF39291F),
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: 'Outfit',
    fontFamilyFallback: const ['Roboto', 'Noto Sans'],
    visualDensity: VisualDensity.standard,
    splashFactory: reduceMotion
        ? NoSplash.splashFactory
        : InkRipple.splashFactory,
  );
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    animationDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200),
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 42,
        height: 1.05,
        letterSpacing: -1.5,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Source Serif 4',
        fontFamilyFallback: const ['Noto Serif'],
        fontSize: 21,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.55, color: subtle),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.5,
        letterSpacing: 1.5,
        color: sepia,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        animationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: wash,
      selectedColor: sepia,
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: 'Outfit', fontSize: 13, color: ink),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 13,
        color: night ? paper : sheet,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: wash,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? sepia : subtle,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Outfit',
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? sepia : subtle,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: sheet,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: sepia, width: 1.5),
      ),
      labelStyle: TextStyle(color: subtle),
      floatingLabelStyle: TextStyle(color: sepia),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
        fontFamily: 'Source Serif 4',
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: subtle,
      titleTextStyle: TextStyle(fontFamily: 'Outfit', fontSize: 15, color: ink),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 12,
        color: subtle,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? sheet
              : Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        elevation: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? 1 : 0,
        ),
        shadowColor: const WidgetStatePropertyAll(Color(0x33000000)),
        foregroundColor: WidgetStatePropertyAll(ink),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Outfit', fontSize: 13),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? sheet : subtle,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? sepia : wash,
      ),
      trackOutlineColor: WidgetStatePropertyAll(line),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(fontFamily: 'Outfit', color: paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sheet,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: ink,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: sepia,
      linearTrackColor: wash,
      borderRadius: BorderRadius.circular(10),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: BookfinPageTransitionsBuilder()},
    ),
  );
}

/// Screen routes move without fading text, matching retained-screen navigation.
class BookfinPageTransitionsBuilder extends PageTransitionsBuilder {
  const BookfinPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.015),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

class BookfinSurface extends StatelessWidget {
  const BookfinSurface({super.key, this.color, required this.child});

  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color ?? Theme.of(context).colorScheme.surface,
    child: DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!,
      child: child,
    ),
  );
}

/// A problem that a data source reports to the person, in the error color.
class StatusMessage extends StatelessWidget {
  const StatusMessage(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}

/// The small spaced capitals that name a section of a page, for example
/// "EDITIONS" or "ON THIS PHONE".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// A rounded sheet of paper on the page, with a thin edge. It takes the
/// colors of the theme around it, so it also fits the night stage. Ink from
/// rows and buttons inside it shows on the paper.
class BookfinPanel extends StatelessWidget {
  const BookfinPanel({
    super.key,
    this.padding = const EdgeInsets.all(18),
    required this.child,
  });

  /// The space between the edge and [child]. Rows that reach the edge, such
  /// as list tiles, use [EdgeInsets.zero].
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A thin rounded line that fills with progress, as under a book in the
/// library.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.height = 3,
    this.color,
    this.trackColor,
  });

  /// How much is done, from 0 to 1. Null means unknown, and the line moves
  /// instead.
  final double? value;

  /// The thickness, in logical pixels.
  final double height;

  /// The filled part. The theme's progress color by default.
  final Color? color;

  /// The unfilled part. The theme's faint outline color by default.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: value?.clamp(0, 1),
      minHeight: height,
      color: color,
      backgroundColor:
          trackColor ?? Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// A paper panel of rows, separated by lines, with space below it.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: BookfinPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(),
            child,
          ],
        ],
      ),
    ),
  );
}

class BookfinScreenStack extends StatefulWidget {
  const BookfinScreenStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<BookfinScreenStack> createState() => _BookfinScreenStackState();
}

class _BookfinScreenStackState extends State<BookfinScreenStack>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(BookfinScreenStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    if (MediaQuery.disableAnimationsOf(context)) _motion.value = 1;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 0.015),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic)),
    child: IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: widget.children,
    ),
  );
}

/// The warm light behind the player's cover at night, and its chapter line.
const theaterGlow = Color(0xFFE4B58A);

/// The player stage at night: a dark theater with cream type and a cream
/// play button. [night] is the app's night theme.
ThemeData theaterTheme(ThemeData night) {
  const stage = Color(0xFF22170F);
  const light = Color(0xFFF3E6D2);
  const dim = Color(0xFFC4AD91);
  final scheme = night.colorScheme.copyWith(
    primary: light,
    onPrimary: stage,
    secondary: light,
    onSecondary: stage,
    surface: stage,
    onSurface: light,
    onSurfaceVariant: dim,
    surfaceContainerLowest: light.withValues(alpha: 0.06),
    surfaceContainerLow: light.withValues(alpha: 0.06),
    outlineVariant: light.withValues(alpha: 0.16),
  );
  return night.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: stage,
    textTheme: night.textTheme.apply(bodyColor: light, displayColor: light),
    iconTheme: night.iconTheme.copyWith(color: light),
  );
}

/// The bottom space that a floating bar covers. A scroll view adds it to its
/// end when its page lets content run beneath the mini player.
double floatingBarInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;
