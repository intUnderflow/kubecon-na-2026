import Foundation

/// An insertion-ordered set: the port of Kotlin's `LinkedHashSet` (what `toSet()`,
/// `mutableSetOf()`, `setOf(...)` and `mapTo(LinkedHashSet())` produce) for code that
/// ITERATES the set. For pure membership tests a plain `Set` is enough.
///
/// Adding an element that is already present keeps its original position.
/// `==` ignores order, like Kotlin's `Set.equals`.
///
/// ```swift
/// var s: OrderedSet = ["b", "a"]
/// s.append("b")         // false: already there, order unchanged
/// Array(s)              // ["b", "a"]
/// ```
struct OrderedSet<Element: Hashable> {
    /// Elements in insertion order.
    private(set) var elements: [Element]
    private var members: Set<Element>

    init() {
        elements = []
        members = []
    }

    /// Kotlin `toSet()` / `LinkedHashSet(collection)`: the distinct elements, first occurrence first.
    init<S: Sequence>(_ s: S) where S.Element == Element {
        self.init()
        for e in s { append(e) }
    }

    var count: Int { elements.count }
    var isEmpty: Bool { elements.isEmpty }

    func contains(_ e: Element) -> Bool { members.contains(e) }

    /// Kotlin `add`: appends `e` unless present. Returns true if it was added.
    @discardableResult
    mutating func append(_ e: Element) -> Bool {
        guard members.insert(e).inserted else { return false }
        elements.append(e)
        return true
    }

    /// Kotlin `remove` (O(n)). Returns true if it was present.
    @discardableResult
    mutating func remove(_ e: Element) -> Bool {
        guard members.remove(e) != nil else { return false }
        if let i = elements.firstIndex(of: e) { elements.remove(at: i) }
        return true
    }

    /// The members as a plain `Set`.
    var asSet: Set<Element> { members }
}

extension OrderedSet: Sequence {
    func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
    var underestimatedCount: Int { elements.count }
}

extension OrderedSet: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Element...) { self.init(elements) }
}

extension OrderedSet: Equatable {
    /// Order-insensitive, like Kotlin `Set.equals`.
    static func == (lhs: OrderedSet, rhs: OrderedSet) -> Bool { lhs.members == rhs.members }
}

extension OrderedSet: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(members) }
}

extension OrderedSet: Sendable where Element: Sendable {}

extension OrderedSet: CustomStringConvertible {
    /// `[a, b]`, like Kotlin's `Set.toString()`.
    var description: String { "[" + elements.map { "\($0)" }.joined(separator: ", ") + "]" }
}
