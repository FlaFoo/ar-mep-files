package com.darwinconcept.arvision

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer

object SimpleModelRenderer {

    private var program = 0
    private var positionHandle = 0
    private var colorHandle = 0
    private var mvpHandle = 0
    private var initialized = false

    // Cube unitaire centré en 0 — l'échelle est appliquée via la matrice modèle
    private val cubeVertices = floatArrayOf(
        -1f, -1f,  1f,   1f, -1f,  1f,   1f,  1f,  1f,  -1f,  1f,  1f,
        -1f, -1f, -1f,   1f, -1f, -1f,   1f,  1f, -1f,  -1f,  1f, -1f,
    )

    private val cubeIndices = shortArrayOf(
        0,1,2, 0,2,3,
        4,6,5, 4,7,6,
        0,5,1, 0,4,5,
        2,6,7, 2,7,3,
        0,3,7, 0,7,4,
        1,5,6, 1,6,2,
    )

    private lateinit var vertexBuffer: FloatBuffer
    private lateinit var indexBuffer: ShortBuffer

    private val vertexShader = """
        uniform mat4 uMVPMatrix;
        attribute vec4 vPosition;
        void main() { gl_Position = uMVPMatrix * vPosition; }
    """.trimIndent()

    private val fragmentShader = """
        precision mediump float;
        uniform vec4 vColor;
        void main() { gl_FragColor = vColor; }
    """.trimIndent()

    private fun init() {
        if (initialized) return

        vertexBuffer = ByteBuffer
            .allocateDirect(cubeVertices.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(cubeVertices); position(0) }

        indexBuffer = ByteBuffer
            .allocateDirect(cubeIndices.size * 2)
            .order(ByteOrder.nativeOrder())
            .asShortBuffer()
            .apply { put(cubeIndices); position(0) }

        val vShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexShader)
        val fShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentShader)
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vShader)
        GLES20.glAttachShader(program, fShader)
        GLES20.glLinkProgram(program)

        positionHandle = GLES20.glGetAttribLocation(program, "vPosition")
        colorHandle    = GLES20.glGetUniformLocation(program, "vColor")
        mvpHandle      = GLES20.glGetUniformLocation(program, "uMVPMatrix")

        initialized = true
    }

    // Ancien appel — cubes flottants fixes (conservé pour compatibilité)
    fun draw(
        projMatrix: FloatArray,
        viewMatrix: FloatArray,
        color: FloatArray,
        x: Float, y: Float, z: Float
    ) {
        val modelMatrix = FloatArray(16)
        Matrix.setIdentityM(modelMatrix, 0)
        Matrix.translateM(modelMatrix, 0, x, y, z)
        Matrix.scaleM(modelMatrix, 0, 0.05f, 0.05f, 0.05f)
        drawWithModel(projMatrix, viewMatrix, modelMatrix, color)
    }

    // Nouvel appel — cube ancré sur une pose ARCore
    fun drawAtPose(
        projMatrix: FloatArray,
        viewMatrix: FloatArray,
        poseMatrix: FloatArray,   // matrice 4x4 issue de Pose.toMatrix()
        color: FloatArray,
        scale: Float,
        offsetX: Float = 0f,
        offsetY: Float = 0f
    ) {
        val modelMatrix = FloatArray(16)
        System.arraycopy(poseMatrix, 0, modelMatrix, 0, 16)

        // Appliquer offset et échelle
        Matrix.translateM(modelMatrix, 0, offsetX, offsetY, 0f)
        Matrix.scaleM(modelMatrix, 0, scale, scale, scale)

        drawWithModel(projMatrix, viewMatrix, modelMatrix, color)
    }

    private fun drawWithModel(
        projMatrix: FloatArray,
        viewMatrix: FloatArray,
        modelMatrix: FloatArray,
        color: FloatArray
    ) {
        init()

        val mvMatrix  = FloatArray(16)
        val mvpMatrix = FloatArray(16)
        Matrix.multiplyMM(mvMatrix,  0, viewMatrix, 0, modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projMatrix, 0, mvMatrix,    0)

        GLES20.glUseProgram(program)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 0, vertexBuffer)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glUniform4fv(colorHandle, 1, color, 0)
        GLES20.glUniformMatrix4fv(mvpHandle, 1, false, mvpMatrix, 0)
        GLES20.glDrawElements(GLES20.GL_TRIANGLES, cubeIndices.size, GLES20.GL_UNSIGNED_SHORT, indexBuffer)
        GLES20.glDisableVertexAttribArray(positionHandle)
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }
}