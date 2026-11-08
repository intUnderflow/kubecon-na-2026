package app.kcna26.sync

import app.kcna26.data.Repository

/**
 * One [T] per [Repository], rebuilt when DataSync swaps in a new Repository (the App uses it
 * for the Router and DetailsRepository, which are built from a Repository).
 */
class RepositoryScoped<T : Any>(private val make: (Repository) -> T) {
    @Volatile
    private var current: Pair<Repository, T>? = null

    operator fun get(repo: Repository): T {
        current?.let { (r, v) -> if (r === repo) return v }
        synchronized(this) {
            current?.let { (r, v) -> if (r === repo) return v }
            return make(repo).also { current = repo to it }
        }
    }
}
