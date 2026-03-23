package com.darwinconcept.arvision

import android.opengl.GLES11Ext
import android.opengl.GLES20
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

class BackgroundRenderer {

    var textureId = -1
        private set

    private var quadProgram = 0
    private var quadPositionAttrib = 0
    private var quadTexCoordAttrib = 0
    private var geometryChanged = false

    private val quadCoords = floatArrayOf(
        -1.0f, -1.0f,
         1.0f, -1.0f,
        -1.0f,  1.0f,
         1.0f,  1.0f,
    )

    private val quadTexCoords = floatArrayOf(
        0.0f, 0.0f,
        0.0f, 0.0f,
        0.0f, 0.0f,
        0.0f, 0.0f,
    )

    private lateinit var quadCoordsBuffer: FloatBuffer
    private lateinit var quadTexCoordsBuffer: FloatBuffer

    private val vertexShader = """
        #version 300 es
        in vec4 a_Position;
        in vec2 a_TexCoord;
        out vec2 v_TexCoord;
        void main() {
            gl_Position = a_Position;
            v_TexCoord = a_TexCoord;
        }
    """.trimIndent()

    private val fragmentShader = """
        #version 300 es
        #extension GL_OES_EGL_image_external_essl3 : require
        precision mediump float;
        in vec2 v_TexCoord;
        uniform samplerExternalOES sTexture;
        out vec4 fragColor;
        void main() {
            fragColor = texture(sTexture, v_TexCoord);
        }
    """.trimIndent()

    fun createOnGlThread() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        val vShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexShader)
        val fShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentShader)

        quadProgram = GLES20.glCreateProgram()
        GLES20.glAttachShader(quadProgram, vShader)
        GLES20.glAttachShader(quadProgram, fShader)
        GLES20.glLinkProgram(quadProgram)

        quadPositionAttrib = GLES20.glGetAttribLocation(quadProgram, "a_Position")
        quadTexCoordAttrib = GLES20.glGetAttribLocation(quadProgram, "a_TexCoord")

        quadCoordsBuffer = ByteBuffer
            .allocateDirect(quadCoords.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(quadCoords); position(0) }

        quadTexCoordsBuffer = ByteBuffer
            .allocateDirect(quadTexCoords.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(quadTexCoords); position(0) }

        geometryChanged = true
    }

    fun draw(frame: Frame) {
        if (frame.timestamp == 0L) return

        if (frame.hasDisplayGeometryChanged() || geometryChanged) {
            frame.transformCoordinates2d(
                Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                quadCoordsBuffer,
                Coordinates2d.TEXTURE_NORMALIZED,
                quadTexCoordsBuffer
            )
            geometryChanged = false
        }

        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUseProgram(quadProgram)

        GLES20.glVertexAttribPointer(
            quadPositionAttrib, 2, GLES20.GL_FLOAT, false, 0, quadCoordsBuffer)
        GLES20.glVertexAttribPointer(
            quadTexCoordAttrib, 2, GLES20.GL_FLOAT, false, 0, quadTexCoordsBuffer)

        GLES20.glEnableVertexAttribArray(quadPositionAttrib)
        GLES20.glEnableVertexAttribArray(quadTexCoordAttrib)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(quadPositionAttrib)
        GLES20.glDisableVertexAttribArray(quadTexCoordAttrib)

        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }
}
