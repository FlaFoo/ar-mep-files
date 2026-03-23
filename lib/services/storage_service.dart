import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';

class StorageService {
  static const String _projectsKey = 'ar_projects';

  static Future<List<ArProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_projectsKey);
    if (data == null) return [];
    final List<dynamic> list = jsonDecode(data) as List;
    final projects = list
        .map((e) => ArProject.fromJson(e as Map<String, dynamic>))
        .toList();
    projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return projects;
  }

  static Future<void> saveProjects(List<ArProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final String data =
        jsonEncode(projects.map((p) => p.toJson()).toList());
    await prefs.setString(_projectsKey, data);
  }

  static Future<void> addProject(ArProject project) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.code == project.code);
    projects.add(project);
    await saveProjects(projects);
  }

  static Future<void> deleteProject(String code) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.code == code);
    await saveProjects(projects);
  }

  static Future<bool> projectExists(String code) async {
    final projects = await loadProjects();
    return projects.any((p) => p.code == code);
  }

  static Future<ArProject?> getProject(String code) async {
    final projects = await loadProjects();
    try {
      return projects.firstWhere((p) => p.code == code);
    } catch (e) {
      return null;
    }
  }

  static Future<void> updateProjectStatus(
      String code, String status) async {
    final projects = await loadProjects();
    final index = projects.indexWhere((p) => p.code == code);
    if (index != -1) {
      final p = projects[index];
      projects[index] = ArProject(
        code: p.code,
        pass: p.pass,
        name: p.name,
        status: status,
        downloadedAt: p.downloadedAt,
        vues: p.vues,
        version: p.version,
        updatedAt: p.updatedAt,
      );
      await saveProjects(projects);
    }
  }

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('language') ?? 'fr';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
  }
}
