# KCNA26Core conventions

How the Swift port maps the Kotlin app, and the shared infrastructure every area builds on.
The Kotlin code (`android/app/src/main/java/app/kcna26`) is the specification; this file says
how to write its Swift twin. Keep it accurate when you change a foundation file.

```
cd ios/Core && swift build && swift test          # Linux or macOS; Swift 6 language mode
swift test --filter RepositoryTests               # one class
```

## Ground rules

- **One module.** Core sources are compiled into the app module ("KCNA26") as well as into the
  `KCNA26Core` package. Never `import KCNA26Core` in sources (tests use
  `@testable import KCNA26Core`); no `public`; type and global names must be unique across Core
  and the app. Core imports only `Foundation`, `Observation`, `Dispatch`.
- **File and type names = Kotlin's.** `data/Repository.kt` -> `Data/Repository.swift`; tests
  `data/RepositoryTest.kt` -> `Tests/KCNA26CoreTests/Data/RepositoryTests.swift`, one
  `func testName()` per `@Test fun name()`.
- **Constants keep their Kotlin names**: `Repository.SCHEDULE`, `GoingStore.REMIND_OPTIONS`,
  `Session.EVENT_COLOCATED` (`static let`; `nonisolated static let` inside `@MainActor` types).
- Kotlin `fun` taking positional args -> Swift funcs with unlabeled params where Kotlin callers
  pass positionally (`repo.session(id)`, `isMine(s, me)`, `GoingStore(prefs)`).

## Kotlin -> Swift mapping decisions

| Kotlin | Swift (Core) |
|---|---|
| `data class` | `struct` (`Sendable, Hashable`), `let` fields, same names; memberwise init (explicit init only where Kotlin has defaults) |
| `object X` / `companion object` | `enum X` with `static` members / `static let` on the type |
| `sealed interface` | `enum` with associated values |
| class with `StateFlow`s (stores, view models) | `@MainActor @Observable final class`, `private(set) var` state (`speakingAs.value` -> `speakingAs`) |
| `fun interface Foo` | `protocol Foo: Sendable` |
| `by lazy(SYNCHRONIZED)` | `SynchronizedLazy` (Util/Locked.swift); `isInitialized` never blocks, like Kotlin's |
| `Instant` | `Date` (epoch millis are `Int64`: `date.epochMillis`, `Date(epochMillis:)`) |
| `ZonedDateTime` in ZONE | `Date` + `date.localDateTime` (a `LocalDateTime` in Denver) |
| `LocalDate` / `LocalDateTime` / `DayOfWeek` | same names (Time/LocalDate.swift), java.time semantics |
| `Duration` | seconds (`TimeInterval`) or whole minutes (`Int`), as the Kotlin code uses it: `Session.OPEN_ENDED` = 5400 s; `Duration.between(a,b).toMinutes()` -> `durationMinutes(from:to:)` |
| `Int` / `Long` | `Int` / `Int64` (Kotlin Int is 32-bit: JSON decoding of an `Int` field rejects values outside Int32, like kotlinx) |
| `Map` that is iterated (JSON maps, `associate`, `LinkedHashMap`) | `OrderedMap` (`==` ignores order, like Kotlin) |
| `Set` (membership only) | `Set`; iterated `LinkedHashSet` -> `OrderedSet` |
| `List` | `Array` |
| colour `Int` (ARGB) | `UInt32` 0xAARRGGBB (same bits; `Int32(bitPattern:)` gives Kotlin's value) |
| `SharedPreferences` | `KeyValueStore` (`UserDefaultsStore(suiteName: PREFS)` in the app, `InMemoryStore()` in tests/previews), same file and key names |
| kotlinx `@Serializable` DTO | `struct XDto: JSONDecodable` with `init(json:)` using `JSONFields` |
| `Json.decodeFromString` | `JSON.decode(T.self, from: data)` |
| `Regex` | `KRegex` (Util/KRegex.swift), UTF-16 offsets |
| `sortedBy` / `sortedWith` (stable) | `stableSorted(on:)` / `stableSorted(with: KComparator)` / `stableSorted(by:)` — never plain `sorted` where ties can occur |
| thrown exceptions | Swift `throws`; property that may throw -> `var x: T { get throws }` (e.g. `repo.details`) |
| `require`/`check`/`!!` on programmer errors | `precondition` / force unwrap only for real invariants; never trap on data |
| `Locale.ROOT` `lowercase()`/`uppercase()` | `lowercased()` / `uppercased()` (locale-independent; one difference: Java lowercases a word-final `Σ` to `ς`, Swift always gives `σ`); `caps()` for display caps |
| String `==`, `in`, `startsWith`, `endsWith`, `contains` | `kotlinEquals(a, b)`, `s.kotlinStartsWith(p)`, `kotlinEndsWith`, `kotlinContains` where text may be non-NFC (see Strings below); plain `==` / `hasPrefix` / `contains` are fine for ASCII and for the NFC data files |

### Errors

- `JSONParseError` (malformed text: message, byte offset, line, column) and
  `JSONDecodingError` (wrong shape: `$.sessions[3].start: Expected a string, found number 3`)
  stand for kotlinx's `SerializationException`.
- `DateTimeParseError` stands for `DateTimeParseException` (typed throws: the ISO parsers are
  `throws(DateTimeParseError)`, so `catch is DateTimeParseError` mirrors
  `catch (e: DateTimeException)`).
- `Repository.load` throws for a bad core file; colocated.json / colocated_details.json
  problems are swallowed (any error, where Kotlin catches IOException +
  IllegalArgumentException, which is every error those calls can raise); a bad date inside
  colocated.json drops the whole co-located merge (all or nothing); details.json errors surface
  from `try repo.details` (not cached: the next access retries).

## Infrastructure API

### JSON (Data/JSON.swift, Data/JSONDecoding.swift)

```swift
let root = try JSON.parse(data)                     // or JSON.parse(string); JSONValue
root["sessions"]?[0]?["id"]?.stringValue            // subscripts return nil on a miss
root["origin"]?["lat0"]?.doubleValue                // also intValue, int64Value, boolValue, arrayValue, objectValue, isNull
root["x"]?.numberValue?.literal                     // "84300" vs "84300.0" stay distinct (JSONNumber.isInteger)
root.objectValue!.keys                              // file order
JSON.serialize(root)                                 // compact (JsonElement.toString()); pretty: true = 4-space indent
let v: JSONValue = ["a": 1, "b": [true, nil]]       // literals keep key order
```

- `enum JSONValue { null, bool, number(JSONNumber), string, array, object(OrderedMap<String, JSONValue>) }`.
- Parser: strict RFC 8259 grammar, UTF-8 input; a repeated key keeps its first position and
  last value; `\uXXXX` surrogate pairs combine (a lone surrogate becomes U+FFFD); raw control
  characters inside strings are accepted (kotlinx does); depth limit `JSON.maxDepth` (200).
  kotlinx's lenient *unquoted* string tokens are not accepted (the data never uses them), and
  neither are leading zeros (`[01]`); see Known platform differences. `-0` reads as -0.0.
- Strings parse in linear time (also with many escapes in one string).
- Debug-build cost: the whole 1.4 MB data set parses in ~40 ms.

Decoding a DTO (kotlinx config `ignoreUnknownKeys, explicitNulls=false, coerceInputValues, isLenient`):

```swift
struct EdgeDto: JSONDecodable {
    let a: String; let textAB: String; let speakers: [String]; let end: String?
    init(json: JSONValue) throws {
        let o = try JSONFields(json, "EdgeDto")
        a = try o.required("a")                          // no Kotlin default: missing/null throws
        speakers = try o.value("speakers", default: [])  // Kotlin default: missing/null -> default
        end = try o.optional("end")                      // `T? = null`: missing/null -> nil
        textAB = try o.required("textAB")
    }
}
let dto = try JSON.decode(EdgeDto.self, from: data)
```

`JSONDecodable` conformances: `String` (lenient: a number/bool token gives its literal text),
`Int` (kotlinx rules: integer literal, whole exponent form "3e2", or a quoted number; never
"3.0" or `true`; 32-bit), `Int64`, `Double` (any number or numeric string; finite), `Bool`
(also a quoted "true"/"false"), `Array`, `OrderedMap<String, V>`, `Optional`, `JSONValue`.
`kotlinxLong(_:)` exposes the integer rule (an exponent form goes through a Double, as in
kotlinx: "9223372036854775807e0" overflows and throws; decoding never traps).

Writing caches/stores (kotlinx `encodeToString` with `explicitNulls=false`, default `encodeDefaults=false`):

```swift
var o = JSONObjectBuilder()
o.put("description", d.description)
o.put("speakers", speakers, unlessEqualTo: [])   // omitted when equal to the Kotlin default
o.putIfNotNil("slides", d.slides)                // omitted when nil
let text = JSON.serialize(o.value)               // or JSON.encode(someJSONEncodable)
```

### OrderedMap / OrderedSet (Util)

```swift
var m: OrderedMap = ["E200S": 1, "EWT": 2]     // insertion order; O(1) lookup
m["EHY"] = 3; m["EWT"] = 20                       // append / replace in place; m[k] = nil removes
m.keys; m.values; for (k, v) in m { }; m.count; m.containsKey("EWT"); m.index(forKey:)
m.mapValues { }; m.mapValuesWithKey { k, v in }; m.filter { k, v in }; m.filterKeys { }; m.compactMapValues { }
m.putIfAbsent(k, v); m.with(k, v) /* Kotlin map + (k to v) */; m.merging(other); m.orderedEquals(other)
OrderedMap(pairs)                                 // repeated key: first position, last value (toMap/associate)
var s: OrderedSet = ["b", "a"]; s.append("c"); s.contains("a"); s.elements
```

### Kotlin compat (Util/KotlinCompat.swift)

Sorting — all stable:
```swift
xs.stableSorted(on: { $0.start })                               // sortedBy (nil keys first for optionals)
xs.stableSortedDescending(on: { $0.start })                     // sortedByDescending
xs.stableSorted(with: KComparator<Session>.by { $0.start }.thenBy { $0.id })   // sortedWith(compareBy{}.thenBy{})
xs.stableSorted(with: .by(.caseInsensitiveOrder) { $0.name })   // compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }
names.stableSorted(with: .caseInsensitiveOrder)                 // sortedWith(String.CASE_INSENSITIVE_ORDER)
xs.stableSorted { ($0.a, $0.b) < ($1.a, $1.b) }                 // tuple predicate (Swift String / IEEE Double order!)
xs.min(with: cmp); xs.max(with: cmp)                            // minWithOrNull / maxWithOrNull (first of equals)

// private val NEAREST_FIRST = compareBy<FromMenuItem>({ it.d ?: Long.MAX_VALUE }, { it.level ?: Int.MAX_VALUE })
static let NEAREST_FIRST = KComparator<FromMenuItem>.by { $0.d ?? Int64.max }.thenBy { $0.level ?? Int.max }
```
`KComparator` (`Sendable`, so it can be a `static let`): `.by`, `thenBy`, `thenByDescending`,
`then`, `reversed()`, `.naturalOrder`, `.caseInsensitiveOrder`, `.javaOrder`; its closures are
`@Sendable` (capture `let`s, not `var`s; key paths work; generic code building one from a key
of type `K` constrains `K: KComparable` = `Comparable & SendableMetatype`). Key order is Kotlin's `compareValues`
on every path (`stableSorted(on:)`, `KComparator.by`/`thenBy`, optional keys, `naturalOrder`,
generic `K: Comparable` code): `String` by UTF-16 units (no canonical equivalence: "e\u{301}"
sorts before "é"), `Double`/`Float` by Java's total order (`javaDoubleCompare`: -0.0 < 0.0, NaN
after +inf and equal to itself, so a NaN key cannot scramble a sort), `Bool` false < true, nil
first; other types by their `<`. Only the `stableSorted(by:)` predicate form and Swift's own
`<`, `sorted()`, `min()`, `max()` use Swift order (IEEE for Doubles: NaN unordered).
Swift's `min(by:)` / `max(by:)` / `first(where:)` already return the first of equals.

Strings (Kotlin indexes and compares UTF-16 units):
- Equality trap: Swift `String` `==` and `Hashable` use Unicode canonical equivalence
  ("Jos\u{E9}" == "Jose\u{301}"), so `Set<String>`, dictionary / `OrderedMap` keys,
  `distinct()`, `associateBy`, `isMine`'s `speakers.contains(me)` merge strings Kotlin keeps
  apart; `hasPrefix` / `hasSuffix` / `contains(String)` match whole Characters
  (`"Jose\u{301}".hasPrefix("Jose")` is false). Kotlin `==` / `in` / `startsWith` / `endsWith` /
  `contains` on such text -> `kotlinEquals(a, b)` (`a.utf16.elementsEqual(b.utf16)`),
  `s.kotlinStartsWith(p)`, `s.kotlinEndsWith(p)`, `s.kotlinContains(x)` (=
  `kotlinIndexOf(x) >= 0`). Every string in the bundled data is NFC, so this only matters for
  text that may not be (user input, downloaded data, NFD output of `decomposedStringWithCanonicalMapping`).
- `javaCompare(a, b)` (`String.compareTo`, UTF-16), `javaCaseInsensitiveCompare(a, b)`
  (`CASE_INSENSITIVE_ORDER`, Android's per-unit simple case mapping), `kotlinEqualsIgnoreCase`.
- `s.kotlinTrim()` = Kotlin `trim()` (strips `Char.isWhitespace`: incl. NBSP, U+2000–200A,
  U+3000; not U+200B/U+FEFF). `s.javaTrim()` = Java `String.trim()` (chars <= U+0020).
  `kotlinTrimStart/End`, `isBlank`, `isNotBlank`, `takeIfNotBlank()`, `ifBlank {}`, `ifEmpty {}`,
  `isKotlinWhitespace(utf16Unit)`.
- `kotlinLength`, `kotlinSubstring(a, b)`, `kotlinTake/TakeLast/Drop(n)`, `kotlinIndexOf(s, from:)`,
  `kotlinLastIndexOf`, `substringBefore/After/BeforeLast/AfterLast(_:missing:)`,
  `removePrefix/removeSuffix`, `padStart/padEnd(len, char)`, `replaceFirst(old, new)`,
  `kotlinReplace(old, new)`, `kotlinSplit(delimiter)` (keeps empty parts).
- Normalization: `Normalizer.normalize(s, NFD)` -> `s.decomposedStringWithCanonicalMapping`.

Numbers:
- `x.kotlinRoundToInt()` / `kotlinRoundToLong()` = `Math.round` (half UP: -2.5 -> -2; saturates
  at Int32 / Int64; NaN -> 0 instead of throwing). `x.kotlinRound()` = `kotlin.math.round` (half
  EVEN). `x.kotlinToInt()` / `kotlinToLong()` = `toInt()` (truncate, saturate, NaN -> 0).
  Never call Swift's `Int(x)` on a computed Double (it traps on NaN/overflow).
- `floorMod(x, y)`, `floorDiv(x, y)`; `x.clamped(to: a...b)`, `coerceIn(a, b)`, `coerceAtLeast`, `coerceAtMost`.

Collections: `distinct()`, `distinctBy {}`, `associateBy {}` / `associateBy({}, {})` /
`associate { (k, v) }` / `associateWith {}` (-> `OrderedMap`, last wins), `groupBy {}`
(-> `OrderedMap<K, [V]>`), `kotlinPartition {}`, `zipWithNext()`, `windowed(size, step:,
partialWindows:)`, `chunked(n)`, `getOrNull(i)`, `ifEmpty {}`.

### KRegex (Util/KRegex.swift)

```swift
private static let LEVEL_TAIL = KRegex(" (?:to|on) Level \\d+(?=,|$)")
LEVEL_TAIL.replace(s, "")                    // all matches; "$1" group refs
RE.replace(s) { m in m.groupValues[1] }       // computed replacement
RE.matches(s)                                // WHOLE input (Kotlin matches)
RE.containsMatchIn(s); RE.find(s, startIndex: 0)?.groupValues; RE.findAll(s); RE.replaceFirst(s, r)
s.split(RE)                                  // keeps empty parts (Kotlin, not Java)
KRegex("reception", options: .ignoreCase)    // .multiline, .dotMatchesAll, .comments, .literal
```
Replacement strings (`replace(s, r)`, `replaceFirst`) follow Java's `Matcher.appendReplacement`
(implemented in KRegex, not NSRegularExpression's template syntax): `$n` (greedy while the group
exists), `${name}`, `\x` = literal x; an invalid reference traps (Kotlin throws). Use
`KRegex.escapeReplacement(s)` (Kotlin `Regex.escapeReplacement`) for literal text.
`KMatch`: `value`, `range` (UTF-16, half-open), `groupValues` ("" if unmatched), `groups`
(nil if unmatched), `groupRanges`, `group(named:)`. ICU note: `\s`, `\w`, `\b` are Unicode-aware
(as on Android; the desktop JVM running the Kotlin tests is ASCII-only).

### Concurrency helpers (Util/Locked.swift)

```swift
let box = Locked<[String]>([]); box.withLock { $0.append(x) }; box.value
private let index = SynchronizedLazy { buildIndex() }; index.value            // lazy, once
private let parsed = SynchronizedLazy { try parse() }; try parsed.get()       // throwing: retried after a failure
index.isInitialized                       // never waits: false while another thread is initializing
```

### KeyValueStore (Util/KeyValueStore.swift)

```swift
let prefs: KeyValueStore = UserDefaultsStore(suiteName: SettingsStore.PREFS)   // app
let prefs: KeyValueStore = InMemoryStore()                                     // tests, previews
prefs.string(forKey: k) ?? def      // also stringSet, int, int64, bool, double; nil when absent or another kind
prefs.set("EWT", forKey: k)          // set(String | Set<String> | Int | Int64 | Bool | Double, forKey:)
prefs.removeValue(forKey: k); prefs.contains(k)
prefs.edit { e in e.set(3, forKey: "a"); e.removeValue(forKey: "b") }        // one batch, in order
```
Kotlin `putInt` -> `set(Int)`, `putLong` -> `set(Int64)` (keep the type: readers are typed).
Both stores tell String, string set, Bool, integer and floating-point values apart (a Bool is
not 1, 2.75 is not 2). `UserDefaultsStore` cannot tell `Int` from `Int64` (one plist integer
type), so there `int` and `int64` both read any integer; `InMemoryStore` (tests) is strict, so
read with the type that was written and the tests catch a mismatch.
PREFS names: "kcna26.settings", "kcna26.going", "kcna26.reminders", "kcna26.debug" (and the
Sync port's own). No change listeners (no Kotlin main code registers one).

### SHA256 (Util/SHA256.swift)

`SHA256.hex(data)` -> lowercase hex (DataManifest.sha256); `SHA256.digest(data)` -> 32 bytes.
Pure Swift (no CryptoKit). A local type: it shadows CryptoKit's `SHA256` if the app imports CryptoKit.

### Time (Time/)

```swift
ZONE                                     // TimeZone America/Denver; zoneCalendar = gregorian Calendar in ZONE
try parseOffsetDateTime("2026-11-09T09:00:00-07:00")   // OffsetDateTime.parse(s).toInstant() -> Date (offset "-07" ok too, JDK 9+)
try parseInstant("2026-11-11T16:00:00Z")               // Instant.parse (strict offset "+HH:MM[:SS]"; 24:00, :60)
try LocalDate.parse("2026-11-08"); LocalDate(2026, 11, 8).dayOfWeek == .sunday
try LocalDateTime.parse("2026-11-11T09:00").atZone(ZONE)   // java.time gap/overlap rules
try parseFakeNow(s)                      // OffsetDateTime, else Instant, else Denver local
date.localDateTime / date.localDate / date.minuteOfDay      // instant.atZone(ZONE)...
date.epochMillis; Date(epochMillis:); Date(epochSecond:nanos:); date.truncatedToMinute
date.plusMinutes(n) / minusMinutes / plusSeconds(Int64) / plusMillis(Int64); isBefore/isAfter (or < >)
day.atStartOfDay(); day.plusDays(1); durationMinutes(from: a, to: b)
```
`LocalDate` (year, monthValue, dayOfMonth, dayOfWeek, epochDay, plusDays, atTime, atStartOfDay,
Comparable, "2026-11-08"), `LocalDateTime` (date, hour, minute, second, nano, minuteOfDay,
plusMinutes, truncatedToMinute, atZone). Calendar arithmetic is pure (epoch days); the zone is
only asked for offsets, so results match java.time, also across DST.

Clocks (inject; never call `Date()` in logic):
```swift
protocol AppClock: Sendable { func now() -> Date }
SystemAppClock.shared; FixedClock(date) / try FixedClock.parse(iso) (clock.instant is settable); ClosureAppClock { ... }
FakeableClock(prefs, allowFake: isDebug)   // offset in prefs "kcna26.debug"/"fakeNowOffsetMs"; Observable offsetMillis
clock.applyFakeNowArg("2026-11-11T09:00:00-07:00" | "clear"); clock.realEpochMillis(at); clock.nowLocal()
```
`NowTicker(clock:periodMillis:running:)` (`@MainActor @Observable`, Kotlin `rememberNow`):
`ticker.now` re-evaluated every `NOW_PERIOD_MS` (15 s) aligned to the clock + 20 ms;
`resume()` / `pause()` from scenePhase; refreshes at once when a FakeableClock's offset
changes. `NowTicker.nextDelayMillis(nowEpochMillis:periodMillis:)` is the pure rule.

`TimeFormat` (hm, ap, hma, range, dur, durationLabel, clockLabel, minutesBetween, minuteOfDay):
same names and strings as Kotlin.

### Data (Data/)

Models (Models.swift) keep every Kotlin name: `Session` (start/end `Date`, `effectiveEnd`,
`startLocal`, `isColocated`, `OPEN_ENDED`, `EVENT_COLOCATED`), `Day` (`dow`, `num`), `Category`
(`lightArgb`/`darkArgb` are `UInt32 { get throws }`, `argb(dark:)`), `Room` (`hasPosition`,
`pos`), `Wayfinding` (`entrances`/`nodes` are `OrderedMap`, `edges` in file order), `Venue`,
`ColoEvent`, `SessionDetail`, `SummitDetail`, `PointXY(x, y)`, `SessionGroup(key, title)`,
`SpeakerTagline(name, tagline)`; `parseHexColor(_:) throws -> UInt32`.

```swift
let repo = try Repository.bundled()                 // app: Bundle "Data" folder; off the main thread
let repo = try Repository.fromDirectory(url)        // a downloaded set / tests
let repo = try Repository.load { name in try data(name) }   // @Sendable opener, kept for the lazy details
repo.sessions; repo.days; repo.categories; repo.rooms; repo.extraRooms; repo.wayfinding; repo.venue
repo.session(id); repo.room(code); repo.day(key); repo.dayOf(s); repo.roomOf(s); repo.category(k); repo.coloEvent(k)
repo.sessionsById; repo.coloEventsByKey; repo.supersededIds; repo.allSpeakers; repo.anthropicSpeakers; repo.defaultMe
try repo.details                                     // lazy, thread-safe; repo.isDetailsLoaded
isMine(s, me); hasAnthropic(s, me, speakers); repo.hasAnthropic(s, me); speakerLabel(name, me); repo.mySessions(me)
```

### Stores

`SettingsStore(prefs)`, `GoingStore(prefs)` (`@MainActor @Observable`; observable
`speakingAs`, `firstRunPending`, `directionsFrom` / `ids`, `remindMinutes`),
`ReminderStore(prefs)` (plain `Sendable` class: `armed()`, `setArmed(_:)`).

### Theme values (Theme/)

`AppPalette.light` / `.dark` (Kotlin `LightAppColors` / `DarkAppColors`; roles `bg, surface,
ink, muted, line, you, anthropic, categories` + derived `liveBorder, anthropicCardBg,
anthropicCardBorder, anthropicRowBg, pressed, scrim, mapMe, mapHyatt, note, onYou,
onAnthropic, primaryContainer, ...`), `CategoryLight` / `CategoryDark` (`OrderedMap<String,
UInt32>`), `mixARGB(a, b, fraction)` (Kotlin `mix`, Compose rounding), `argbWithAlpha(c, a)`
(`copy(alpha=)`), `argbComponents(c)` (for `Color(.sRGB, ...)`), `Dimens.*` (points), `s.caps()`.
The SwiftUI layer builds `Color`s from these; it should not hard-code hex values.

## Tests

- `TestData` (Tests/KCNA26CoreTests/TestData.swift): `repo` (loaded once), `dataDir` /
  `assetsDir` (ios/KCNA26/Resources/Data), `publishedDataDir` (<repo>/data, has
  test_vectors.json), `androidAssetsDir`, `androidTestDir` (Kotlin test sources, e.g.
  route/golden/), `vectors` (typed test_vectors.json), `text(name)`, `data(name)`,
  `json(name)`, `url(name)`, `clockAt(iso)`, `instant(iso)`, `lines(url)`, `crc32Hex(_:)`
  (java.util.zip.CRC32).
- Tests of `@MainActor` types: mark the test class `@MainActor`. Async waits: poll with
  `Task.sleep`, never fixed long sleeps.
- `InMemoryStore()` replaces `InMemoryPrefs()`; `TestData.instant(iso)` replaces
  `OffsetDateTime.parse(iso).toInstant()` / `Instant.parse(iso)`.

### Hand-offs to later ports (TODO)

- **Schedule port**: `ColocatedRepositoryTest.theScheduleStillLoadsWithoutColocatedJson` (Kotlin
  lines 230-236) also checks `ScheduleIndex(r).dayView("mon", instant("2026-11-09T08:00:00-07:00"),
  "Lucy Sweet")!!` for each broken colocated.json (missing file, `"{ not json"`, a bad date):
  `mon.colo` is empty; `mon.longsTitle == "Co-located + off-site"`; `mon.longsFirst`; exactly 11
  of `mon.longs` have `session.note == "All-Access pass"`. The foundation test ports the
  repository half only. Add the dayView half as `func testTheScheduleStillLoadsWithoutColocatedJsonDayView()`
  in `Tests/KCNA26CoreTests/Schedule/ColocatedRepositoryTests+Schedule.swift` (an `extension
  ColocatedRepositoryTests`), looping over `Self.colocatedJsonFailures()` with
  `Self.loadWith(text)`.

## Known platform differences (documented, deliberate)

- Lone UTF-16 surrogates (in JSON `\uD800` escapes) become U+FFFD: Swift strings can't hold them.
- `roundToInt()` of NaN returns 0 (Kotlin throws).
- Kotlin unit tests run regexes on the desktop JVM (ASCII `\s`); `KRegex` is ICU, like Android devices.
- JSON numbers written by the serializer from Swift Doubles use Swift's shortest form ("1e+20"
  where Kotlin writes "1.0E20"); both are valid JSON and parse to the same value.
- `JSON.parse` rejects nesting deeper than `JSON.maxDepth` (200; kotlinx has no limit) and
  numbers with leading zeros such as `[01]` (kotlinx's lenient mode reads them as 1), as well as
  unquoted string tokens. The data files use none of these.
- Swift `String` equality / hashing use canonical equivalence (see Strings above); use the
  `kotlin*` UTF-16 helpers where Kotlin's exact comparison matters on non-NFC text.
- `lowercased()` does not apply Java's final-sigma rule (`"ΟΔΟΣ"` -> "οδοσ", Java "οδος").
- `UserDefaultsStore` reads an `Int` written value with `int64(forKey:)` and vice versa
  (Android throws ClassCastException); see KeyValueStore.
