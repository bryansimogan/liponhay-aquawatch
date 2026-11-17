import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  AppTheme._();

  static const deep = Color(0xFF0F4C5C);
  static const deepDark = Color(0xFF04181E);
  static const aqua = Color(0xFF17B8A6);
  static const amber = Color(0xFFF08A4B);
  static const coral = Color(0xFFE2563B);

  static const _light = AquaPalette(
    brightness: Brightness.light,
    deep: deep,
    header: deep,
    onPrimary: Colors.white,
    ink: Color(0xFF0D3B47),
    inkSoft: Color(0xFF4F7179),
    bg: Color(0xFFE9F4F4),
    surface: Color(0xF2FFFFFF),
    border: Colors.white,
    aqua: Color(0xFF137D6F),
    amber: Color(0xFF9E4E16),
    coral: Color(0xFFB33427),
  );

  static const _dark = AquaPalette(
    brightness: Brightness.dark,
    deep: Color(0xFF80E0D5),
    header: deepDark,
    onPrimary: deepDark,
    ink: Color(0xFFE6F6F4),
    inkSoft: Color(0xFFABCDD0),
    bg: Color(0xFF06232B),
    surface: Color(0xF20E3A45),
    border: Color(0xFF235665),
    aqua: Color(0xFF69DAC7),
    amber: Color(0xFFFFB381),
    coral: Color(0xFFFF9385),
  );

  static AquaPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static final lightTheme = _light.buildTheme();
  static final darkTheme = _dark.buildTheme();

  static double topInset(BuildContext context) => 4;
  static double bottomNavInset(BuildContext context) => 20;
}

class AppAppearance {
  static const _key = 'aqua_theme_mode';
  static final _mode = ValueNotifier(ThemeMode.system);
  static ValueListenable<ThemeMode> get mode => _mode;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode.value = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> toggle(Brightness current) async {
    final next = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    _mode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, next.name);
  }
}

class AquaPalette {
  const AquaPalette({
    required this.brightness,
    required this.deep,
    required this.header,
    required this.onPrimary,
    required this.ink,
    required this.inkSoft,
    required this.bg,
    required this.surface,
    required this.border,
    required this.aqua,
    required this.amber,
    required this.coral,
  });

  final Brightness brightness;
  final Color deep;
  final Color header;
  final Color onPrimary;
  final Color ink;
  final Color inkSoft;
  final Color bg;
  final Color surface;
  final Color border;
  final Color aqua;
  final Color amber;
  final Color coral;

  Color statusColor(String status) => switch (status) {
        'critical' => coral,
        'warning' => amber,
        _ => aqua,
      };

  BoxDecoration card({Color? borderColor, double radius = 22}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x260D3B47),
          blurRadius: 24,
          offset: Offset(0, 10),
          spreadRadius: -10,
        ),
      ],
    );
  }

  BoxDecoration tintedCard(Color accentColor, {double radius = 16}) {
    return BoxDecoration(
      color: accentColor.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
    );
  }

  TextTheme get textTheme {
    return TextTheme(
      displayLarge:
          TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: ink),
      displayMedium:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink),
      headlineLarge:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
      headlineMedium:
          TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
      headlineSmall:
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
      titleLarge:
          TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
      titleMedium:
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
      titleSmall:
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: inkSoft),
      bodyLarge: TextStyle(fontSize: 14, color: ink),
      bodyMedium: TextStyle(fontSize: 13, color: inkSoft),
      bodySmall: TextStyle(fontSize: 12, color: inkSoft),
      labelLarge:
          TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: deep),
      labelMedium:
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: inkSoft),
      labelSmall:
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: inkSoft),
    );
  }

  ThemeData buildTheme() {
    return ThemeData(
      brightness: brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: bg,
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: deep,
        secondary: aqua,
        surface: surface,
        onPrimary: onPrimary,
        onSecondary: AppTheme.deepDark,
        onSurface: ink,
        onError: AppTheme.deepDark,
        error: coral,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: header,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: deep,
        unselectedItemColor: inkSoft,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: deep, width: 1.5),
        ),
        hintStyle: TextStyle(color: inkSoft, fontSize: 13),
        labelStyle: TextStyle(color: inkSoft),
        prefixIconColor: inkSoft,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: deep,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkSoft,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 46),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: deep,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return deep;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return deep.withOpacity(0.35);
          }
          return border;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: deep.withOpacity(0.08),
        labelStyle:
            TextStyle(color: deep, fontSize: 11, fontWeight: FontWeight.w700),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: header,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle:
            TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: inkSoft, fontSize: 13),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 16,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: deep,
        foregroundColor: onPrimary,
        elevation: 2,
      ),
      dataTableTheme: DataTableThemeData(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
        ),
        headingTextStyle: TextStyle(
          color: deep,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        dataTextStyle: TextStyle(color: ink, fontSize: 12),
        dividerThickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
