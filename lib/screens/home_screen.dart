import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../services/download_service.dart';
import '../services/arcore_service.dart';
import '../main.dart';
import 'ar_view_screen.dart';
import 'add_project_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ArProject> _projects = [];
  bool _loading = true;
  String _lang = 'fr';
  final Set<String> _updating = {};
  final Map<String, double> _preloadProgress = {};
  Timer? _preloadTimer;

  final Map<String, Map<String, String>> _t = {
    'title': {'fr': 'Projets', 'en': 'Projects'},
    'empty': {'fr': 'Aucun projet téléchargé', 'en': 'No project downloaded'},
    'emptyHint': {
      'fr': 'Appuyez sur + pour ajouter un chantier',
      'en': 'Tap + to add a project'
    },
    'delete': {'fr': 'Supprimer', 'en': 'Delete'},
    'deleteTitle': {'fr': 'Supprimer le projet ?', 'en': 'Delete project?'},
    'deleteBody': {
      'fr': 'Les fichiers seront supprimés de cet appareil.',
      'en': 'Files will be removed from this device.'
    },
    'cancel': {'fr': 'Annuler', 'en': 'Cancel'},
    'synced': {'fr': 'Synchronisé', 'en': 'Synced'},
    'update': {'fr': 'Mise à jour dispo', 'en': 'Update available'},
    'offline': {'fr': 'Hors-ligne', 'en': 'Offline'},
    'downloaded': {'fr': 'Téléchargé le', 'en': 'Downloaded on'},
  };

  String tr(String key) => _t[key]?[_lang] ?? key;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final projects = await StorageService.loadProjects();
    final lang = await StorageService.getLanguage();
    setState(() {
      _projects = projects;
      _lang = lang;
      _loading = false;
    });
    // Vérification silencieuse des mises à jour en arrière-plan
    _checkForUpdates(projects);
    // Préchargement des GLB dans le cache Kotlin
    _preloadAllModels(projects);
  }

  Future<void> _preloadAllModels(List<ArProject> projects) async {
    for (final project in projects) {
      if (project.vues.isEmpty) continue;
      await ArCoreService.preloadModels(project.code, project.pass, project.vues);
    }
    _startPreloadPolling(projects);
  }

  void _startPreloadPolling(List<ArProject> projects) {
    _preloadTimer?.cancel();
    _preloadTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      bool allDone = true;
      for (final project in projects) {
        if (project.vues.isEmpty) continue;
        final total = project.vues.fold<int>(0, (s, v) => s + v.models.length);
        if (total == 0) continue;
        final cached = await ArCoreService.getCachedCount(
            project.code, project.pass, project.vues);
        final progress = cached / total;
        if (mounted) {
          setState(() => _preloadProgress[project.code] = progress);
        }
        if (progress < 1.0) allDone = false;
      }
      if (allDone) _preloadTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdates(List<ArProject> projects) async {
    for (final project in projects) {
      if (!mounted) return;
      try {
        final manifest = await DownloadService.fetchManifest(
            project.code, project.pass);
        if (!mounted) return;
        final remoteVersion = (manifest?['version'] as num?)?.toInt() ?? 1;
        final newStatus =
            remoteVersion > project.version ? 'update' : 'synced';
        if (newStatus != project.status) {
          await StorageService.updateProjectStatus(project.code, newStatus);
          final updated = await StorageService.loadProjects();
          if (mounted) setState(() => _projects = updated);
        }
      } catch (_) {
        // Pas de réseau — on ne change pas le statut
      }
    }
  }

  Future<void> _toggleLanguage() async {
    final newLang = _lang == 'fr' ? 'en' : 'fr';
    await StorageService.setLanguage(newLang);
    if (mounted) {
      ArMepApp.setLocale(context, Locale(newLang));
      setState(() => _lang = newLang);
    }
  }

  Future<void> _goToAddProject() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddProjectScreen()),
    );
    if (result == true) await _loadData();
  }

  Future<void> _confirmDelete(ArProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArMepTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
          side: const BorderSide(color: ArMepTheme.border),
        ),
        title: Text(tr('deleteTitle'), style: ArMepTheme.titleCard),
        content: Text(tr('deleteBody'), style: ArMepTheme.bodyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ArMepTheme.accentRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DownloadService.deleteProjectFiles(project.fullCode);
      await StorageService.deleteProject(project.code);
      await _loadData();
    }
  }

  Future<void> _updateProject(ArProject project) async {
    setState(() => _updating.add(project.code));
    final manifest =
        await DownloadService.fetchManifest(project.code, project.pass);
    if (manifest == null || !mounted) return;

    final vuesJson = manifest['vues'] as List? ?? [];
    final vues = vuesJson
        .map((v) => ArVue.fromJson(v as Map<String, dynamic>))
        .toList();

    await DownloadService.downloadProjectFiles(
        project.code, project.pass, vues, (_, __, ___) {});

    final updated = ArProject(
      code: project.code,
      pass: project.pass,
      name: manifest['name'] as String,
      status: 'synced',
      downloadedAt: project.downloadedAt,
      vues: vues,
      version: (manifest['version'] as num?)?.toInt() ?? 1,
      updatedAt: manifest['updatedAt'] as String? ?? '',
    );
    await StorageService.addProject(updated);
    if (mounted) {
      setState(() => _updating.remove(project.code));
      await _loadData();
    }
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

  Map<String, Color> _metierColors(ArProject project) {
    final map = <String, Color>{};
    for (final vue in project.vues) {
      for (final filename in vue.models) {
        final parts = filename.endsWith('.glb')
            ? filename.substring(0, filename.length - 4).split('-')
            : filename.split('-');
        if (parts.length >= 2) {
          map[parts[parts.length - 2]] = _colorFromFilename(filename);
        }
      }
    }
    return map;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'update':
        return ArMepTheme.accentOrange;
      case 'offline':
        return ArMepTheme.textSecondary;
      default:
        return ArMepTheme.accentGreen;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'update':
        return Icons.sync_problem_outlined;
      case 'offline':
        return Icons.cloud_off_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArMepTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: ArMepTheme.bgPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DC AR Vision', style: ArMepTheme.accentLabel),
            Text(tr('title'), style: ArMepTheme.titleScreen),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _toggleLanguage,
            child: Container(
              margin: const EdgeInsets.only(right: ArMepTheme.spaceMD),
              padding: const EdgeInsets.symmetric(
                  horizontal: ArMepTheme.spaceSM, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: ArMepTheme.border),
                borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
              ),
              child: Text(_lang.toUpperCase(), style: ArMepTheme.accentLabel),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: ArMepTheme.border),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: ArMepTheme.accentBlue))
              : _projects.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
        ),
      ),
      floatingActionButton: SafeArea(
        child: FloatingActionButton(
          onPressed: _goToAddProject,
          backgroundColor: ArMepTheme.accentBlue,
          foregroundColor: ArMepTheme.bgPrimary,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 64, color: ArMepTheme.textMuted),
          const SizedBox(height: ArMepTheme.spaceMD),
          Text(tr('empty'), style: ArMepTheme.titleCard),
          const SizedBox(height: ArMepTheme.spaceSM),
          Text(tr('emptyHint'), style: ArMepTheme.bodyText),
        ],
      ),
    );
  }

  Widget _buildList() {
    final bottomPadding = 56.0;
    return RefreshIndicator(
      color: ArMepTheme.accentBlue,
      backgroundColor: ArMepTheme.bgSecondary,
      onRefresh: _loadData,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          ArMepTheme.spaceMD,
          ArMepTheme.spaceMD,
          ArMepTheme.spaceMD,
          ArMepTheme.spaceMD + bottomPadding + 56,
        ),
        itemCount: _projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: ArMepTheme.spaceSM),
        itemBuilder: (_, i) => _buildProjectCard(_projects[i]),
      ),
    );
  }

  Widget _buildProjectCard(ArProject project) {
    final statusColor = _statusColor(project.status);
    final statusIcon = _statusIcon(project.status);
    final date = '${project.downloadedAt.day.toString().padLeft(2, '0')}/'
        '${project.downloadedAt.month.toString().padLeft(2, '0')}/'
        '${project.downloadedAt.year}';

    return Dismissible(
      key: Key(project.code),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ArMepTheme.spaceMD),
        decoration: BoxDecoration(
          color: ArMepTheme.accentRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
          border: Border.all(color: ArMepTheme.accentRed.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.delete_outline, color: ArMepTheme.accentRed),
      ),
      confirmDismiss: (_) async {
        await _confirmDelete(project);
        return false;
      },
      child: Container(
        decoration: ArMepTheme.cardDecoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ArViewScreen(project: project),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
              padding: const EdgeInsets.all(ArMepTheme.spaceMD),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ArMepTheme.bgTertiary,
                      borderRadius: BorderRadius.circular(ArMepTheme.radiusSM),
                      border: Border.all(color: ArMepTheme.border),
                    ),
                    child: const Icon(Icons.view_in_ar_outlined,
                        color: ArMepTheme.accentBlue, size: 22),
                  ),
                  const SizedBox(width: ArMepTheme.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name, style: ArMepTheme.titleCard),
                        const SizedBox(height: 2),
                        Text(project.code, style: ArMepTheme.labelCode),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: project.vues
                              .map((vue) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: ArMepTheme.accentBlue
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: ArMepTheme.accentBlue
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(vue.name,
                                        style: ArMepTheme.accentLabel
                                            .copyWith(fontSize: 9)),
                                  ))
                              .toList(),
                        ),
                        if (project.metiers.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 3,
                            children: _metierColors(project)
                                .entries
                                .map((e) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: e.value.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                            color: e.value.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(e.key,
                                          style: ArMepTheme.bodyText.copyWith(
                                              fontSize: 8,
                                              color: e.value,
                                              fontFamily: 'monospace')),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (project.status == 'update')
                        GestureDetector(
                          onTap: _updating.contains(project.code)
                              ? null
                              : () => _updateProject(project),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _updating.contains(project.code)
                                  ? ArMepTheme.accentOrange.withValues(alpha: 0.25)
                                  : ArMepTheme.accentOrange.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(ArMepTheme.radiusSM),
                              border: Border.all(
                                  color: ArMepTheme.accentOrange
                                      .withValues(alpha: 0.5)),
                            ),
                            child: _updating.contains(project.code)
                                ? SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: ArMepTheme.accentOrange,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.download_outlined,
                                          size: 12,
                                          color: ArMepTheme.accentOrange),
                                      const SizedBox(width: 4),
                                      Text('Mettre à jour',
                                          style: ArMepTheme.bodyText.copyWith(
                                              fontSize: 9,
                                              color: ArMepTheme.accentOrange)),
                                    ],
                                  ),
                          ),
                        )
                      else
                        Icon(statusIcon, color: statusColor, size: 18),
                      const SizedBox(height: 4),
                      Text(tr(project.status),
                          style: ArMepTheme.bodyText
                              .copyWith(color: statusColor, fontSize: 10)),
                      const SizedBox(height: 8),
                      Text('${tr('downloaded')}\n$date',
                          style: ArMepTheme.bodyText.copyWith(fontSize: 9),
                          textAlign: TextAlign.right),
                      if (project.version > 0) ...[
                        const SizedBox(height: 6),
                        Text('v${project.version}',
                            style: ArMepTheme.bodyText.copyWith(
                                fontSize: 8,
                                color: ArMepTheme.textMuted,
                                fontFamily: 'monospace')),
                      ],
                    ],
                  ),
                ],
              ),
            ),
                _buildPreloadBar(project),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreloadBar(ArProject project) {
    final progress = _preloadProgress[project.code] ?? 0.0;
    if (progress >= 1.0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(ArMepTheme.radiusMD),
        bottomRight: Radius.circular(ArMepTheme.radiusMD),
      ),
      child: Stack(
        children: [
          Container(height: 4, color: ArMepTheme.bgTertiary),
          LayoutBuilder(
            builder: (context, constraints) => ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  width: constraints.maxWidth,
                  height: 4,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF5555),
                        Color(0xFFF0883E),
                        Color(0xFFFFD700),
                        Color(0xFF69F0AE),
                      ],
                      stops: [0.0, 0.33, 0.66, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
