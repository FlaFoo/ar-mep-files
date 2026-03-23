package com.darwinconcept.arvision

import android.content.Context
import com.google.android.filament.Engine
import com.google.android.filament.utils.ModelViewer
import com.google.ar.core.Frame
import java.io.File
import java.nio.ByteBuffer

class GlbRenderer(private val context: Context) {

    private var engine: Engine? = null
    private var modelViewer: ModelViewer? = null
    private var initialized = false

    fun init() {
        try {
            engine = Engine.create()
            initialized = true
        } catch (e: Exception) {
            initialized = false
        }
    }

    fun loadGlb(filePath: String) {
        if (!initialized) return
        try {
            val file = File(filePath)
            if (!file.exists()) return
            val buffer = ByteBuffer.wrap(file.readBytes())
            modelViewer?.loadModelGlb(buffer)
            modelViewer?.transformToUnitCube()
        } catch (e: Exception) {
            // Ignore
        }
    }

    fun destroy() {
        try {
            modelViewer = null
            engine?.destroy()
            engine = null
        } catch (e: Exception) {
            // Ignore
        }
        initialized = false
    }
}
