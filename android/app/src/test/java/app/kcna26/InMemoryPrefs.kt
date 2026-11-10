package app.kcna26

import android.content.SharedPreferences

/**
 * In-memory SharedPreferences for JVM unit tests (owner: foundation), e.g.
 * `SettingsStore(InMemoryPrefs())` or `FakeableClock(InMemoryPrefs(), allowFake = true)`.
 * Listeners are notified synchronously on apply()/commit().
 */
class InMemoryPrefs : SharedPreferences {
    private val map = LinkedHashMap<String, Any?>()
    private val listeners = LinkedHashSet<SharedPreferences.OnSharedPreferenceChangeListener>()

    override fun getAll(): MutableMap<String, *> = LinkedHashMap(map)
    override fun getString(key: String, defValue: String?): String? = if (map.containsKey(key)) map[key] as String? else defValue
    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
        if (map.containsKey(key)) (map[key] as Set<String>?)?.toMutableSet() else defValues
    override fun getInt(key: String, defValue: Int): Int = map[key] as Int? ?: defValue
    override fun getLong(key: String, defValue: Long): Long = map[key] as Long? ?: defValue
    override fun getFloat(key: String, defValue: Float): Float = map[key] as Float? ?: defValue
    override fun getBoolean(key: String, defValue: Boolean): Boolean = map[key] as Boolean? ?: defValue
    override fun contains(key: String): Boolean = map.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor()
    override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener) {
        listeners += l
    }
    override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener) {
        listeners -= l
    }

    private inner class Editor : SharedPreferences.Editor {
        private val puts = LinkedHashMap<String, Any?>()
        private val removes = LinkedHashSet<String>()
        private var clear = false

        override fun putString(key: String, value: String?) = apply { puts[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = apply { puts[key] = values?.toSet() }
        override fun putInt(key: String, value: Int) = apply { puts[key] = value }
        override fun putLong(key: String, value: Long) = apply { puts[key] = value }
        override fun putFloat(key: String, value: Float) = apply { puts[key] = value }
        override fun putBoolean(key: String, value: Boolean) = apply { puts[key] = value }
        override fun remove(key: String) = apply { removes += key }
        override fun clear() = apply { clear = true }
        override fun commit(): Boolean {
            apply()
            return true
        }
        override fun apply() {
            val changed = LinkedHashSet<String>()
            if (clear) {
                changed += map.keys
                map.clear()
            }
            for (k in removes) {
                map.remove(k)
                changed += k
            }
            for ((k, v) in puts) {
                if (v == null) map.remove(k) else map[k] = v
                changed += k
            }
            for (k in changed) for (l in listeners.toList()) l.onSharedPreferenceChanged(this@InMemoryPrefs, k)
        }
    }
}
