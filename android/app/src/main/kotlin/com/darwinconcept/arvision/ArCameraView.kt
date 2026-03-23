package com.darwinconcept.arvision

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.exceptions.CameraNotAvailableException
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/** Données d'une vue AR : chemin de la cible + chemins des GLB + largeur cible en cm. */
data class VuePaths(
    val targetPath: String,
    val modelPaths: List<String>,
    val widthCm: Int = 10
)

class ArCameraViewFactory(
    private val session: () -> Session?,
    private val onViewCreated: (ArCameraView) -> Unit = {}
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArCameraView(context, session).also { onViewCreated(it) }
    }
}

class ArCameraView(
    context: Context,
    private val getSession: () -> Session?
) : PlatformView, GLSurfaceView.Renderer {

    private val glSurfaceView: GLSurfaceView = GLSurfaceView(context)
    private val displayRotationHelper = DisplayRotationHelper(context)
    private val backgroundRenderer = BackgroundRenderer()
    private var surfaceCreated = false

    // Données des vues : vueId → chemins cible + modèles
    @Volatile private var vuesData: Map<String, VuePaths> = emptyMap()

    // Modèles chargés par vue : vueId → (chemin → modèle recentré)
    @Volatile private var loadedModelsByVue: Map<String, Map<String, GlbModel>> = emptyMap()

    // Paramètres de position par vue : vueId → (offsetX, offsetY, targetScale)
    private val targetParamsByVue = mutableMapOf<String, Triple<Float, Float, Int>>()

    // Chemins déjà tentés (succès ou échec) pour éviter les doubles chargements
    @Volatile private var attemptedPaths: Set<String> = emptySet()
    @Volatile private var isLoading = false

    // Vues dont les modèles ont déjà été recentrés
    @Volatile private var recenteredVues: Set<String> = emptySet()

    // Vue actuellement affichée (= dernière image ARCore détectée)
    private var activeVueId: String? = null

    // Ancre SLAM courante + dernière pose valide par vue
    private var renderAnchor: Anchor? = null
    private val lastValidPoseByVue = mutableMapOf<String, Pose>()

    // Cache matrices proj/view
    private val lastProjMatrix = FloatArray(16)
    private val lastViewMatrix = FloatArray(16)
    private var hasValidMatrices = false

    init {
        glSurfaceView.preserveEGLContextOnPause = true
        glSurfaceView.setEGLContextClientVersion(3)
        glSurfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glSurfaceView.setRenderer(this)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
    }

    override fun getView(): View = glSurfaceView

    override fun dispose() {
        renderAnchor?.detach()
        renderAnchor = null
        glSurfaceView.onPause()
    }

    /** Retourne les IDs des vues dont les modèles sont recentrés et prêts à l'affichage. */
    fun getRecenteredVues(): List<String> = recenteredVues.toList()

    /** Met à jour les données de toutes les vues et réinitialise l'état de rendu. */
    fun setVues(data: Map<String, VuePaths>) {
        vuesData = data

        // Extraire les paramètres de position depuis le nom de fichier de chaque cible
        targetParamsByVue.clear()
        for ((id, vue) in data) {
            val filename = vue.targetPath.substringAfterLast("/")
            targetParamsByVue[id] = parseTargetParams(filename)
        }

        // Réinitialiser l'état de rendu
        loadedModelsByVue = emptyMap()
        attemptedPaths = emptySet()
        recenteredVues = emptySet()
        renderAnchor?.detach()
        renderAnchor = null
        activeVueId = null
        lastValidPoseByVue.clear()

        android.util.Log.d("ArMEP", "setVues: ${data.size} vues configurées: ${data.keys.toList()}")
    }

    /** Parse X/Y/S depuis le nom de fichier cible (ex: target_01_X0_Y0_S50.jpg). */
    private fun parseTargetParams(filename: String): Triple<Float, Float, Int> {
        val parts = filename.removeSuffix(".jpg").split("_")
        var x = 0f; var y = 0f; var s = 50
        for (part in parts) {
            when {
                part.startsWith("X") -> x = part.removePrefix("X").toFloatOrNull()?.div(100f) ?: 0f
                part.startsWith("Y") -> y = part.removePrefix("Y").toFloatOrNull()?.div(100f) ?: 0f
                part.startsWith("S") -> s = part.removePrefix("S").toIntOrNull() ?: 50
            }
        }
        return Triple(x, y, s)
    }

    /**
     * Déclenche le chargement des GLB non encore parsés (toutes les vues).
     * Appelé depuis onDrawFrame — ne lance qu'un seul thread à la fois.
     */
    private fun ensureModelsLoaded() {
        val vues = vuesData
        if (isLoading || vues.isEmpty()) return

        val newPaths = vues.values.flatMap { it.modelPaths }.filter { it !in attemptedPaths }
        if (newPaths.isEmpty()) return

        isLoading = true
        Thread {
            val newAttempted = attemptedPaths + newPaths

            // Parser les nouveaux modèles (cache en priorité)
            val newlyParsed = mutableMapOf<String, GlbModel>()
            for (path in newPaths) {
                val model = GlbModelCache.get(path) ?: GlbParser.parse(path)?.also {
                    GlbModelCache.put(path, it)
                }
                if (model != null) {
                    newlyParsed[path] = model
                    logBoundingBox(path.substringAfterLast("/"), model)
                }
                val source = if (GlbModelCache.has(path)) "cache" else "disque"
                android.util.Log.d("ArMEP",
                    "GLB ($source): ${path.substringAfterLast("/")} → ${model?.primitives?.size ?: "ÉCHEC"} primitifs")
            }

            // Fusionner dans loadedModelsByVue et recenter par vue si possible
            val updatedByVue = loadedModelsByVue.toMutableMap()
            val updatedRecentered = recenteredVues.toMutableSet()

            for ((id, vue) in vues) {
                val existing = updatedByVue[id] ?: emptyMap()
                val merged = existing.toMutableMap()
                var changed = false

                for (path in vue.modelPaths) {
                    if (path in newlyParsed && path !in existing) {
                        merged[path] = newlyParsed[path]!!
                        changed = true
                    }
                }

                if (!changed) continue

                // Recenter dès que tous les chemins de cette vue ont été tentés
                val allAttempted = vue.modelPaths.all { it in newAttempted }
                if (allAttempted && id !in updatedRecentered && merged.isNotEmpty()) {
                    val scale = targetParamsByVue[id]?.third ?: 50
                    updatedByVue[id] = computeRecentered(merged, scale)
                    updatedRecentered.add(id)
                    android.util.Log.d("ArMEP", "Vue '$id' recentrée (${merged.size} modèles)")
                } else {
                    updatedByVue[id] = merged
                }
            }

            loadedModelsByVue = updatedByVue
            recenteredVues = updatedRecentered
            attemptedPaths = newAttempted
            isLoading = false
        }.start()
    }

    /**
     * Recentre les modèles d'une vue sur leur barycentre commun.
     * Scale baked : GLB en unités → mètres ARCore à l'échelle 1:S (× 0.5 correctif empirique).
     */
    private fun computeRecentered(
        models: Map<String, GlbModel>,
        targetScale: Int
    ): Map<String, GlbModel> {
        var gxMin = Float.MAX_VALUE; var gxMax = -Float.MAX_VALUE
        var gyMin = Float.MAX_VALUE; var gyMax = -Float.MAX_VALUE
        var gzMin = Float.MAX_VALUE; var gzMax = -Float.MAX_VALUE

        for (model in models.values) {
            for (prim in model.primitives) {
                prim.positions.position(0)
                while (prim.positions.hasRemaining()) {
                    val x = prim.positions.get(); val y = prim.positions.get(); val z = prim.positions.get()
                    if (x < gxMin) gxMin = x; if (x > gxMax) gxMax = x
                    if (y < gyMin) gyMin = y; if (y > gyMax) gyMax = y
                    if (z < gzMin) gzMin = z; if (z > gzMax) gzMax = z
                }
                prim.positions.position(0)
            }
        }

        val cx = (gxMin + gxMax) / 2f
        val cy = gyMin
        val cz = (gzMin + gzMax) / 2f
        val scale = 0.5f / targetScale.toFloat()
        android.util.Log.d("ArMEP", "recenter: cx=$cx cy=$cy cz=$cz scale=$scale  BBox X[$gxMin..$gxMax] Y[$gyMin..$gyMax] Z[$gzMin..$gzMax]")

        val recentered = mutableMapOf<String, GlbModel>()
        for ((path, model) in models) {
            val newPrims = model.primitives.map { prim ->
                val vertexCount = prim.vertexCount
                val newBuf = ByteBuffer.allocateDirect(vertexCount * 12)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer()
                prim.positions.position(0)
                repeat(vertexCount) {
                    newBuf.put((prim.positions.get() - cx) * scale)
                    newBuf.put((prim.positions.get() - cy) * scale)
                    newBuf.put((prim.positions.get() - cz) * scale)
                }
                newBuf.position(0)
                prim.positions.position(0)
                prim.copy(positions = newBuf)
            }
            recentered[path] = model.copy(primitives = newPrims, xCenter = 0f, yCenter = 0f)
        }
        return recentered
    }

    fun resume() {
        displayRotationHelper.onResume()
        glSurfaceView.onResume()
    }

    fun pause() {
        displayRotationHelper.onPause()
        glSurfaceView.onPause()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
        backgroundRenderer.createOnGlThread()
        GlbModelRenderer.reset()
        GlbModelRenderer.init()
        surfaceCreated = true
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = getSession() ?: return

        ensureModelsLoaded()

        try {
            session.setCameraTextureName(backgroundRenderer.textureId)
            displayRotationHelper.updateSessionIfNeeded(session)
            val frame = session.update()

            // 1. Fond caméra
            backgroundRenderer.draw(frame)

            val camera = frame.camera
            val projMatrix = FloatArray(16)
            val viewMatrix = FloatArray(16)

            if (camera.trackingState == TrackingState.TRACKING) {
                camera.getProjectionMatrix(projMatrix, 0, 0.01f, 100f)
                camera.getViewMatrix(viewMatrix, 0)
                System.arraycopy(projMatrix, 0, lastProjMatrix, 0, 16)
                System.arraycopy(viewMatrix, 0, lastViewMatrix, 0, 16)
                hasValidMatrices = true
            } else if (hasValidMatrices && activeVueId?.let { lastValidPoseByVue[it] } != null) {
                System.arraycopy(lastProjMatrix, 0, projMatrix, 0, 16)
                System.arraycopy(lastViewMatrix, 0, viewMatrix, 0, 16)
            } else {
                return
            }

            GLES20.glEnable(GLES20.GL_DEPTH_TEST)
            GLES20.glDepthMask(true)
            GLES20.glDepthFunc(GLES20.GL_LEQUAL)
            GLES20.glDisable(GLES20.GL_CULL_FACE)
            GLES20.glDisable(GLES20.GL_BLEND)

            // 2. Détection de la cible image → sélection de la vue active
            val allImages = frame.getUpdatedTrackables(AugmentedImage::class.java)
            val trackedImage = allImages.firstOrNull {
                it.trackingState == TrackingState.TRACKING
            }

            if (trackedImage != null) {
                val vueId = trackedImage.name

                // Changement de vue → reset ancre
                if (vueId != activeVueId) {
                    android.util.Log.d("ArMEP", "Vue détectée : '$vueId' (était '${activeVueId ?: "aucune"}')")
                    renderAnchor?.detach()
                    renderAnchor = null
                    activeVueId = vueId
                }

                val shouldCreate = renderAnchor == null ||
                                   renderAnchor?.trackingState == TrackingState.STOPPED
                if (shouldCreate) {
                    renderAnchor?.detach()
                    renderAnchor = trackedImage.createAnchor(trackedImage.centerPose)
                    android.util.Log.d("ArMEP", "Ancre créée pour '$vueId' method=${trackedImage.trackingMethod}")
                }
            }

            // 3. Pose à utiliser pour le rendu
            val currentVueId = activeVueId ?: return
            val poseToUse: Pose? = when (renderAnchor?.trackingState) {
                TrackingState.TRACKING -> {
                    renderAnchor!!.pose.also { lastValidPoseByVue[currentVueId] = it }
                }
                TrackingState.PAUSED -> {
                    renderAnchor!!.pose.also { lastValidPoseByVue[currentVueId] = it }
                }
                else -> lastValidPoseByVue[currentVueId]
            }

            if (poseToUse != null) drawAnchored(projMatrix, viewMatrix, poseToUse, currentVueId)

            GLES20.glDisable(GLES20.GL_DEPTH_TEST)

        } catch (e: CameraNotAvailableException) {
            // ignore
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun drawAnchored(
        projMatrix: FloatArray,
        viewMatrix: FloatArray,
        anchorPose: Pose,
        vueId: String
    ) {
        val vue = vuesData[vueId] ?: return

        // N'afficher les modèles que si le recentrage est terminé
        if (vueId !in recenteredVues) return

        val models = loadedModelsByVue[vueId]

        if (models.isNullOrEmpty()) return

        val params = targetParamsByVue[vueId] ?: Triple(0f, 0f, 50)
        val modelPose = anchorPose
            .compose(Pose.makeTranslation(params.first, 0f, -params.second))
        val poseMatrix = FloatArray(16)
        modelPose.toMatrix(poseMatrix, 0)

        for (path in vue.modelPaths) {
            val model = models[path] ?: continue
            val color = extractColorFromPath(path)
            GlbModelRenderer.drawModel(model, projMatrix, viewMatrix, poseMatrix, color, 1.0f)
        }
    }

    private fun logBoundingBox(filename: String, model: GlbModel) {
        // Désactivé en production — décommenter pour débogage géométrie
    }

    private fun extractColorFromPath(path: String): FloatArray {
        val filename = path.substringAfterLast("/")
        val hex = filename.substringAfterLast("-").removeSuffix(".glb")
        return try {
            val r = hex.substring(0, 2).toInt(16) / 255f
            val g = hex.substring(2, 4).toInt(16) / 255f
            val b = hex.substring(4, 6).toInt(16) / 255f
            floatArrayOf(r, g, b, 1f)
        } catch (e: Exception) {
            floatArrayOf(0.6f, 0.2f, 0.8f, 1f)
        }
    }
}
