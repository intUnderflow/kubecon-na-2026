import XCTest
@testable import KCNA26Core

/// OrderedMap (LinkedHashMap semantics) and OrderedSet (LinkedHashSet semantics).
final class OrderedMapTests: XCTestCase {

    func testInsertionOrderAndInPlaceReplacement() {
        var m = OrderedMap<String, Int>()
        XCTAssertTrue(m.isEmpty)
        m["b"] = 1
        m["a"] = 2
        m["c"] = 3
        m["a"] = 20 // replace in place
        XCTAssertEqual(m.keys, ["b", "a", "c"])
        XCTAssertEqual(m.values, [1, 20, 3])
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m["a"], 20)
        XCTAssertNil(m["z"])
        XCTAssertEqual(m["z", default: 9], 9)
        XCTAssertEqual(m.map { "\($0.key)\($0.value)" }, ["b1", "a20", "c3"])
        XCTAssertEqual(m.first?.key, "b")
        XCTAssertEqual(m.index(forKey: "c"), 2)
        XCTAssertEqual(m.element(at: 1).value, 20)
        XCTAssertEqual(m.description, "{b=1, a=20, c=3}")
    }

    func testRemoval() {
        var m: OrderedMap = ["a": 1, "b": 2, "c": 3]
        XCTAssertEqual(m.removeValue(forKey: "b"), 2)
        XCTAssertNil(m.removeValue(forKey: "b"))
        XCTAssertEqual(m.keys, ["a", "c"])
        m["a"] = nil
        XCTAssertEqual(m.keys, ["c"])
        m["a"] = 5 // re-added at the end
        XCTAssertEqual(m.keys, ["c", "a"])
        m.removeAll()
        XCTAssertTrue(m.isEmpty)
    }

    func testPairsKeepFirstPositionAndLastValue() {
        // Kotlin toMap() / associate / repeated put.
        let m = OrderedMap([("x", 1), ("y", 2), ("x", 3)])
        XCTAssertEqual(m.keys, ["x", "y"])
        XCTAssertEqual(m["x"], 3)
        let lit: OrderedMap = ["x": 1, "y": 2]
        XCTAssertEqual(lit.keys, ["x", "y"])
        var p = lit
        XCTAssertEqual(p.putIfAbsent("x", 9), 1)
        XCTAssertNil(p.putIfAbsent("z", 9))
        XCTAssertEqual(p.keys, ["x", "y", "z"])
        XCTAssertEqual(p["x"], 1)
        XCTAssertEqual(p.updateValue(7, forKey: "y"), 2)
    }

    func testLargeMapsStayConsistentAcrossTheIndexThreshold() {
        var m = OrderedMap<Int, Int>()
        for i in 0..<100 { m[i * 7 % 100] = i }
        XCTAssertEqual(m.count, 100)
        for i in 0..<100 { XCTAssertEqual(m[i * 7 % 100], i) }
        for k in stride(from: 0, to: 100, by: 2) { m[k] = nil }
        XCTAssertEqual(m.count, 50)
        XCTAssertTrue(m.keys.allSatisfy { $0 % 2 == 1 })
        for k in m.keys { XCTAssertEqual(m.index(forKey: k), m.keys.firstIndex(of: k)) }
        while m.count > 3 { m.removeValue(forKey: m.keys[0]) }
        XCTAssertEqual(m.count, 3)
        for k in m.keys { XCTAssertNotNil(m[k]) }
        var big = OrderedMap<String, Int>()
        big.reserveCapacity(50)
        for i in 0..<50 { big["k\(i)"] = i }
        XCTAssertEqual(big["k49"], 49)
        XCTAssertEqual(big.keys.first, "k0")
    }

    func testTransformsKeepOrder() {
        let m: OrderedMap = ["c": 3, "a": 1, "b": 2]
        XCTAssertEqual(m.mapValues { $0 * 10 }.values, [30, 10, 20])
        XCTAssertEqual(m.mapValuesWithKey { k, v in "\(k)\(v)" }.values, ["c3", "a1", "b2"])
        XCTAssertEqual(m.filter { $0.value != 1 }.keys, ["c", "b"])
        XCTAssertEqual(m.filter { k, _ in k != "c" }.keys, ["a", "b"])
        XCTAssertEqual(m.filterKeys { $0 > "a" }.keys, ["c", "b"])
        XCTAssertEqual(m.filterValues { $0 > 1 }.keys, ["c", "b"])
        XCTAssertEqual(m.compactMapValues { $0 == 2 ? nil : $0 }.keys, ["c", "a"])
        XCTAssertEqual(m.with("a", 9).values, [3, 9, 2])
        XCTAssertEqual(m.with("z", 0).keys, ["c", "a", "b", "z"])
        XCTAssertEqual(m.merging(["b": 5, "d": 4]).elements.map(\.key), ["c", "a", "b", "d"])
        XCTAssertEqual(m.toDictionary(), ["a": 1, "b": 2, "c": 3])
    }

    func testEqualityIgnoresOrderLikeKotlinMaps() {
        let a: OrderedMap = ["x": 1, "y": 2]
        let b: OrderedMap = ["y": 2, "x": 1]
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.orderedEquals(b))
        XCTAssertTrue(a.orderedEquals(["x": 1, "y": 2]))
        XCTAssertNotEqual(a, ["x": 1])
        XCTAssertNotEqual(a, ["x": 1, "y": 3])
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testOrderedSet() {
        var s: OrderedSet = ["b", "a"]
        XCTAssertFalse(s.append("b"))
        XCTAssertTrue(s.append("c"))
        XCTAssertEqual(Array(s), ["b", "a", "c"])
        XCTAssertTrue(s.contains("a"))
        XCTAssertTrue(s.remove("a"))
        XCTAssertFalse(s.remove("a"))
        XCTAssertEqual(s.elements, ["b", "c"])
        XCTAssertEqual(OrderedSet(["x", "y", "x"]).elements, ["x", "y"])
        XCTAssertEqual(OrderedSet(["x", "y"]), OrderedSet(["y", "x"]))
        XCTAssertEqual(s.description, "[b, c]")
        XCTAssertEqual(s.asSet, ["b", "c"])
    }
}
