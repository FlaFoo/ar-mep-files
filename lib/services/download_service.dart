import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';

class DownloadService {
  static const String _baseUrl =
      'https://raw.githubusercontent.com/FlaFoo/ar-mep-files/main/projects';

  // Récupère le manifest depuis GitHub
  static Future<Map<String, dynamic>?> fetchManifest(
      String code, String pass) async {
    final fullCode = '$code-$pass';
    final url = '$_baseUrl/$fullCode/manifest.json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Télécharge tous les fichiers d'un projet (GLB + images cibles) depuis la liste de vues
  static Future<bool> downloadProjectFiles(
      String code,
      String pass,
      List<ArVue> vues,
      Function(int current, int total, String filename) onProgress) async {
    final fullCode = '$code-$pass';
    final dir = await _projectDirectory(fullCode);

    // Collecte les fichiers uniques à télécharger
    final allModels = <String>{};
    final allTargets = <String>{};
    for (final vue in vues) {
      allModels.addAll(vue.models);
      allTargets.add(vue.target);
    }

    final totalFiles = allModels.length + allTargets.length;
    int current = 0;

    // --- Téléchargement des GLB ---
    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

    for (final filename in allModels) {
      final url = '$_baseUrl/$fullCode/models/$filename';
      final file = File('${modelsDir.path}/$filename');
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
        } else {
          debugPrint('[Download] HTTP ${response.statusCode} for model $filename');
        }
      } catch (e) {
        debugPrint('[Download] Error downloading model $filename: $e');
      }
      current++;
      onProgress(current, totalFiles, filename);
    }

    // --- Téléchargement des images cibles ---
    final targetsDir = Directory('${dir.path}/targets');
    if (!await targetsDir.exists()) await targetsDir.create(recursive: true);

    for (final filename in allTargets) {
      final url = '$_baseUrl/$fullCode/targets/$filename';
      final file = File('${targetsDir.path}/$filename');
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
        } else {
          debugPrint('[Download] HTTP ${response.statusCode} for target $filename');
        }
      } catch (e) {
        debugPrint('[Download] Error downloading target $filename: $e');
      }
      current++;
      onProgress(current, totalFiles, filename);
    }

    return true;
  }

  // Retourne le chemin local d'un fichier GLB
  static Future<String?> localModelPath(
      String fullCode, String filename) async {
    final dir = await _projectDirectory(fullCode);
    final file = File('${dir.path}/models/$filename');
    if (await file.exists()) return file.path;
    return null;
  }

  // Retourne le chemin local d'une image cible
  static Future<String?> localTargetPath(
      String fullCode, String filename) async {
    final dir = await _projectDirectory(fullCode);
    final file = File('${dir.path}/targets/$filename');
    if (await file.exists()) return file.path;
    return null;
  }

  // Supprime les fichiers locaux d'un projet
  static Future<void> deleteProjectFiles(String fullCode) async {
    final dir = await _projectDirectory(fullCode);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // Répertoire local du projet
  static Future<Directory> _projectDirectory(String fullCode) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/projects/$fullCode');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String modelUrl(String fullCode, String filename) {
    return '$_baseUrl/$fullCode/models/$filename';
  }

  static String targetUrl(String fullCode, String filename) {
    return '$_baseUrl/$fullCode/targets/$filename';
  }
}
