import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/project.dart';
import '../services/arcore_service.dart';

class ArViewScreen extends StatefulWidget {
  final ArProject project;
  const ArViewScreen({super.key, required this.project});

  @override
  State<ArViewScreen> createState() => _ArViewScreenState();
}

class _ArViewScreenState extends State<ArViewScreen>
    with WidgetsBindingObserver {
  // Visibilité par métier (globale, appliquée à toutes les vues)
  late Map<String, bool> _visibility;

  bool _arInitialized = false;
  String _arMessage = 'Initialisation AR...';
  Set<String> _recenteredVues = {};
  Timer? _readinessTimer;

  final Map<String, Map<String, String>> _t = {
    'options': {'fr': 'Options', 'en': 'Options'},
    'visibility': {'fr': 'Visibilité', 'en': 'Visibility'},
    'reset': {'fr': 'Réinitialiser', 'en': 'Reset'},
    'save': {'fr': 'Enregistrer', 'en': 'Save'},
    'saved': {'fr': 'Paramètres enregistrés', 'en': 'Settings saved'},
    'arSimul': {'fr': 'Simulation', 'en': 'Simulation'},
    'arActive': {'fr': 'AR Active', 'en': 'AR Active'},
    'scanHint': {
      'fr': 'Pointez vers une cible pour afficher la 3D',
      'en': 'Point at a target to display 3D'
    },
    'arNotSupported': {
      'fr': 'ARCore non supporté',
      'en': 'ARCore not supported'
    },
    'arNotInstalled': {
      'fr': 'ARCore requis — installation...',
      'en': 'ARCore required — installing...'
    },
    'noVues': {
      'fr': 'Aucune vue configurée pour ce projet.',
      'en': 'No views configured for this project.'
    },
  };

  String get _lang => Localizations.localeOf(context).languageCode;
  String tr(String key) => _t[key]?[_lang] ?? key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Visibilité initialisée pour tous les métiers du projet
    _visibility = {for (final m in widget.project.metiers) m: true};
    _initAr();
  }

  @override
  void dispose() {
    _readinessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ArCoreService.closeSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ArCoreService.closeSession();
    } else if (state == AppLifecycleState.resumed && _arInitialized) {
      ArCoreService.initSession();
    }
  }

  Future<void> _initAr() async {
    if (widget.project.vues.isEmpty) {
      setState(() => _arMessage = tr('noVues'));
      return;
    }

    // 0. Permission caméra
    final hasPermission = await ArCoreService.requestCameraPermission();
    if (!hasPermission) {
      setState(() => _arMessage = 'Permission caméra refusée.');
      return;
    }

    // 1. Vérifier disponibilité
    final status = await ArCoreService.checkAvailability();
    if (status == ArCoreStatus.unsupported) {
      setState(() => _arMessage = tr('arNotSupported'));
      return;
    }

    // 2. Initialiser session
    final result = await ArCoreService.initSession();
    switch (result) {
      case ArCoreInitResult.ok:
        setState(() {
          _arInitialized = true;
          _arMessage = '';
        });
        // 3. Envoyer les vues après que l'AndroidView soit créé (post-frame)
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            await _sendVues();
            _startReadinessPolling();
          }
        });
        break;
      case ArCoreInitResult.installRequested:
        setState(() => _arMessage = tr('arNotInstalled'));
        break;
      case ArCoreInitResult.notInstalled:
        setState(() => _arMessage = tr('arNotInstalled'));
        break;
      case ArCoreInitResult.notCompatible:
        setState(() => _arMessage = tr('arNotSupported'));
        break;
      case ArCoreInitResult.error:
        setState(() {
          _arInitialized = false;
          _arMessage = 'Simulation (AR indisponible)';
        });
        break;
    }
  }

  /// Envoie les vues à Android en filtrant les modèles selon la visibilité des métiers.
  Future<void> _sendVues() async {
    final filteredVues = widget.project.vues.map((vue) {
      final filteredModels = vue.models.where((filename) {
        final metier = _extractMetierFromFilename(filename);
        return _visibility[metier] ?? true;
      }).toList();
      return ArVue(
        id: vue.id,
        name: vue.name,
        target: vue.target,
        widthCm: vue.widthCm,
        models: filteredModels,
      );
    }).toList();

    await ArCoreService.setVues(
      widget.project.code,
      widget.project.pass,
      filteredVues,
    );
  }

  void _startReadinessPolling() {
    _readinessTimer?.cancel();
    final expectedVueIds = widget.project.vues
        .where((v) => v.models.isNotEmpty)
        .map((v) => v.id)
        .toSet();

    _readinessTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      final ready = await ArCoreService.getRecenteredVues();
      if (!mounted) return;
      setState(() => _recenteredVues = ready.toSet());
      if (expectedVueIds.isNotEmpty &&
          expectedVueIds.every((id) => _recenteredVues.contains(id))) {
        _readinessTimer?.cancel();
      }
    });
  }

  bool get _modelsReady {
    final expected = widget.project.vues
        .where((v) => v.models.isNotEmpty)
        .map((v) => v.id)
        .toSet();
    if (expected.isEmpty) return true;
    return expected.every((id) => _recenteredVues.contains(id));
  }

  String _extractMetierFromFilename(String filename) {
    final withoutExt =
        filename.endsWith('.glb') ? filename.substring(0, filename.length - 4) : filename;
    final parts = withoutExt.split('-');
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  Color _colorFromFilename(String filename) {
    final withoutExt = filename.endsWith('.glb')
        ? filename.substring(0, filename.length - 4)
        : filename;
    final hex = withoutExt.split('-').last;
    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return ArMepTheme.accentBlue;
    }
  }

  void _openOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ArMepTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ArMepTheme.radiusLG)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: ArMepTheme.textMuted,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(ArMepTheme.spaceMD, 0,
                    ArMepTheme.spaceMD, ArMepTheme.spaceSM),
                child: Row(
                  children: [
                    Expanded(
                        child:
                            Text(tr('options'), style: ArMepTheme.titleCard)),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close,
                          color: ArMepTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Divider(color: ArMepTheme.border, height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(ArMepTheme.spaceMD),
                  children: [
                    if (widget.project.vues.isNotEmpty) ...[
                      Text(tr('visibility').toUpperCase(),
                          style: ArMepTheme.accentLabel),
                      const SizedBox(height: ArMepTheme.spaceSM),
                      ...widget.project.vues.map((vue) {
                        final metierColors = <String, Color>{};
                        for (final f in vue.models) {
                          final m = _extractMetierFromFilename(f);
                          if (m.isNotEmpty) metierColors[m] = _colorFromFilename(f);
                        }
                        if (metierColors.isEmpty) return const SizedBox();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 6, top: 4),
                              child: Text(vue.name,
                                  style: ArMepTheme.bodyText.copyWith(
                                      fontSize: 10,
                                      color: ArMepTheme.textSecondary)),
                            ),
                            Wrap(
                              spacing: ArMepTheme.spaceSM,
                              runSpacing: ArMepTheme.spaceSM,
                              children: metierColors.keys.map((metier) {
                                final active = _visibility[metier] ?? true;
                                final color = metierColors[metier]!;
                                return GestureDetector(
                                  onTap: () async {
                                    setModalState(
                                        () => _visibility[metier] = !active);
                                    setState(() {});
                                    await _sendVues();
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? color.withValues(alpha: 0.15)
                                          : ArMepTheme.bgTertiary,
                                      borderRadius: BorderRadius.circular(
                                          ArMepTheme.radiusSM),
                                      border: Border.all(
                                          color: active
                                              ? color.withValues(alpha: 0.6)
                                              : ArMepTheme.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                                color: active
                                                    ? color
                                                    : ArMepTheme.textMuted,
                                                shape: BoxShape.circle)),
                                        const SizedBox(width: 6),
                                        Text(metier,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w700,
                                                color: active
                                                    ? color
                                                    : ArMepTheme.textMuted)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: ArMepTheme.spaceSM),
                          ],
                        );
                      }),
                      const SizedBox(height: ArMepTheme.spaceSM),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              setModalState(() {
                                _visibility = {
                                  for (final m in widget.project.metiers)
                                    m: true
                                };
                              });
                              setState(() {});
                              await _sendVues();
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: Text(tr('reset')),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: ArMepTheme.textSecondary,
                                side: const BorderSide(
                                    color: ArMepTheme.border)),
                          ),
                        ),
                        const SizedBox(width: ArMepTheme.spaceSM),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr('saved'),
                                      style: const TextStyle(
                                          fontFamily: 'monospace')),
                                  backgroundColor: ArMepTheme.bgSecondary,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ArMepTheme.radiusSM),
                                      side: const BorderSide(
                                          color: ArMepTheme.accentGreen)),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: Text(tr('save')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ArMepTheme.spaceLG),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: FloatingActionButton(
        onPressed: _openOptions,
        backgroundColor: ArMepTheme.bgSecondary,
        child: const Icon(Icons.tune, color: ArMepTheme.accentBlue),
      ),
      body: Stack(
        children: [
          _arInitialized
              ? const AndroidView(
                  viewType: 'ar_camera_view',
                  layoutDirection: TextDirection.ltr,
                  creationParamsCodec: StandardMessageCodec(),
                )
              : _buildSimulatedBackground(),
          _buildTopBar(),
          if (_arMessage.isNotEmpty) _buildArMessage(),
          if (_arInitialized && !_modelsReady) _buildLoadingBar(),
          if (_arInitialized && _modelsReady) _buildScanHint(),
        ],
      ),
    );
  }

  Widget _buildSimulatedBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1F2D), Color(0xFF0A0A0A)],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }

  Widget _buildTopBar() {
    final vueNames = widget.project.vues.map((v) => v.name).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ArMepTheme.spaceMD, vertical: ArMepTheme.spaceSM),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
                  border: Border.all(color: ArMepTheme.border),
                ),
                child: const Icon(Icons.arrow_back,
                    color: ArMepTheme.textPrimary, size: 18),
              ),
            ),
            const SizedBox(width: ArMepTheme.spaceSM),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ArMepTheme.spaceSM, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
                  border: Border.all(color: ArMepTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.project.name,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ArMepTheme.textPrimary,
                            fontFamily: 'monospace')),
                    if (vueNames.isNotEmpty)
                      Text(vueNames.join(' · '),
                          style: ArMepTheme.labelCode
                              .copyWith(fontSize: 9),
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            const SizedBox(width: ArMepTheme.spaceSM),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
                border: Border.all(
                    color: _arInitialized
                        ? ArMepTheme.accentGreen.withValues(alpha: 0.5)
                        : ArMepTheme.accentOrange.withValues(alpha: 0.5)),
              ),
              child: Text(_arInitialized ? tr('arActive') : tr('arSimul'),
                  style: TextStyle(
                      fontSize: 9,
                      color: _arInitialized
                          ? ArMepTheme.accentGreen
                          : ArMepTheme.accentOrange,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArMessage() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(ArMepTheme.spaceLG),
        padding: const EdgeInsets.all(ArMepTheme.spaceMD),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
          border: Border.all(color: ArMepTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ArMepTheme.accentBlue)),
            const SizedBox(width: ArMepTheme.spaceSM),
            Flexible(
                child: Text(_arMessage,
                    style: ArMepTheme.bodyText, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBar() {
    final total = widget.project.vues.where((v) => v.models.isNotEmpty).length;
    final ready = _recenteredVues.length;
    return Positioned(
      bottom: 100,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ArMepTheme.spaceMD, vertical: ArMepTheme.spaceSM),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ArMepTheme.accentBlue.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: ArMepTheme.accentBlue),
                ),
                const SizedBox(width: 8),
                Text(
                  total > 1
                      ? 'Préparation des modèles 3D... ($ready/$total)'
                      : 'Préparation des modèles 3D...',
                  style: const TextStyle(
                      fontSize: 11,
                      color: ArMepTheme.textSecondary,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: total > 0 ? ready / total : null,
                backgroundColor: ArMepTheme.bgTertiary,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(ArMepTheme.accentBlue),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanHint() {
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ArMepTheme.spaceMD, vertical: ArMepTheme.spaceSM),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ArMepTheme.border),
          ),
          child: Text(tr('scanHint'),
              style: const TextStyle(
                  fontSize: 12,
                  color: ArMepTheme.textSecondary,
                  fontFamily: 'monospace')),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
