package com.darwinconcept.arvision

/**
 * Cache singleton des modèles GLB parsés.
 * Évite de re-parser les fichiers à chaque ouverture de la vue AR.
 * Durée de vie : session applicative (en mémoire uniquement).
 */
object GlbModelCache {

    private val cache = mutableMapOf<String, GlbModel>()
    private val lock = Any()

    fun get(path: String): GlbModel? = synchronized(lock) { cache[path] }

    fun put(path: String, model: GlbModel) = synchronized(lock) { cache[path] = model }

    fun has(path: String): Boolean = synchronized(lock) { path in cache }

    /** Supprime les entrées correspondant aux chemins donnés (ex: projet supprimé). */
    fun evict(paths: Collection<String>) = synchronized(lock) { paths.forEach { cache.remove(it) } }

    /** Précharge une liste de chemins GLB en arrière-plan. Ignore les chemins déjà en cache. */
    fun preload(paths: List<String>, onDone: (() -> Unit)? = null) {
        val toLoad = paths.filter { !has(it) }
        if (toLoad.isEmpty()) {
            onDone?.invoke()
            return
        }
        Thread {
            for (path in toLoad) {
                if (has(path)) continue
                val model = GlbParser.parse(path)
                if (model != null) {
                    put(path, model)
                    android.util.Log.d("ArMEP", "Cache: préchargé ${path.substringAfterLast("/")}")
                }
            }
            android.util.Log.d("ArMEP", "Cache: préchargement terminé (${toLoad.size} fichiers)")
            onDone?.invoke()
        }.start()
    }

    fun size(): Int = synchronized(lock) { cache.size }
}
