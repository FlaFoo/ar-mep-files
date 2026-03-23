import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/project.dart';

class ArCoreService {
  static const MethodChannel _channel =
      MethodChannel('com.darwinconcept.arvision/arcore');

  // Demande la permission caméra
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  // Vérifie si ARCore est disponible
  static Future<ArCoreStatus> checkAvailability() async {
    try {
      final String result =
          await _channel.invokeMethod('checkArCoreAvailability');
      switch (result) {
        case 'supported':
          return ArCoreStatus.supported;
        case 'transient':
          return ArCoreStatus.transient;
        default:
          return ArCoreStatus.unsupported;
      }
    } catch (e) {
      return ArCoreStatus.unsupported;
    }
  }

  // Initialise la session AR
  static Future<ArCoreInitResult> initSession() async {
    try {
      final String result = await _channel.invokeMethod('initArSession');
      switch (result) {
        case 'ok':
          return ArCoreInitResult.ok;
        case 'install_requested':
          return ArCoreInitResult.installRequested;
        default:
          return ArCoreInitResult.error;
      }
    } on PlatformException catch (e) {
      if (e.code == 'ARCORE_NOT_INSTALLED') {
        return ArCoreInitResult.notInstalled;
      } else if (e.code == 'DEVICE_NOT_COMPATIBLE') {
        return ArCoreInitResult.notCompatible;
      }
      return ArCoreInitResult.error;
    } catch (e) {
      return ArCoreInitResult.error;
    }
  }

  // Envoie toutes les vues à Android : chaque vue a une cible + des modèles GLB.
  // Les modèles peuvent être filtrés (visibilité par métier) avant l'appel.
  static Future<void> setVues(
      String code, String pass, List<ArVue> vues) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullCode = '$code-$pass';
      final basePath = '${appDir.path}/projects/$fullCode';

      final vuesList = <Map<String, dynamic>>[];
      for (final vue in vues) {
        final targetPath = '$basePath/targets/${vue.target}';
        if (!File(targetPath).existsSync()) {
          debugPrint('Cible manquante : $targetPath');
          continue;
        }
        final modelPaths = vue.models
            .map((f) => '$basePath/models/$f')
            .where((p) => File(p).existsSync())
            .toList();

        debugPrint('Vue ${vue.id}: target=$targetPath models=${modelPaths.length}');
        vuesList.add({
          'id': vue.id,
          'targetPath': targetPath,
          'modelPaths': modelPaths,
          'widthCm': vue.widthCm,
        });
      }

      await _channel.invokeMethod('setVues', {'vues': vuesList});
    } catch (e) {
      debugPrint('setVues error: $e');
    }
  }

  // Précharge les GLB d'un projet dans le cache Kotlin (arrière-plan)
  static Future<void> preloadModels(String code, String pass, List<ArVue> vues) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullCode = '$code-$pass';
      final basePath = '${appDir.path}/projects/$fullCode';
      final paths = vues
          .expand((v) => v.models)
          .map((f) => '$basePath/models/$f')
          .where((p) => File(p).existsSync())
          .toList();
      if (paths.isEmpty) return;
      await _channel.invokeMethod('preloadModels', {'paths': paths});
    } catch (e) {
      debugPrint('preloadModels error: $e');
    }
  }

  // Retourne le nombre de GLB déjà en cache pour un projet donné
  static Future<int> getCachedCount(String code, String pass, List<ArVue> vues) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullCode = '$code-$pass';
      final basePath = '${appDir.path}/projects/$fullCode';
      final paths = vues
          .expand((v) => v.models)
          .map((f) => '$basePath/models/$f')
          .where((p) => File(p).existsSync())
          .toList();
      if (paths.isEmpty) return 0;
      final int count =
          await _channel.invokeMethod('getCachedCount', {'paths': paths});
      return count;
    } catch (e) {
      return 0;
    }
  }

  // Retourne les IDs des vues dont les modèles sont prêts (recentrés)
  static Future<List<String>> getRecenteredVues() async {
    try {
      final List<dynamic> result =
          await _channel.invokeMethod('getRecenteredVues');
      return result.cast<String>();
    } catch (e) {
      return [];
    }
  }

  // Ferme la session AR
  static Future<void> closeSession() async {
    try {
      await _channel.invokeMethod('closeArSession');
    } catch (e) {
      // ignore
    }
  }
}

enum ArCoreStatus {
  supported,
  transient,
  unsupported,
}

enum ArCoreInitResult {
  ok,
  installRequested,
  notInstalled,
  notCompatible,
  error,
}
