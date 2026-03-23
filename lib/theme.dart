import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppBackground extends StatefulWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load('assets/images/bg_trame.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TramePainter(_image, 800, 0.08),
      child: widget.child,
    );
  }
}

class _TramePainter extends CustomPainter {
  final ui.Image? image;
  final double tileSize; // dp
  final double opacity;

  _TramePainter(this.image, this.tileSize, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D1117),
    );
    if (image == null) return;
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity);
    final src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
    for (double y = 0; y < size.height; y += tileSize) {
      for (double x = 0; x < size.width; x += tileSize) {
        canvas.drawImageRect(image!, src, Rect.fromLTWH(x, y, tileSize, tileSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TramePainter old) =>
      old.image != image || old.tileSize != tileSize || old.opacity != opacity;
}

class ArMepTheme {
  // ─── COULEURS PRINCIPALES ───────────────────────────────
  static const Color bgPrimary      = Color(0xFF0D1117);  // fond principal
  static const Color bgSecondary    = Color(0xFF161B22);  // cartes, panneaux
  static const Color bgTertiary     = Color(0xFF1C2128);  // éléments survolés

  // ─── COULEURS D'ACCENT ──────────────────────────────────
  static const Color accentBlue     = Color(0xFF9B59F5);  // titres, bordures (violet)
  static const Color accentGreen    = Color(0xFF69F0AE);  // succès, sync OK
  static const Color accentOrange   = Color(0xFFF0883E);  // avertissements
  static const Color accentRed      = Color(0xFFFF5555);  // erreurs, suppression

  // ─── TEXTE ──────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFE6EDF3);  // texte principal
  static const Color textSecondary  = Color(0xFF8B949E);  // texte secondaire
  static const Color textMuted      = Color(0xFF484F58);  // texte désactivé

  // ─── BORDURES ───────────────────────────────────────────
  static const Color border         = Color(0xFF21262D);  // bordures standard
  static const Color borderActive   = Color(0xFF4FC3F7);  // bordure active

  // ─── TYPOGRAPHIE ────────────────────────────────────────
  static const double fontXS        = 10.0;
  static const double fontSM        = 12.0;
  static const double fontMD        = 14.0;
  static const double fontLG        = 18.0;
  static const double fontXL        = 24.0;
  static const double fontXXL       = 32.0;

  // ─── ESPACEMENTS ────────────────────────────────────────
  static const double spaceSM       = 8.0;
  static const double spaceMD       = 16.0;
  static const double spaceLG       = 24.0;
  static const double spaceXL       = 32.0;

  // ─── ARRONDIS ───────────────────────────────────────────
  static const double radiusSM      = 6.0;
  static const double radiusMD      = 10.0;
  static const double radiusLG      = 16.0;

  // ─── STYLES DE TEXTE ────────────────────────────────────
  static const TextStyle labelCode = TextStyle(
    fontSize: fontXS,
    fontFamily: 'monospace',
    letterSpacing: 0.15,
    color: textSecondary,
  );

  static const TextStyle titleScreen = TextStyle(
    fontSize: fontXL,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle titleCard = TextStyle(
    fontSize: fontMD,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyText = TextStyle(
    fontSize: fontSM,
    color: textSecondary,
    height: 1.6,
  );

  static const TextStyle accentLabel = TextStyle(
    fontSize: fontXS,
    fontFamily: 'monospace',
    letterSpacing: 0.12,
    color: accentBlue,
    fontWeight: FontWeight.w700,
  );

  // ─── DECORATIONS ────────────────────────────────────────
  static BoxDecoration cardDecoration = BoxDecoration(
    color: bgSecondary,
    borderRadius: BorderRadius.circular(radiusMD),
    border: Border.all(color: border),
  );

  static BoxDecoration cardDecorationActive = BoxDecoration(
    color: bgTertiary,
    borderRadius: BorderRadius.circular(radiusMD),
    border: Border.all(color: borderActive),
    boxShadow: [
      BoxShadow(
        color: accentBlue.withValues(alpha: 0.08),
        blurRadius: 20,
        spreadRadius: 0,
      ),
    ],
  );

  // ─── THEME MATERIAL ─────────────────────────────────────
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgPrimary,
    colorScheme: const ColorScheme.dark(
      primary: accentBlue,
      secondary: accentGreen,
      error: accentRed,
      surface: bgSecondary,
    ),
    cardColor: bgSecondary,
    dividerColor: border,
    fontFamily: 'monospace',
    appBarTheme: const AppBarTheme(
      backgroundColor: bgPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: titleScreen,
      iconTheme: IconThemeData(color: textPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentBlue,
        foregroundColor: bgPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSM),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: spaceMD,
          vertical: spaceSM,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentBlue,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgTertiary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: accentBlue, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textMuted),
    ),
  );
}
