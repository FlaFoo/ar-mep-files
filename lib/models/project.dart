class ArVue {
  final String id;
  final String name;
  final String target;
  final int widthCm;
  final List<String> models;

  const ArVue({
    required this.id,
    required this.name,
    required this.target,
    this.widthCm = 10,
    required this.models,
  });

  factory ArVue.fromJson(Map<String, dynamic> json) {
    return ArVue(
      id: json['id'] as String,
      name: json['name'] as String,
      target: json['target'] as String,
      widthCm: (json['widthCm'] as num?)?.toInt() ?? 10,
      models: List<String>.from(json['models'] as List),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'widthCm': widthCm,
        'models': models,
      };
}

class ArProject {
  final String code;
  final String pass;
  final String name;
  final String status;
  final DateTime downloadedAt;
  final List<ArVue> vues;
  final int version;
  final String updatedAt;

  const ArProject({
    required this.code,
    required this.pass,
    required this.name,
    required this.status,
    required this.downloadedAt,
    this.vues = const [],
    this.version = 1,
    this.updatedAt = '',
  });

  String get fullCode => '$code-$pass';

  /// Tous les métiers uniques extraits des noms de fichiers GLB.
  /// Format filename : CODE-METIER-HEXCOLOR.glb → avant-dernier segment séparé par '-'.
  List<String> get metiers {
    final set = <String>{};
    for (final vue in vues) {
      for (final filename in vue.models) {
        final metier = _extractMetier(filename);
        if (metier.isNotEmpty) set.add(metier);
      }
    }
    return set.toList();
  }

  factory ArProject.fromJson(Map<String, dynamic> json) {
    // Nouveau format avec vues
    final vuesJson = json['vues'] as List?;
    if (vuesJson != null) {
      return ArProject(
        code: json['code'] as String,
        pass: json['pass'] as String? ?? '',
        name: json['name'] as String,
        status: json['status'] as String? ?? 'synced',
        downloadedAt: DateTime.parse(json['downloadedAt'] as String),
        vues: vuesJson
            .map((v) => ArVue.fromJson(v as Map<String, dynamic>))
            .toList(),
        version: (json['version'] as num?)?.toInt() ?? 1,
        updatedAt: json['updatedAt'] as String? ?? '',
      );
    }
    // Ancien format (migration) — vues vides, projet à re-télécharger
    return ArProject(
      code: json['code'] as String,
      pass: json['pass'] as String? ?? '',
      name: json['name'] as String,
      status: json['status'] as String? ?? 'synced',
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      vues: const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'pass': pass,
        'name': name,
        'status': status,
        'downloadedAt': downloadedAt.toIso8601String(),
        'vues': vues.map((v) => v.toJson()).toList(),
        'version': version,
        'updatedAt': updatedAt,
      };
}

/// Extrait le métier depuis un nom de fichier GLB.
/// Format attendu : CODE[-PARTS]-METIER-HEXCOLOR.glb
/// → avant-dernier segment quand on split par '-'.
String _extractMetier(String filename) {
  final withoutExt =
      filename.endsWith('.glb') ? filename.substring(0, filename.length - 4) : filename;
  final parts = withoutExt.split('-');
  return parts.length >= 2 ? parts[parts.length - 2] : '';
}
