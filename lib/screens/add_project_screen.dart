import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../services/download_service.dart';
import 'qr_scan_screen.dart';

class AddProjectScreen extends StatefulWidget {
  const AddProjectScreen({super.key});
  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  String _code = '';
  String _pass = '';
  bool _codeConfirmed = false;
  String? _errorMessage;
  bool _downloading = false;
  int _downloadCurrent = 0;
  int _downloadTotal = 0;
  String _downloadStatus = '';
  String get _lang => Localizations.localeOf(context).languageCode;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  final Map<String, Map<String, String>> _t = {
    'titleCode': {'fr': 'Code chantier', 'en': 'Project code'},
    'titlePass': {'fr': 'Mot de passe', 'en': 'Password'},
    'titleDl': {'fr': 'Téléchargement...', 'en': 'Downloading...'},
    'stepCode': {'fr': 'Code chantier', 'en': 'Project code'},
    'stepPass': {'fr': 'Mot de passe', 'en': 'Password'},
    'validate': {'fr': 'Valider', 'en': 'Confirm'},
    'download': {'fr': 'Télécharger le projet', 'en': 'Download project'},
    'hint': {'fr': 'ex: A3-25-1604', 'en': 'e.g. A3-25-1604'},
    'scanTip': {'fr': 'Scanner un QR code', 'en': 'Scan QR code'},
    'checkConn': {'fr': 'Vérification de la connexion...', 'en': 'Checking connection...'},
    'checkProject': {'fr': 'Vérification du projet...', 'en': 'Checking project...'},
    'alreadyLocal': {'fr': 'Projet déjà disponible localement.', 'en': 'Project already available locally.'},
    'dlModels': {'fr': 'Téléchargement des modèles 3D...', 'en': 'Downloading 3D models...'},
    'files': {'fr': 'fichiers', 'en': 'files'},
    'errCode': {'fr': 'Entrez le code chantier.', 'en': 'Enter the project code.'},
    'errPass': {'fr': 'Le mot de passe doit faire 4 caractères.', 'en': 'Password must be 4 characters.'},
    'errNoNet': {
      'fr': 'Pas de connexion réseau. Ce projet n\'est pas encore téléchargé sur cet appareil.',
      'en': 'No network connection. This project is not yet downloaded on this device.'
    },
    'errAuth': {'fr': 'Code ou mot de passe incorrect.', 'en': 'Incorrect code or password.'},
  };

  String tr(String key) => _t[key]?[_lang] ?? key;

  final List<String> _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '-',
    '⌫',
  ];

  void _tap(String key) {
    if (key == '⌫') {
      setState(() {
        if (!_codeConfirmed) {
          if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
        } else {
          if (_pass.isNotEmpty) _pass = _pass.substring(0, _pass.length - 1);
        }
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _errorMessage = null;
      if (!_codeConfirmed) {
        _code += key;
      } else {
        if (_pass.length < 4) _pass += key;
      }
    });
  }

  void _confirmCode() {
    if (_code.isEmpty) {
      setState(() => _errorMessage = tr('errCode'));
      return;
    }
    setState(() => _codeConfirmed = true);
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<({String code, String pass})>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _code = result.code;
      _pass = result.pass;
      _codeConfirmed = true;
      _errorMessage = null;
    });
    await _submit();
  }

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('raw.githubusercontent.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_pass.length != 4) {
      setState(() => _errorMessage = tr('errPass'));
      return;
    }

    setState(() {
      _downloading = true;
      _errorMessage = null;
      _downloadStatus = tr('checkConn');
    });

    // 1. Vérifier si le projet existe déjà localement
    final alreadyExists = await StorageService.projectExists(_code);
    if (alreadyExists) {
      setState(() => _downloadStatus = tr('alreadyLocal'));
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context, true);
      return;
    }

    // 2. Vérifier la connexion réseau
    final hasNetwork = await _hasNetwork();
    if (!hasNetwork) {
      setState(() {
        _downloading = false;
        _errorMessage = tr('errNoNet');
      });
      return;
    }

    // 3. Récupérer le manifest
    setState(() => _downloadStatus = tr('checkProject'));
    final manifest = await DownloadService.fetchManifest(_code, _pass);
    if (manifest == null) {
      setState(() {
        _downloading = false;
        _errorMessage = tr('errAuth');
      });
      return;
    }

    // 4. Parser les vues depuis le manifest
    final vuesJson = manifest['vues'] as List? ?? [];
    final vues = vuesJson
        .map((v) => ArVue.fromJson(v as Map<String, dynamic>))
        .toList();

    // Compter les fichiers uniques à télécharger
    final allModels = <String>{};
    final allTargets = <String>{};
    for (final vue in vues) {
      allModels.addAll(vue.models);
      allTargets.add(vue.target);
    }

    setState(() {
      _downloadTotal = allModels.length + allTargets.length;
      _downloadCurrent = 0;
      _downloadStatus = tr('dlModels');
    });

    await DownloadService.downloadProjectFiles(
      _code,
      _pass,
      vues,
      (current, total, filename) {
        setState(() {
          _downloadCurrent = current;
          _downloadTotal = total;
          _downloadStatus = filename;
        });
      },
    );

    // 5. Sauvegarder le projet
    final project = ArProject(
      code: _code,
      pass: _pass,
      name: manifest['name'] as String,
      status: 'synced',
      downloadedAt: DateTime.now(),
      vues: vues,
      version: (manifest['version'] as num?)?.toInt() ?? 1,
      updatedAt: manifest['updatedAt'] as String? ?? '',
    );

    await StorageService.addProject(project);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _stepBadge(String n, bool active) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: active ? ArMepTheme.accentBlue : ArMepTheme.bgTertiary,
        shape: BoxShape.circle,
        border: Border.all(
            color: active ? ArMepTheme.accentBlue : ArMepTheme.border),
      ),
      child: Center(
          child: Text(n,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color:
                      active ? ArMepTheme.bgPrimary : ArMepTheme.textMuted))),
    );
  }

  Widget _buildKey(String label) {
    final isDelete = label == '⌫';
    final isDash = label == '-';
    return GestureDetector(
      onTap: _downloading ? null : () => _tap(label),
      child: Container(
        decoration: BoxDecoration(
          color: isDelete
              ? ArMepTheme.accentRed.withValues(alpha: 0.15)
              : isDash
                  ? ArMepTheme.bgTertiary
                  : ArMepTheme.bgSecondary,
          borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
          border: Border.all(
              color: isDelete
                  ? ArMepTheme.accentRed.withValues(alpha: 0.4)
                  : ArMepTheme.border),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: _downloading
                        ? ArMepTheme.textMuted
                        : isDelete
                            ? ArMepTheme.accentRed
                            : ArMepTheme.textPrimary))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 10;
    return Scaffold(
      backgroundColor: ArMepTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: ArMepTheme.bgPrimary,
        elevation: 0,
        title: Text(
            _downloading
                ? tr('titleDl')
                : _codeConfirmed
                    ? tr('titlePass')
                    : tr('titleCode'),
            style: ArMepTheme.titleCard),
        leading: (!_downloading && _codeConfirmed)
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: ArMepTheme.textPrimary),
                onPressed: () => setState(() {
                  _codeConfirmed = false;
                  _pass = '';
                  _errorMessage = null;
                }),
              )
            : null,
        actions: [
          if (!_downloading)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner,
                  color: ArMepTheme.accentBlue),
              tooltip: tr('scanTip'),
              onPressed: _scanQr,
            ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: ArMepTheme.border)),
      ),
      body: AppBackground(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(ArMepTheme.spaceLG),
            child: Column(
              children: [
                if (!_downloading)
                  Row(
                    children: [
                      _stepBadge('1', !_codeConfirmed),
                      const SizedBox(width: 8),
                      Text(tr('stepCode'),
                          style: ArMepTheme.bodyText.copyWith(
                              color: !_codeConfirmed
                                  ? ArMepTheme.textPrimary
                                  : ArMepTheme.accentGreen)),
                      const SizedBox(width: 16),
                      _stepBadge('2', _codeConfirmed),
                      const SizedBox(width: 8),
                      Text(tr('stepPass'),
                          style: ArMepTheme.bodyText.copyWith(
                              color: _codeConfirmed
                                  ? ArMepTheme.textPrimary
                                  : ArMepTheme.textMuted)),
                    ],
                  ),
                if (!_downloading) const SizedBox(height: ArMepTheme.spaceMD),
                if (!_downloading)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: ArMepTheme.spaceMD,
                        vertical: ArMepTheme.spaceLG),
                    decoration: BoxDecoration(
                      color: ArMepTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
                      border: Border.all(
                          color: ArMepTheme.accentBlue.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _codeConfirmed
                          ? (String.fromCharCodes(
                                  List.filled(_pass.length, 0x25CF)) +
                              String.fromCharCodes(
                                  List.filled(4 - _pass.length, 0x25CB)))
                          : (_code.isEmpty ? tr('hint') : _code),
                      style: TextStyle(
                          fontSize: 28,
                          fontFamily: 'monospace',
                          letterSpacing: _codeConfirmed ? 12 : 3,
                          color: _codeConfirmed
                              ? ArMepTheme.accentGreen
                              : (_code.isEmpty
                                  ? ArMepTheme.textMuted
                                  : ArMepTheme.textPrimary)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_downloading) ...[
                  const SizedBox(height: ArMepTheme.spaceLG),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(ArMepTheme.spaceMD),
                    decoration: BoxDecoration(
                      color: ArMepTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
                      border: Border.all(color: ArMepTheme.border),
                    ),
                    child: Column(
                      children: [
                        Text(_downloadStatus,
                            style: ArMepTheme.bodyText,
                            textAlign: TextAlign.center),
                        const SizedBox(height: ArMepTheme.spaceMD),
                        if (_downloadTotal > 0) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _downloadCurrent / _downloadTotal,
                              backgroundColor: ArMepTheme.bgTertiary,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  ArMepTheme.accentBlue),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: ArMepTheme.spaceSM),
                          Text('$_downloadCurrent / $_downloadTotal ${tr('files')}',
                              style: ArMepTheme.labelCode),
                        ] else
                          const CircularProgressIndicator(
                              color: ArMepTheme.accentBlue, strokeWidth: 2),
                      ],
                    ),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: ArMepTheme.spaceSM),
                  Container(
                    padding: const EdgeInsets.all(ArMepTheme.spaceSM),
                    decoration: BoxDecoration(
                        color: ArMepTheme.accentRed.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(ArMepTheme.radiusSM),
                        border: Border.all(
                            color: ArMepTheme.accentRed.withValues(alpha: 0.4))),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: ArMepTheme.accentRed, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_errorMessage!,
                              style: ArMepTheme.bodyText.copyWith(
                                  color: ArMepTheme.accentRed, fontSize: 12))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          if (!_downloading)
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
                child: Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: _keys.length,
                        itemBuilder: (_, i) => _buildKey(_keys[i]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _codeConfirmed ? _submit : _confirmCode,
                        child: Text(
                            _codeConfirmed ? tr('download') : tr('validate'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      )),
    );
  }
}
