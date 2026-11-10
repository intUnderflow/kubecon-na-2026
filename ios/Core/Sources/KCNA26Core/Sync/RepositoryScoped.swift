import Foundation

/// One `T` per ``Repository``, rebuilt when DataSync swaps in a new Repository (the app uses it
/// for the Router and DetailsRepository, which are built from a Repository).
///
/// ```swift
/// private let routerByRepository = RepositoryScoped { Router($0) }
/// var router: Router { routerByRepository[repository] }
/// ```
///
/// Thread-safe: `make` runs at most once per Repository (identity, `===`), under a lock, on the
/// calling thread.
final class RepositoryScoped<T>: @unchecked Sendable {
    private let make: (Repository) -> T
    private let lock = NSLock()
    private var current: (repo: Repository, value: T)?

    init(_ make: @escaping (Repository) -> T) {
        self.make = make
    }

    /// The `T` for `repo`: the cached one if it was made for this very Repository, else a new one.
    subscript(_ repo: Repository) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let c = current, c.repo === repo { return c.value }
        let v = make(repo)
        current = (repo, v)
        return v
    }
}
