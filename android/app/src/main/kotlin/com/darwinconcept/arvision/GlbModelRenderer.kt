package com.darwinconcept.arvision

import android.opengl.GLES20
import android.opengl.GLES30
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Rendu OpenGL ES 3.0 de modèles GLB parsés.
 * - Shader LIT (Lambert) quand les normales sont disponibles
 * - Shader FLAT (couleur unie) en fallback
 * Couleur passée depuis le nom de fichier GLB ({CODE}-{METIER}-{HEXRGB}.glb)
 */
object GlbModelRenderer {

    private var progLit  = 0
    private var progFlat = 0
    private var initialized = false
    private var debugCounter = 0

    // Handles — shader LIT
    private var litPosition  = 0
    private var litNormal    = 0
    private var litMVP       = 0
    private var litMV        = 0
    private var litColor     = 0
    private var litLightDir  = 0

    // Handles — shader FLAT
    private var flatPosition = 0
    private var flatMVP      = 0
    private var flatColor    = 0

    // ── ESSL 3.0 shaders ──────────────────────────────────────────────────────

    private val VS_LIT = """
        #version 300 es
        uniform mat4 uMVP;
        uniform mat4 uMV;
        in vec3 aPos;
        in vec3 aNorm;
        out vec3 vNorm;
        void main() {
            gl_Position = uMVP * vec4(aPos, 1.0);
            vNorm = mat3(uMV) * aNorm;
        }
    """.trimIndent()

    private val FS_LIT = """
        #version 300 es
        precision mediump float;
        uniform vec4 uColor;
        uniform vec3 uLightDir;
        in vec3 vNorm;
        out vec4 fragColor;
        void main() {
            vec3  n       = normalize(vNorm);
            float diff    = max(dot(n, normalize(uLightDir)), 0.0);
            float ambient = 0.35;
            float light   = ambient + (1.0 - ambient) * diff;
            fragColor = vec4(uColor.rgb * light, uColor.a);
        }
    """.trimIndent()

    private val VS_FLAT = """
        #version 300 es
        uniform mat4 uMVP;
        in vec3 aPos;
        void main() { gl_Position = uMVP * vec4(aPos, 1.0); }
    """.trimIndent()

    private val FS_FLAT = """
        #version 300 es
        precision mediump float;
        uniform vec4 uColor;
        out vec4 fragColor;
        void main() { fragColor = uColor; }
    """.trimIndent()

    // ── Initialisation (à appeler depuis onSurfaceCreated dans le thread GL) ──

    fun reset() { initialized = false }

    fun init() {
        if (initialized) return
        progLit  = buildProgram(VS_LIT,  FS_LIT)
        progFlat = buildProgram(VS_FLAT, FS_FLAT)

        litPosition = GLES20.glGetAttribLocation(progLit, "aPos")
        litNormal   = GLES20.glGetAttribLocation(progLit, "aNorm")
        litMVP      = GLES20.glGetUniformLocation(progLit, "uMVP")
        litMV       = GLES20.glGetUniformLocation(progLit, "uMV")
        litColor    = GLES20.glGetUniformLocation(progLit, "uColor")
        litLightDir = GLES20.glGetUniformLocation(progLit, "uLightDir")

        flatPosition = GLES20.glGetAttribLocation(progFlat, "aPos")
        flatMVP      = GLES20.glGetUniformLocation(progFlat, "uMVP")
        flatColor    = GLES20.glGetUniformLocation(progFlat, "uColor")

        android.util.Log.d("GlbRenderer", "Handles flat: pos=$flatPosition mvp=$flatMVP color=$flatColor")
        android.util.Log.d("GlbRenderer", "Handles lit:  pos=$litPosition norm=$litNormal mvp=$litMVP mv=$litMV")

        initialized = true
    }

    // ── Dessin d'un modèle complet ─────────────────────────────────────────────

    /**
     * @param model     Modèle parsé
     * @param proj      Matrice projection ARCore (FloatArray 16, column-major)
     * @param view      Matrice vue ARCore
     * @param pose      Matrice modèle issue de Pose.toMatrix() — position de l'ancre
     * @param color     RGBA [0..1] extrait du nom de fichier
     * @param scale     Facteur d'échelle (ex: 1/50 pour un plan S50)
     */
    fun drawModel(
        model: GlbModel,
        proj:  FloatArray,
        view:  FloatArray,
        pose:  FloatArray,
        color: FloatArray,
        scale: Float
    ) {
        if (!initialized) return

        // Matrice modèle = pose de l'ancre × scale uniforme
        val modelM = FloatArray(16).also { System.arraycopy(pose, 0, it, 0, 16) }
        Matrix.scaleM(modelM, 0, scale, scale, scale)

        val mv  = FloatArray(16)
        val mvp = FloatArray(16)
        Matrix.multiplyMM(mv,  0, view, 0, modelM, 0)
        Matrix.multiplyMM(mvp, 0, proj, 0, mv,     0)

        debugCounter++

        val lw = floatArrayOf(0.4f, 1.0f, 0.4f)
        val lightView = floatArrayOf(
            view[0]*lw[0] + view[4]*lw[1] + view[8]*lw[2],
            view[1]*lw[0] + view[5]*lw[1] + view[9]*lw[2],
            view[2]*lw[0] + view[6]*lw[1] + view[10]*lw[2]
        )
        for (prim in model.primitives) {
            if (prim.normals != null) drawLit(prim, mvp, mv, color, lightView)
            else drawFlat(prim, mvp, color)
        }

        val err = GLES20.glGetError()
        if (err != GLES20.GL_NO_ERROR) {
            android.util.Log.e("GlbRenderer", "GL error: 0x${err.toString(16)}")
        }
    }

    // ── Primitif avec éclairage Lambert ────────────────────────────────────────

    private fun drawLit(
        prim:     GlbPrimitive,
        mvp:      FloatArray,
        mv:       FloatArray,
        color:    FloatArray,
        lightDir: FloatArray
    ) {
        GLES20.glUseProgram(progLit)
        GLES20.glUniformMatrix4fv(litMVP, 1, false, mvp, 0)
        GLES20.glUniformMatrix4fv(litMV,  1, false, mv,  0)
        GLES20.glUniform4fv(litColor,    1, color,    0)
        GLES20.glUniform3fv(litLightDir, 1, lightDir, 0)

        prim.positions.position(0)
        GLES20.glVertexAttribPointer(litPosition, 3, GLES20.GL_FLOAT, false, 0, prim.positions)
        GLES20.glEnableVertexAttribArray(litPosition)

        prim.normals!!.position(0)
        GLES20.glVertexAttribPointer(litNormal, 3, GLES20.GL_FLOAT, false, 0, prim.normals)
        GLES20.glEnableVertexAttribArray(litNormal)

        drawElements(prim)

        GLES20.glDisableVertexAttribArray(litPosition)
        GLES20.glDisableVertexAttribArray(litNormal)
    }

    // ── Primitif flat (pas de normales) ────────────────────────────────────────

    private fun drawFlat(prim: GlbPrimitive, mvp: FloatArray, color: FloatArray) {
        GLES20.glUseProgram(progFlat)
        GLES20.glUniformMatrix4fv(flatMVP,  1, false, mvp, 0)
        GLES20.glUniform4fv(flatColor, 1, color, 0)

        prim.positions.position(0)
        GLES20.glVertexAttribPointer(flatPosition, 3, GLES20.GL_FLOAT, false, 0, prim.positions)
        GLES20.glEnableVertexAttribArray(flatPosition)

        drawElements(prim)

        GLES20.glDisableVertexAttribArray(flatPosition)
    }

    // ── Appel glDrawElements selon le type d'indices ───────────────────────────

    private fun drawElements(prim: GlbPrimitive) {
        when {
            prim.shortIndices != null -> {
                prim.shortIndices.position(0)
                GLES20.glDrawElements(
                    GLES20.GL_TRIANGLES, prim.indexCount,
                    GLES20.GL_UNSIGNED_SHORT, prim.shortIndices
                )
            }
            prim.intIndices != null -> {
                prim.intIndices.position(0)
                // GL_UNSIGNED_INT = 0x1405, supporté en ES 3.0
                GLES30.glDrawElements(
                    GLES30.GL_TRIANGLES, prim.indexCount,
                    GLES30.GL_UNSIGNED_INT, prim.intIndices
                )
            }
            else -> {
                GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, prim.vertexCount)
            }
        }
    }

    // ── Triangle de debug en clip space (toujours visible, ne dépend d'aucun MVP) ──

    fun drawDebugTriangle() {
        if (!initialized) return
        val verts = floatArrayOf(0f, 0.5f, 0f, -0.5f, -0.5f, 0f, 0.5f, -0.5f, 0f)
        val buf = ByteBuffer.allocateDirect(36).order(ByteOrder.nativeOrder()).asFloatBuffer()
            .apply { put(verts); position(0) }
        val identity = FloatArray(16).also { android.opengl.Matrix.setIdentityM(it, 0) }
        GLES20.glUseProgram(progFlat)
        GLES20.glUniformMatrix4fv(flatMVP, 1, false, identity, 0)
        GLES20.glUniform4fv(flatColor, 1, floatArrayOf(1f, 0f, 0f, 1f), 0)
        GLES20.glVertexAttribPointer(flatPosition, 3, GLES20.GL_FLOAT, false, 0, buf)
        GLES20.glEnableVertexAttribArray(flatPosition)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, 3)
        GLES20.glDisableVertexAttribArray(flatPosition)
    }

    // ── Marqueur 3D en espace monde (teste le vrai pipeline MVP) ──────────────
    // Dessine une croix verte de 20cm centrée sur la pose passée en paramètre.
    // Visible de n'importe quel angle : 2 quads perpendiculaires (XZ + XY).

    fun drawAnchorMarker(proj: FloatArray, view: FloatArray, anchorMatrix: FloatArray) {
        if (!initialized) return
        val h = 0.05f  // demi-côté 5cm → carré 10cm
        // Quad horizontal (plan XZ) : visible de dessus/dessous
        val vertsH = floatArrayOf(
            -h, 0f, -h,   h, 0f, -h,   h, 0f,  h,
            -h, 0f, -h,   h, 0f,  h,  -h, 0f,  h
        )
        // Quad vertical (plan XY) : visible de face/dos
        val vertsV = floatArrayOf(
            -h, -h, 0f,   h, -h, 0f,   h,  h, 0f,
            -h, -h, 0f,   h,  h, 0f,  -h,  h, 0f
        )
        val mv  = FloatArray(16)
        val mvp = FloatArray(16)
        Matrix.multiplyMM(mv,  0, view,  0, anchorMatrix, 0)
        Matrix.multiplyMM(mvp, 0, proj,  0, mv,           0)

        GLES20.glUseProgram(progFlat)
        GLES20.glUniformMatrix4fv(flatMVP, 1, false, mvp, 0)
        GLES20.glUniform4fv(flatColor, 1, floatArrayOf(0f, 1f, 0f, 1f), 0)  // vert vif

        for (verts in listOf(vertsH, vertsV)) {
            val buf = ByteBuffer.allocateDirect(verts.size * 4).order(ByteOrder.nativeOrder())
                .asFloatBuffer().apply { put(verts); position(0) }
            GLES20.glVertexAttribPointer(flatPosition, 3, GLES20.GL_FLOAT, false, 0, buf)
            GLES20.glEnableVertexAttribArray(flatPosition)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, verts.size / 3)
            GLES20.glDisableVertexAttribArray(flatPosition)
        }
        val err = GLES20.glGetError()
        if (err != GLES20.GL_NO_ERROR) android.util.Log.e("GlbRenderer", "anchorMarker GL error: 0x${err.toString(16)}")
    }

    // ── Compilation shader ─────────────────────────────────────────────────────

    private fun buildProgram(vsSource: String, fsSource: String): Int {
        val vs = compile(GLES20.GL_VERTEX_SHADER,   vsSource)
        val fs = compile(GLES20.GL_FRAGMENT_SHADER, fsSource)
        val p  = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, vs)
        GLES20.glAttachShader(p, fs)
        GLES20.glLinkProgram(p)
        val linked = IntArray(1)
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, linked, 0)
        if (linked[0] == 0) {
            android.util.Log.e("GlbRenderer", "Program link FAILED:\n${GLES20.glGetProgramInfoLog(p)}")
        } else {
            android.util.Log.d("GlbRenderer", "Program linked OK (id=$p)")
        }
        return p
    }

    private fun compile(type: Int, source: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, source)
        GLES20.glCompileShader(s)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            val typeName = if (type == GLES20.GL_VERTEX_SHADER) "VS" else "FS"
            android.util.Log.e("GlbRenderer", "Shader $typeName compile FAILED:\n${GLES20.glGetShaderInfoLog(s)}")
        }
        return s
    }
}
