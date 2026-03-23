package com.darwinconcept.arvision

import android.os.Bundle
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Session
import com.google.ar.core.Config
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.BitmapFactory
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.darwinconcept.arvision/arcore"
    private var arSession: Session? = null
    private var arCoreInstallRequested = false
    private var arCameraView: ArCameraView? = null
    private var vuesData: Map<String, VuePaths> = emptyMap()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "ar_camera_view",
            ArCameraViewFactory(
                session = { arSession },
                onViewCreated = { view ->
                    arCameraView = view
                    // Si les données de vues sont déjà disponibles, les transmettre
                    if (vuesData.isNotEmpty()) view.setVues(vuesData)
                }
            )
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkArCoreAvailability" -> checkArCoreAvailability(result)
                "initArSession" -> initArSession(result)
                "closeArSession" -> closeArSession(result)
                "setVues" -> {
                    val vuesRaw = call.argument<List<Map<String, Any>>>("vues") ?: emptyList()
                    val map = mutableMapOf<String, VuePaths>()
                    for (vue in vuesRaw) {
                        val id = vue["id"] as? String ?: continue
                        val targetPath = vue["targetPath"] as? String ?: ""
                        val modelPaths = (vue["modelPaths"] as? List<*>)
                            ?.filterIsInstance<String>() ?: emptyList()
                        val widthCm = (vue["widthCm"] as? Int) ?: 10
                        map[id] = VuePaths(targetPath, modelPaths, widthCm)
                    }
                    vuesData = map
                    arSession?.let { configureSessionWithVues(it, vuesData) }
                    arCameraView?.setVues(vuesData)
                    android.util.Log.d("ArMEP", "setVues: ${map.size} vues reçues: ${map.keys.toList()}")
                    result.success("ok")
                }
                "preloadModels" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    GlbModelCache.preload(paths)
                    result.success("ok")
                }
                "getCachedCount" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val count = paths.count { GlbModelCache.has(it) }
                    result.success(count)
                }
                "getRecenteredVues" -> {
                    val ready = arCameraView?.getRecenteredVues() ?: emptyList<String>()
                    result.success(ready)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkArCoreAvailability(result: MethodChannel.Result) {
        val availability = ArCoreApk.getInstance().checkAvailability(this)
        when {
            availability.isSupported -> result.success("supported")
            availability.isTransient -> result.success("transient")
            else -> result.success("unsupported")
        }
    }

    private fun initArSession(result: MethodChannel.Result) {
        try {
            if (arSession == null) {
                val installStatus = ArCoreApk.getInstance()
                    .requestInstall(this, !arCoreInstallRequested)
                if (installStatus == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                    arCoreInstallRequested = true
                    result.success("install_requested")
                    return
                }
                arSession = Session(this)
                configureSessionWithVues(arSession!!, vuesData)
            }
            arSession!!.resume()
            result.success("ok")
        } catch (e: UnavailableArcoreNotInstalledException) {
            result.error("ARCORE_NOT_INSTALLED", "ARCore non installé", null)
        } catch (e: UnavailableDeviceNotCompatibleException) {
            result.error("DEVICE_NOT_COMPATIBLE", "Appareil incompatible", null)
        } catch (e: Exception) {
            result.error("ARCORE_ERROR", e.message, null)
        }
    }

    /**
     * Configure la session ARCore avec toutes les images cibles des vues.
     * Chaque vue est enregistrée dans l'AugmentedImageDatabase avec son id comme nom.
     */
    private fun configureSessionWithVues(session: Session, vues: Map<String, VuePaths>) {
        val config = Config(session)
        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        config.focusMode = Config.FocusMode.AUTO
        config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
        config.lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY

        val db = AugmentedImageDatabase(session)
        var imagesAdded = 0

        for ((id, vue) in vues) {
            if (vue.targetPath.isEmpty()) continue
            val file = File(vue.targetPath)
            if (!file.exists()) {
                android.util.Log.w("ArMEP", "Cible introuvable pour vue '$id': ${vue.targetPath}")
                continue
            }
            try {
                val bitmap = BitmapFactory.decodeFile(vue.targetPath) ?: continue
                val widthM = vue.widthCm / 100f
                val index = db.addImage(id, bitmap, widthM)
                android.util.Log.d("ArMEP", "Image cible '$id' ajoutée (index=$index, widthM=$widthM)")
                imagesAdded++
            } catch (e: Exception) {
                android.util.Log.e("ArMEP", "Erreur ajout image '$id': ${e.message}")
            }
        }

        if (imagesAdded > 0) {
            config.augmentedImageDatabase = db
        }

        session.configure(config)
        android.util.Log.d("ArMEP", "Session configurée avec $imagesAdded image(s) cible(s)")
    }

    private fun closeArSession(result: MethodChannel.Result) {
        arSession?.pause()
        arSession?.close()
        arSession = null
        vuesData = emptyMap() // Éviter les données périmées au prochain lancement
        result.success("ok")
    }

    override fun onPause() {
        super.onPause()
        arCameraView?.pause()
        arSession?.pause()
    }

    override fun onResume() {
        super.onResume()
        try {
            arSession?.resume()
            arCameraView?.resume()
        } catch (e: Exception) {
            // ignore
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        arCameraView?.pause()
        arSession?.close()
        arSession = null
    }
}
