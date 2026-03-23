package com.darwinconcept.arvision

import android.opengl.Matrix
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.nio.ShortBuffer

/** Un primitif glTF : positions + normals optionnels + indices (short ou int) */
data class GlbPrimitive(
    val positions: FloatBuffer,   // x,y,z par vertex (direct buffer, espace monde GLB)
    val normals: FloatBuffer?,    // x,y,z par vertex, peut être null
    val shortIndices: ShortBuffer?,
    val intIndices: IntBuffer?,
    val vertexCount: Int,
    val indexCount: Int
)

data class GlbModel(
    val primitives: List<GlbPrimitive>,
    val yMin: Float = 0f,
    val xCenter: Float = 0f,
    val yCenter: Float = 0f
)

object GlbParser {

    private const val TAG = "GlbParser"

    private const val GLB_MAGIC       = 0x46546C67
    private const val CHUNK_TYPE_JSON = 0x4E4F534A
    private const val CHUNK_TYPE_BIN  = 0x004E4942

    private const val CT_UNSIGNED_BYTE  = 5121
    private const val CT_UNSIGNED_SHORT = 5123
    private const val CT_UNSIGNED_INT   = 5125
    private const val CT_FLOAT          = 5126

    fun parse(filePath: String): GlbModel? {
        return try {
            parseBytes(File(filePath).readBytes())
        } catch (e: Exception) {
            Log.e(TAG, "Échec parsing GLB : $filePath", e)
            null
        }
    }

    private fun parseBytes(bytes: ByteArray): GlbModel? {
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        if (buf.int != GLB_MAGIC) { Log.e(TAG, "Pas un fichier GLB"); return null }
        buf.int // version
        buf.int // totalLength

        val jsonLen  = buf.int
        val jsonType = buf.int
        if (jsonType != CHUNK_TYPE_JSON) { Log.e(TAG, "Chunk 0 n'est pas JSON"); return null }
        val jsonBytes = ByteArray(jsonLen).also { buf.get(it) }
        val json = JSONObject(String(jsonBytes, Charsets.UTF_8))

        if (buf.remaining() < 8) { Log.e(TAG, "Pas de chunk BIN"); return null }
        val binLen  = buf.int
        val binType = buf.int
        if (binType != CHUNK_TYPE_BIN) { Log.e(TAG, "Chunk 1 n'est pas BIN"); return null }
        val binData = ByteArray(binLen).also { buf.get(it) }

        return buildModel(json, binData)
    }

    private fun buildModel(json: JSONObject, bin: ByteArray): GlbModel {
        val accessors   = json.optJSONArray("accessors")   ?: return GlbModel(emptyList())
        val bufferViews = json.optJSONArray("bufferViews") ?: return GlbModel(emptyList())
        val meshesArr   = json.optJSONArray("meshes")      ?: return GlbModel(emptyList())
        val nodesArr    = json.optJSONArray("nodes")

        val primitives = mutableListOf<GlbPrimitive>()
        val identity   = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

        if (nodesArr != null) {
            // Cherche les nœuds racines depuis la scène active
            val sceneIdx  = json.optInt("scene", 0)
            val rootNodes = json.optJSONArray("scenes")
                ?.optJSONObject(sceneIdx)
                ?.optJSONArray("nodes")

            if (rootNodes != null) {
                for (i in 0 until rootNodes.length()) {
                    traverseNode(
                        rootNodes.getInt(i), nodesArr, meshesArr,
                        accessors, bufferViews, bin, identity, primitives
                    )
                }
            } else {
                // Pas de scène — traite tous les nœuds avec mesh
                for (i in 0 until nodesArr.length()) {
                    val node = nodesArr.getJSONObject(i)
                    if (node.has("mesh")) {
                        val t = nodeTransform(node)
                        addMeshPrimitives(meshesArr.getJSONObject(node.getInt("mesh")),
                            accessors, bufferViews, bin, t, primitives)
                    }
                }
            }
        } else {
            // Pas de nœuds — lecture directe des meshes (comportement de repli)
            for (mi in 0 until meshesArr.length()) {
                addMeshPrimitives(meshesArr.getJSONObject(mi),
                    accessors, bufferViews, bin, identity, primitives)
            }
        }

        // BBox globale pour xCenter/yCenter
        var xMin = Float.MAX_VALUE; var xMax = -Float.MAX_VALUE
        var yMin = Float.MAX_VALUE; var yMax = -Float.MAX_VALUE
        for (prim in primitives) {
            val pos = prim.positions
            pos.position(0)
            while (pos.hasRemaining()) {
                val x = pos.get(); val y = pos.get(); pos.get()
                if (x < xMin) xMin = x; if (x > xMax) xMax = x
                if (y < yMin) yMin = y; if (y > yMax) yMax = y
            }
            pos.position(0)
        }
        if (yMin == Float.MAX_VALUE) { xMin = 0f; xMax = 0f; yMin = 0f; yMax = 0f }
        val xCenter = (xMin + xMax) / 2f
        val yCenter = (yMin + yMax) / 2f

        Log.d(TAG, "GLB parsé : ${primitives.size} primitifs, BBox X[$xMin..$xMax] Y[$yMin..$yMax]")
        return GlbModel(primitives, yMin, xCenter, yCenter)
    }

    // ── Traversée récursive des nœuds ────────────────────────────────────────

    private fun traverseNode(
        nodeIdx: Int,
        nodes: JSONArray,
        meshes: JSONArray,
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteArray,
        parentTransform: FloatArray,
        primitives: MutableList<GlbPrimitive>
    ) {
        val node = nodes.getJSONObject(nodeIdx)
        val local = nodeTransform(node)
        val world = FloatArray(16)
        Matrix.multiplyMM(world, 0, parentTransform, 0, local, 0)

        val meshIdx = node.optInt("mesh", -1)
        if (meshIdx >= 0) {
            addMeshPrimitives(meshes.getJSONObject(meshIdx),
                accessors, bufferViews, bin, world, primitives)
        }

        val children = node.optJSONArray("children") ?: return
        for (ci in 0 until children.length()) {
            traverseNode(children.getInt(ci), nodes, meshes,
                accessors, bufferViews, bin, world, primitives)
        }
    }

    // ── Calcul du transform local d'un nœud (matrix ou TRS) ─────────────────

    private fun nodeTransform(node: JSONObject): FloatArray {
        val m = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

        // Option 1 : matrice 4×4 explicite (column-major glTF)
        val matArr = node.optJSONArray("matrix")
        if (matArr != null && matArr.length() == 16) {
            for (i in 0 until 16) m[i] = matArr.getDouble(i).toFloat()
            return m
        }

        // Option 2 : TRS — local = T * R * S
        val t = node.optJSONArray("translation")
        val r = node.optJSONArray("rotation")
        val s = node.optJSONArray("scale")

        // On construit T * R * S en partant de l'identité et en post-multipliant
        if (t != null && t.length() >= 3) {
            Matrix.translateM(m, 0,
                t.getDouble(0).toFloat(),
                t.getDouble(1).toFloat(),
                t.getDouble(2).toFloat())
        }
        if (r != null && r.length() >= 4) {
            val qx = r.getDouble(0).toFloat(); val qy = r.getDouble(1).toFloat()
            val qz = r.getDouble(2).toFloat(); val qw = r.getDouble(3).toFloat()
            val rotM = quaternionToMatrix(qx, qy, qz, qw)
            val tmp = FloatArray(16)
            Matrix.multiplyMM(tmp, 0, m, 0, rotM, 0)
            tmp.copyInto(m)
        }
        if (s != null && s.length() >= 3) {
            Matrix.scaleM(m, 0,
                s.getDouble(0).toFloat(),
                s.getDouble(1).toFloat(),
                s.getDouble(2).toFloat())
        }
        return m
    }

    /** Quaternion (x,y,z,w) → matrice rotation 4×4 column-major */
    private fun quaternionToMatrix(qx: Float, qy: Float, qz: Float, qw: Float): FloatArray {
        val m = FloatArray(16)
        m[0]  = 1f - 2f*(qy*qy + qz*qz);  m[4]  = 2f*(qx*qy - qz*qw);        m[8]  = 2f*(qx*qz + qy*qw);        m[12] = 0f
        m[1]  = 2f*(qx*qy + qz*qw);        m[5]  = 1f - 2f*(qx*qx + qz*qz);  m[9]  = 2f*(qy*qz - qx*qw);        m[13] = 0f
        m[2]  = 2f*(qx*qz - qy*qw);        m[6]  = 2f*(qy*qz + qx*qw);        m[10] = 1f - 2f*(qx*qx + qy*qy);  m[14] = 0f
        m[3]  = 0f;                          m[7]  = 0f;                          m[11] = 0f;                          m[15] = 1f
        return m
    }

    // ── Ajout des primitifs d'un mesh avec transform monde appliqué ──────────

    private fun addMeshPrimitives(
        mesh: JSONObject,
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteArray,
        worldTransform: FloatArray,
        primitives: MutableList<GlbPrimitive>
    ) {
        val prims = mesh.optJSONArray("primitives") ?: return
        val applyT = !isIdentity(worldTransform)

        for (pi in 0 until prims.length()) {
            val prim  = prims.getJSONObject(pi)
            val attrs = prim.optJSONObject("attributes") ?: continue

            val posIdx = attrs.optInt("POSITION", -1)
            if (posIdx < 0) continue

            val posRaw = readVec3Float(accessors.getJSONObject(posIdx), bufferViews, bin) ?: continue
            val vertexCount = accessors.getJSONObject(posIdx).getInt("count")

            val positions = if (applyT) applyTransformToPositions(posRaw, vertexCount, worldTransform)
                            else posRaw

            val normals = attrs.optInt("NORMAL", -1).let { idx ->
                if (idx >= 0) {
                    val raw = readVec3Float(accessors.getJSONObject(idx), bufferViews, bin)
                    if (raw != null && applyT) applyTransformToNormals(raw, vertexCount, worldTransform)
                    else raw
                } else null
            }

            val indicesIdx = prim.optInt("indices", -1)
            var shortBuf: ShortBuffer? = null
            var intBuf: IntBuffer?     = null
            var indexCount = 0

            if (indicesIdx >= 0) {
                val acc   = accessors.getJSONObject(indicesIdx)
                val count = acc.getInt("count")
                indexCount = count
                val offset = resolveOffset(acc, bufferViews)

                when (acc.getInt("componentType")) {
                    CT_UNSIGNED_SHORT -> {
                        val bb = ByteBuffer.allocateDirect(count * 2).order(ByteOrder.LITTLE_ENDIAN)
                        bb.put(bin, offset, count * 2); bb.position(0)
                        shortBuf = bb.asShortBuffer()
                    }
                    CT_UNSIGNED_INT -> {
                        val bb = ByteBuffer.allocateDirect(count * 4).order(ByteOrder.LITTLE_ENDIAN)
                        bb.put(bin, offset, count * 4); bb.position(0)
                        intBuf = bb.asIntBuffer()
                    }
                    CT_UNSIGNED_BYTE -> {
                        val bb = ByteBuffer.allocateDirect(count * 2).order(ByteOrder.LITTLE_ENDIAN)
                        val sbuf = bb.asShortBuffer()
                        for (i in 0 until count) sbuf.put((bin[offset + i].toInt() and 0xFF).toShort())
                        sbuf.position(0); shortBuf = sbuf
                    }
                }
            }

            val actualNormals = normals
                ?: computeSmoothNormals(positions, shortBuf, intBuf, vertexCount,
                                       if (indicesIdx >= 0) indexCount else vertexCount)
            primitives.add(
                GlbPrimitive(
                    positions    = positions,
                    normals      = actualNormals,
                    shortIndices = shortBuf,
                    intIndices   = intBuf,
                    vertexCount  = vertexCount,
                    indexCount   = if (indicesIdx >= 0) indexCount else vertexCount
                )
            )
        }
    }

    /** Applique la partie rotation 3×3 d'une matrice monde aux normales, puis renormalise */
    private fun applyTransformToNormals(src: FloatBuffer, count: Int, m: FloatArray): FloatBuffer {
        val bb  = ByteBuffer.allocateDirect(count * 12).order(ByteOrder.nativeOrder())
        val dst = bb.asFloatBuffer()
        src.position(0)
        for (i in 0 until count) {
            val x = src.get(); val y = src.get(); val z = src.get()
            var nx = m[0]*x + m[4]*y + m[8]*z
            var ny = m[1]*x + m[5]*y + m[9]*z
            var nz = m[2]*x + m[6]*y + m[10]*z
            val len = Math.sqrt((nx*nx + ny*ny + nz*nz).toDouble()).toFloat()
            val l = if (len > 1e-6f) len else 1f
            dst.put(nx/l); dst.put(ny/l); dst.put(nz/l)
        }
        src.position(0); dst.position(0)
        return dst
    }

    /** Applique une matrice monde 4×4 (column-major) à un FloatBuffer de positions */
    private fun applyTransformToPositions(src: FloatBuffer, count: Int, m: FloatArray): FloatBuffer {
        val bb  = ByteBuffer.allocateDirect(count * 12).order(ByteOrder.nativeOrder())
        val dst = bb.asFloatBuffer()
        src.position(0)
        for (i in 0 until count) {
            val x = src.get(); val y = src.get(); val z = src.get()
            dst.put(m[0]*x + m[4]*y + m[8]*z  + m[12])
            dst.put(m[1]*x + m[5]*y + m[9]*z  + m[13])
            dst.put(m[2]*x + m[6]*y + m[10]*z + m[14])
        }
        src.position(0); dst.position(0)
        return dst
    }

    private fun isIdentity(m: FloatArray): Boolean =
        m[0]==1f && m[5]==1f && m[10]==1f && m[15]==1f &&
        m[1]==0f && m[2]==0f && m[3]==0f &&
        m[4]==0f && m[6]==0f && m[7]==0f &&
        m[8]==0f && m[9]==0f && m[11]==0f &&
        m[12]==0f && m[13]==0f && m[14]==0f

    // ── Calcul de normales lissées ────────────────────────────────────────────

    private fun computeSmoothNormals(
        positions: FloatBuffer,
        shortIndices: ShortBuffer?,
        intIndices: IntBuffer?,
        vertexCount: Int,
        indexCount: Int
    ): FloatBuffer? {
        if (vertexCount == 0 || indexCount == 0) return null

        val pos = FloatArray(vertexCount * 3)
        positions.position(0); positions.get(pos); positions.position(0)

        val idx = IntArray(indexCount)
        when {
            shortIndices != null -> {
                shortIndices.position(0)
                for (i in 0 until indexCount) idx[i] = shortIndices.get().toInt() and 0xFFFF
                shortIndices.position(0)
            }
            intIndices != null -> {
                intIndices.position(0)
                for (i in 0 until indexCount) idx[i] = intIndices.get()
                intIndices.position(0)
            }
            else -> for (i in 0 until indexCount) idx[i] = i
        }

        val accum = FloatArray(vertexCount * 3)
        var t = 0
        while (t + 2 < indexCount) {
            val i0 = idx[t]; val i1 = idx[t + 1]; val i2 = idx[t + 2]; t += 3
            val ax = pos[i1*3]-pos[i0*3]; val ay = pos[i1*3+1]-pos[i0*3+1]; val az = pos[i1*3+2]-pos[i0*3+2]
            val bx = pos[i2*3]-pos[i0*3]; val by = pos[i2*3+1]-pos[i0*3+1]; val bz = pos[i2*3+2]-pos[i0*3+2]
            val nx = ay*bz - az*by; val ny = az*bx - ax*bz; val nz = ax*by - ay*bx
            for (i in intArrayOf(i0, i1, i2)) {
                accum[i*3] += nx; accum[i*3+1] += ny; accum[i*3+2] += nz
            }
        }

        val bb  = ByteBuffer.allocateDirect(vertexCount * 12).order(ByteOrder.nativeOrder())
        val out = bb.asFloatBuffer()
        for (i in 0 until vertexCount) {
            val nx = accum[i*3]; val ny = accum[i*3+1]; val nz = accum[i*3+2]
            val len = Math.sqrt((nx*nx + ny*ny + nz*nz).toDouble()).toFloat()
            val l = if (len > 1e-6f) len else 1f
            out.put(nx/l); out.put(ny/l); out.put(nz/l)
        }
        out.position(0)
        return out
    }

    // ── Lecture accesseurs ────────────────────────────────────────────────────

    private fun readVec3Float(acc: JSONObject, bufferViews: JSONArray, bin: ByteArray): FloatBuffer? {
        if (acc.getInt("componentType") != CT_FLOAT) return null
        val count      = acc.getInt("count")
        val bvIdx      = acc.optInt("bufferView", -1)
        if (bvIdx < 0) return null
        val bv         = bufferViews.getJSONObject(bvIdx)
        val bvOffset   = bv.optInt("byteOffset", 0)
        val accOffset  = acc.optInt("byteOffset", 0)
        val byteStride = bv.optInt("byteStride", 0)
        val stride     = if (byteStride > 0) byteStride else 12
        val dataStart  = bvOffset + accOffset

        val bb  = ByteBuffer.allocateDirect(count * 12).order(ByteOrder.nativeOrder())
        val dst = bb.asFloatBuffer()
        val src = ByteBuffer.wrap(bin).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until count) {
            src.position(dataStart + i * stride)
            dst.put(src.float); dst.put(src.float); dst.put(src.float)
        }
        dst.position(0)
        return dst
    }

    private fun resolveOffset(acc: JSONObject, bufferViews: JSONArray): Int {
        val bvIdx = acc.optInt("bufferView", -1)
        val bvOffset = if (bvIdx >= 0) bufferViews.getJSONObject(bvIdx).optInt("byteOffset", 0) else 0
        return bvOffset + acc.optInt("byteOffset", 0)
    }
}
