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
    outlineVariant: Color(night ? 0xFF504234 : 0xFFD9CCB6),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: sepia,
      linearTrackColor: wash,
      borderRadius: BorderRadius.circular(10),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeUpwardsPageTransitionsBuilder()},
    ),
  );
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

class BookfinPanel extends StatelessWidget {
  const BookfinPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
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
