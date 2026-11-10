# KCNA26 SwiftUI conventions

The shared UI API of the iOS app: theme (colours, type, dimensions, icons), the shared
components, the environment, and the rules for the screen ports. Read it with
`ios/Core/CONVENTIONS.md` (Core API) before writing a view. Keep it accurate when you change
anything under `Sources/Theme` or `Sources/Components`.

The Kotlin app (`android/app/src/main/java/app/kcna26`) is the specification. Its theme is
`theme/*.kt`; the components here come from `ui/schedule/ScheduleParts.kt` and the small visual
pieces several screens share.

## Files

```
ios/KCNA26/Sources/
  Theme/        Color.swift (AppColors), Type.swift (AppType, AppTextStyle, CapsText),
                Theme.swift (environment, .kcnaTheme(), page layout), WidthClass.swift,
                AppIcon.swift
  Components/   ScheduleParts.swift (Pill, RuledHeading, UpNextLine, EmptyState,
                ScheduleFooter, speakersLine), CardSurface.swift (cardSurface, dashedOutline,
                mineShadow, tileSurface), FlowRow.swift, SectionLabel.swift (SectionLabel,
                HairlineDivider), Buttons.swift (InkButtonStyle, OutlineButtonStyle),
                SearchField.swift, ThemePreview.swift
  App/ Schedule/ Going/ Session/ Settings/ Directions/ Platform/   the screen ports
```

Everything under `Sources/` is compiled into the app target (a synchronized folder; other files
are copied into the bundle, so docs stay outside `Sources/`). Core
(`ios/Core/Sources/KCNA26Core`) is in the same module: use its types directly, never
`import KCNA26Core`.

## Installing the theme (app shell)

```swift
WindowGroup {
    RootView()
        .kcnaTheme()            // AppColors for the colour scheme, AppType, tint = you, foreground = ink
        .kcnaPageBackground()   // bg under everything, safe areas included (Kotlin root Surface)
        .readsWindowWidth()     // \.widthClass and \.windowWidth from the window size
}
```

`.kcnaTheme()` reads `\.colorScheme` where it is applied (light/dark follow the system; nothing
in the app overrides it). Sheets and navigation destinations inherit the environment. The
environment it sets only reaches the view it modifies, so a modifier chained after it does not
see `\.appColors` (it gets the light default): `.kcnaPageBackground()` therefore picks its
palette from `\.colorScheme` and works on either side; any other theme-reading modifier goes
inside (on `RootView`'s content), never after `.kcnaTheme()`.

System containers do not read `AppColors` (Kotlin mapped them through the Material scheme: page
and bars = `bg`, sheets/cards/menus = `surface`). Set them where you use them:
`.scrollContentBackground(.hidden)` + a `bg` background for `List` / `Form`,
`.toolbarBackground(colors.bg, for: .navigationBar)`, `.presentationBackground(colors.bg)` on a
sheet's content (Kotlin `containerColor = c.bg`; the details pane on wide windows is `surface`).

## Reading the theme in a view

```swift
@Environment(\.appColors) private var colors    // Kotlin AppTheme.colors
@Environment(\.appType) private var type         // Kotlin AppTheme.type
@Environment(\.widthClass) private var widthClass   // Kotlin LocalWidthClass.current
@Environment(\.windowWidth) private var windowWidth // Kotlin currentWindowWidth()
```

Never hard-code a colour, font name or size that the theme has.

### Colours (`AppColors`, Theme/Color.swift)

Built from Core's `AppPalette` (`colors.palette` gives the 0xAARRGGBB values). Same role names
as Kotlin `AppColors`:

| Role | Use |
|---|---|
| `bg`, `surface`, `ink`, `muted`, `line` | page, cards/sheets/inputs, text, secondary text, hairlines |
| `you` (`pink`), `onYou` | "you / now / live" pink and the text on it |
| `anthropic` (`clay`), `onAnthropic` | Anthropic colleagues |
| `category(key)`, `categories` | category colours; `muted` for an unknown key |
| `color(of: Category)` | a schedule.json category's own colour (Kotlin `Category.color(dark)`) |
| `liveBorder`, `anthropicCardBg`, `anthropicCardBorder`, `anthropicRowBg`, `pressed`, `scrim`, `mapMe`, `mapHyatt`, `note` | derived colours of Color.kt |
| `primaryContainer`, `secondaryContainer`, `tertiaryContainer`, `surfaceVariant` | Kotlin Material scheme containers |
| `goingCardBg`, `goingCardBorder`, `goingRowBg`, `goingRule`, `clash`, `clashBg`, `clashBorder` | the Going accents of `ui/going/GoingUi.kt` (defined here because Schedule, Going and Session all use them: do not redefine them) |
| `isDark` | Kotlin `isDark` / `isDarkTheme()` |

Kotlin -> Swift: `c.x.copy(alpha = a)` -> `colors.x.opacity(a)` (the roles are opaque, except
`anthropicRowBg`, `pressed`, `scrim`, `goingRowBg`); a one-off `mix(a, b, f)` ->
`Color(argb: mixARGB(colors.palette.a, colors.palette.b, f))`; `Color.Transparent` ->
`Color.clear`; `Color.White` -> `colors.onYou`. `Color(argb:)` builds a colour from a
palette value.

### Typography (`AppType`, Theme/Type.swift)

Every Kotlin `AppType` style has the same name and values: `brand`, `clock`, `dayTabLabel`,
`dayTabNumber`, `badge`, `dayHeading`, `status`, `slotHeading`, `nowLine`, `meta`, `pill`,
`cardTitle`, `cardTitleMine`, `small`, `tiny`, `kidTime`, `kidTitle`, `body`, `description`,
`sheetTitle`, `sectionLabel`, `button`, `bannerLabel`, `bannerCountdown`, `bannerTime`,
`bannerTitle`, `routeSummary`, `step`, `levelBadge`, `display`, `displayLarge`. The Material roles
(Kotlin `KcnaTypography`) are `type.material.bodyLarge` etc.; nothing uses them implicitly.

```swift
Text(verbatim: s.title)
    .appTextStyle(type.cardTitle)                 // Kotlin style = t.cardTitle
    .foregroundStyle(colors.ink)                  // colours are never part of a style
CapsText(label, style: type.meta, color: colors.muted, lineLimit: 1)   // every Barlow style
type.cardTitle.copy(size: 17)                     // Kotlin .copy(fontSize = 17.sp) (keeps the line height, as Compose)
type.slotHeading.copy(size: 20, lineHeight: 22, letterSpacing: type.brand.letterSpacing)
type.meta.bold                                    // .copy(fontWeight = FontWeight.Bold)
Text(verbatim: name).appFont(type.small.bold)     // a span inside Text + Text (SpanStyle)
```

- `AppTextStyle`: `family` (`.barlow` / `.atkinson`), `weight` (`.regular` / `.semibold` /
  `.bold`; the face falls back like Android: Barlow regular -> SemiBold, Atkinson semibold ->
  Bold), `size` (pt = sp), `letterSpacing` (em), `lineHeight` (pt, absolute), `tabularNumbers`
  (all Barlow styles: Kotlin `tnum` -> `Font.monospacedDigit()`); `font`, `tracking`.
- `.appTextStyle(style)` sets the font, the letter spacing and the line height the way Compose
  applies it by default (`LineHeightStyle.Default`: Proportional, `Trim.Both`, `Mode.Fixed`;
  Compose ui-text 1.12, BOM 2026.09): a single line keeps the font's natural height
  ((ascent + descent) x size: 1.2 em Barlow, 1.24 em Atkinson) and only the baseline distance of
  wrapped lines follows `lineHeight`, i.e. `lineSpacing = lineHeight - natural`. No padding is
  added, so it can go on a `Text`, a `TextField` or a container of texts. Wrapped lines of a
  style tighter than the font (Barlow below 1.2 em) keep the font's spacing: iOS 17 has no
  negative line spacing (slightly taller than Android). All of it scales with Dynamic Type
  (`@ScaledMetric` relative to the style's text style).
- Dynamic Type: every font is `Font.custom(_:size:relativeTo:)` with the iOS text style nearest
  in default size (`AppTextStyle.dynamicTypeStyle(forSize:)`). Do not wrap text in fixed
  heights; use `minHeight`.
- Inside a `Text` concatenation use `.appFont(style)` (font and tracking) and
  `.foregroundStyle(color)` on the span (iOS 17 `Text` overloads); apply `.appTextStyle` to the
  whole result. Bold spans need the bold style (`style.bold`), not `.bold()`.
- `CapsText(text, style:, color:, lineLimit:)` uppercases with Core's `caps()` (Locale.ROOT).
  VoiceOver reads the original text. `lineLimit` (Kotlin `maxLines`) truncates with "…" where
  Compose clipped.

Fonts (Resources/Fonts, all four listed in Info.plist `UIAppFonts` as `Fonts/<file>`); use them
only through `AppTextStyle` / `AppFontFace`:

| File | PostScript name (`Font.custom`) | Weight |
|---|---|---|
| barlow_condensed_semibold.ttf | `BarlowCondensed-SemiBold` | 600 |
| barlow_condensed_bold.ttf | `BarlowCondensed-Bold` | 700 |
| atkinson_hyperlegible_regular.ttf | `AtkinsonHyperlegible-Regular` | 400 |
| atkinson_hyperlegible_bold.ttf | `AtkinsonHyperlegible-Bold` | 700 |

Vertical metrics (hhea = OS/2 typo, same on both platforms): Barlow ascent 1.0 em, descent
0.2 em; Atkinson 0.95 / 0.29.

### Dimensions and layout

- Core `Dimens` (points): `touchTarget` 48 (kept from Android, above the 44 pt HIG minimum),
  `pagePadding` 16, `cardGap` 8, `cardRadius` 10, `bannerRadius` 14, `sheetRadius` 18,
  `categoryStripe` 4, `maxContentWidth` 760, `maxTextWidth` 620, `mediumBreakpoint` 600,
  `expandedBreakpoint` 840. They are `Double`: write `CGFloat(Dimens.x)` in non-trivial
  expressions.
- `PageLayout.sidePadding(forWidth:maxContent:)`: Kotlin
  `max(Dimens.pagePadding, (maxWidth - Dimens.maxContentWidth) / 2)` (Settings passes
  `Dimens.maxTextWidth`). Get the width from a `GeometryReader` around the screen, like the
  Kotlin `BoxWithConstraints`.
- `.widthIn(max: CGFloat(Dimens.maxTextWidth))`: Kotlin `Modifier.widthIn(max = ...)`
  (leading-aligned frame).
- `WidthClass` (`.compact` < 600 <= `.medium` < 840 <= `.expanded`, `isWide`,
  `WidthClass.fromWidth(_:)`): Kotlin `ui/adaptive/WidthClass.kt`. Wide windows (iPad, iPhone
  landscape, wide Split View) use the list–detail layout. Read `\.widthClass`; the shell sets it
  with `.readsWindowWidth()` (full window width, safe-area insets included, like Android). The
  enum is Core's (Core/Sources/KCNA26Core/UILogic/Adaptive/WidthClassRule.swift);
  Theme/WidthClass.swift holds only the environment part (`\.widthClass`, `\.windowWidth`,
  `.readsWindowWidth()`).

## Components (Sources/Components)

| Component | Usage |
|---|---|
| `Pill` | `Pill("Anthropic", tone: .anthropic)`; tones `.you` (Live, You), `.onYou` (on my pink cards), `.anthropic`, `.clash`; `Pill(tag, background: .clear, content: muted, border: colors.line)` for the outlined `.tag`; `size:` `.regular` (cards), `.large` (details), `.badge` (details speaker badge, day tab "YOU"), `.kid` (group card kid rows). Strings come from Core (`SessionText`, `GoingText`, `CardStatus.liveLabel`). |
| `RuledHeading` | `RuledHeading(slot.label)` / `RuledHeading(title, topPadding: 16)`: uppercase heading + hairline on `bg`, a VoiceOver heading. Sticky: the header of a `Section` in `LazyVStack(pinnedViews: [.sectionHeaders])`. |
| `UpNextLine` | `UpNextLine()`: pink "UP NEXT" + 2 pt rule. |
| `EmptyState` | `EmptyState(title: ScheduleRows.WRAP_TITLE, text: ScheduleRows.WRAP_TEXT)` (texts from Core's UILogic port of ScheduleRows.kt / GoingLogic `emptyText`): dashed box. |
| `ScheduleFooter` | `ScheduleFooter()`: the list footer ("Times are MST. …"). |
| `speakersLine` | `speakersLine(s.speakers, me: me, anthropic: index.anthropicSpeakers, colors: colors, onMine: mine, style: type.small)` returns a `Text`; then `.appTextStyle(type.small).foregroundStyle(mine ? colors.onYou : colors.muted)`. Me in bold ("You"), Anthropic colleagues bold clay. |
| `.cardSurface(...)` | `.cardSurface(fill:, border:, stripe:, progress: status.progress, progressColor: colors.you, ring: selected ? colors.ink : nil)`: the `.card` look (fill, 1 pt border, 4 pt stripe, 3 pt live bar, 2 pt selection ring); clips and sets the tap shape. `edges: .top` / `.bottom` = Kotlin `cardSegment` (a co-located card and its attached agenda). Pad the content yourself (`leading: Dimens.categoryStripe + 12, trailing 12, top 9, bottom 10`). |
| `.mineShadow(colors.you)` | the pink glow under my cards and the banner; after `cardSurface` (composites the card first, so it casts one shadow). |
| `.dashedOutline(colors.line, radius:)` | the `.lrow` / `.empty` dashed outline (break rows). |
| `.tileSurface(selected:)` | ink when selected, else surface + line border: day tabs, Going chip, reminder options. Content colour is the caller's (`bg` / `ink`). |
| `FlowRow` | `FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) { ... }`: Compose `FlowRow` (meta rows, pills, link rows, where lines). |
| `SectionLabel` | `SectionLabel("Speakers")`: `sectionLabel` style, muted, a heading; padding is the caller's. `isHeading: false` for non-heading labels (the Directions top bar). |
| `HairlineDivider` | `HairlineDivider()` / `HairlineDivider(.vertical)` / `HairlineDivider(color: colors.onYou.opacity(0.3))`: Compose `HorizontalDivider` / `VerticalDivider` (1 pt, `line`). |
| `InkButtonStyle` | `Button { } label: { CapsText(SessionText.SLIDES, style: type.button) }.buttonStyle(InkButtonStyle(horizontalPadding: 16))`; `.buttonStyle(.ink)`; `minHeight: 56, fillsWidth: true` for the Directions bar. Disabled: `line` fill, `muted` text. |
| `OutlineButtonStyle` | the same with a hairline border, ink text (`.buttonStyle(.outline)`); `shape: .capsule` for Material's default shape (Kotlin's Skip). |
| `SearchField` | `SearchField(text: $query, placeholder: "Search talks, speakers, rooms", focus: $searchFocused)`; `autocapitalization: .words` for speaker names. |
| `AppIconImage` | `AppIconImage(.star, size: 23).foregroundStyle(colors.ink)`: a Material `Icon` of that size; `label:` for a `contentDescription`. |
| `ThemePreview` | `#Preview("X") { ThemePreview { X() } }`: light and dark panes. |

Not here (screen-specific, ported with their screens): the star toggle, Going chip, Going card
and clash note (`Going/`, from GoingUi.kt: the schedule cards and the details use them from
there), session/group/co-located cards, kid rows, banner, day tabs, details parts, Directions
views. A group card's inline kid pills: Compose draws them inside the title text; SwiftUI cannot
put a background on a `Text` span, so put `Pill(..., size: .kid)` before the title in an
`HStack(alignment: .firstTextBaseline)`.

## Icons (`AppIcon`, Theme/AppIcon.swift)

Every Material icon used in `ui/` and `nav/`. Use `Image(appIcon: .x)` or
`AppIconImage(.x, size:)`; never `Image(systemName:)` directly.

| Kotlin | `AppIcon` | SF Symbol | Where |
|---|---|---|---|
| `Icons.Rounded.Star` | `.star` | `star.fill` | going: card star, chip, "Up next" row, details button |
| `Icons.Rounded.StarBorder` | `.starBorder` | `star` | not going |
| `Icons.AutoMirrored.Filled.DirectionsWalk` | `.directionsWalk` | `figure.walk` | Directions buttons |
| `Icons.Rounded.NotificationsOff` | `.notificationsOff` | `bell.slash.fill` | notifications-off hint |
| `Icons.AutoMirrored.Rounded.ArrowBack`, `Icons.AutoMirrored.Filled.ArrowBack` | `.arrowBack` | `chevron.backward` | back (the NavigationStack back button replaces it) |
| `Icons.Rounded.Check`, `Icons.Filled.Check` | `.check` | `checkmark` | chosen speaker, chosen "from" place |
| `Icons.Rounded.Search` | `.search` | `magnifyingglass` | search fields |
| `Icons.Rounded.Close` (search) | `.clearSearch` | `xmark.circle.fill` | "Clear search" |
| `Icons.Filled.Close` (sheet) | `.close` | `xmark` | details "Close" |
| `Icons.Rounded.ExpandLess` | `.expandLess` | `chevron.up` | open co-located card, "Hide agenda" |
| `Icons.Rounded.ExpandMore` | `.expandMore` | `chevron.down` | closed co-located card |
| `Icons.Rounded.Settings` | `.settings` | `gearshape.fill` | schedule header |
| `Icons.Filled.FitScreen` | `.fitScreen` | `viewfinder` | map refit button |
| `Icons.Outlined.MyLocation` | `.myLocation` | `location` | "from": live location |
| `Icons.AutoMirrored.Outlined.Login` | `.login` | `arrow.right.to.line` | "from": an entrance |
| `Icons.Outlined.MeetingRoom` | `.meetingRoom` | `door.left.hand.open` | "from": a room |

The notification small icon `ic_stat_pin` has no iOS counterpart (notifications show the app
icon). The Directions step icons (RouteViews.kt `StepIcon`) are drawn, not Material icons: port
them with `Canvas` / `Path` in `Directions/`.

## Rules for the screen ports

- **Where**: one folder per Kotlin package (`Schedule/` for `ui/schedule/*.kt`, ...); file names
  = Kotlin file names (`ScheduleCards.swift`). Shared small views go to `Components/` only if two
  screens use them; then add them to the table above.
- **Names**: Kotlin names (`SessionCard`, `DayHeading`, `MineBannerCard`). Unique across Core and
  the app (one module): never declare `Category`, `Session`, `Room`, `Day`, `Venue`, `DayView`,
  `Block`, `Slot`, `DayTab`, `MineBanner`, `ColoCard`, `Layout`, `Axis`, ... Check with
  `grep -rn "struct X\b\|enum X\b\|class X\b" ios/Core/Sources ios/KCNA26/Sources`.
- **Logic stays in Core**: rules, strings, sorting, filtering, formatting come from Core
  (`ScheduleIndex`, `ScheduleLogic`, `TimeFormat`, `SessionText`, `GoingText`, ...). The
  `ui/*` ports (`SessionText`, `GoingText`, `ScheduleRows`, `GoingLogic`, ... named in this file)
  go to Core `UILogic/<Screen>/`; they may not exist yet when you read this: grep
  `ios/Core/Sources/KCNA26Core` for the exact names before using one. A view
  only lays out. Texts that Kotlin writes inline in a composable are copied verbatim
  (typographic characters included) with `Text(verbatim:)`.
- **Kotlin -> SwiftUI**: `Column`/`Row`/`Box` -> `VStack`/`HStack`/`ZStack` (spacing 0 and
  explicit padding to keep the Kotlin geometry; `alignment: .leading` for `Column`);
  `Spacer(Modifier.width(x))` -> `.padding` or a `spacing:`; `Modifier.weight(1f)` ->
  `.frame(maxWidth: .infinity)`; `FlowRow` -> `FlowRow`; `LazyColumn` + `stickyHeader` ->
  `ScrollView { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) }`;
  `clickable(role = Button)` -> `Button { } label: { }.buttonStyle(.plain)` (tap shape from
  `cardSurface`/`contentShape`); `toggleable(role = Checkbox)` -> `Button` with
  `.accessibilityAddTraits(.isToggle)` (iOS 17) and `.accessibilityValue`, or `Toggle`;
  `semantics { heading() }` -> `.accessibilityAddTraits(.isHeader)`; `contentDescription` ->
  `.accessibilityLabel(Text(verbatim:))`; `onClickLabel` -> `.accessibilityHint`;
  `clearAndSetSemantics` -> `.accessibilityElement(children: .ignore)` + label;
  `heightIn(min = Dimens.touchTarget)` -> `.frame(minHeight: CGFloat(Dimens.touchTarget))`;
  `maxLines` -> `.lineLimit`; `ModalBottomSheet` -> `.sheet` + `.presentationDetents` +
  `.presentationDragIndicator(.visible)` (the GrabBar); `IconButton` -> `Button` with a 48 pt
  frame; `TextButton` -> `Button` + `.buttonStyle(.borderless)` with the Kotlin colour;
  haptics `ToggleOn/Off` -> `.sensoryFeedback(.selection, trigger:)`; `LocalUriHandler` ->
  `@Environment(\.openURL)`; `BackHandler` -> NavigationStack / sheet dismissal.
- **Accessibility**: VoiceOver labels = the Kotlin `contentDescription`s and `stateDescription`s;
  hit targets at least 44 pt (the app uses 48); support Dynamic Type (no fixed text heights).
- **iOS 17 only**: no API newer than iOS 17 without `if #available`. `.onChange(of:) { old, new in }`,
  `@Observable` + `@Environment(Type.self)`, `foregroundStyle`, `NavigationStack`.
- **Previews**: every view file ends with `#Preview` blocks wrapped in `ThemePreview` (light and
  dark). Feed them fakes, never real persistence or network: `try! Repository.bundled()` (the
  bundled data is in the app bundle), `SettingsStore(InMemoryStore())`,
  `GoingStore(InMemoryStore())`, `ReminderStore(InMemoryStore())`,
  `try! FixedClock.parse("2026-11-11T10:20:00-07:00")` (a conference morning), `NowTicker(clock:
  ..., running: false)`. Keep preview code simple: it compiles in every build configuration.
- **Checking without Xcode**: `swiftc -parse <file>` must print nothing; grep Core for every
  symbol you use; the lead compiles on macOS CI.

## App shell (Sources/App) and platform services (Sources/Platform)

Kotlin `MainActivity.kt` (UI parts), `nav/AppNav.kt`, `KcnaApp.kt` process wiring. The logic is
Core's (`AppGraph`, `NavModel`, `AppNavLogic`, `MainActivityLogic`; see "App graph, navigation
and reminder scheduling" in ios/Core/CONVENTIONS.md); the shell only wires and lays out.

```
App/       KCNA26App.swift (@main, scenePhase), AppDelegate.swift (UNUserNotificationCenter delegate,
           willTerminate), AppGraph+Live.swift (AppGraph.shared), RootView.swift (rootState, per-window
           NavModel + @SceneStorage, first-run sheet, tapped-reminder routing), AppNav.swift
           (NavigationStack, ScheduleLayer, details sheet/pane, EmptyDetailsHint), SceneEnvironment.swift
Platform/  NotificationCenterReminders.swift (ReminderScheduling), NotificationCenterPermission.swift
           (NotificationPermission), NotificationCenterDelegate.swift, DirectionsLocationService.swift
           (CoreLocation for Directions), SystemLinks.swift (Settings pages, URLs)
```

- **Lifecycle**: `KCNA26App.init` installs the compass declination source and calls
  `AppGraph.shared.start(arguments:)`; the App-level `scenePhase` (`onChange(initial: true)`)
  calls `graph.onForeground()` on `.active` and `graph.onBackground()` on every other phase;
  `applicationWillTerminate` calls `onBackground()` too. Screens never call these.
- **Root**: `graph.rootState` -> `.loading` (the `bg` page, same colour as `LaunchBackground`),
  `.failed(text)` (the Core text in `type.material.bodyLarge`, 24 pt padding), `.ready` (the
  window's shell). Root modifiers: `.environment(graph)`, `.kcnaTheme()`,
  `.kcnaPageBackground()`, `.readsWindowWidth()`.
- **Navigation**: one `NavModel` per window (scene), restored from and mirrored into
  `@SceneStorage(NavModel.KEY_STACK / KEY_SESSION)`. `NavigationStack(path: $nav.path)` rooted at
  the Schedule; `.navigationDestination(for: Screen.self)`: `.settings` -> `SettingsScreen`,
  `.directions(id)` -> `DirectionsScreen`. The system back button / edge swipe pops (the path
  setter writes the stack back). The Schedule root hides the navigation bar
  (`.toolbar(.hidden, for: .navigationBar)`, it draws its own header); pushed screens get the
  system bar (style it with `.toolbarBackground(colors.bg, for: .navigationBar)` and a title).
- **Session details** (`AppNavLogic`): wide (`widthClass.isWide`): the list at
  `AppNavLogic.listPaneWidth(windowWidth)`, a vertical hairline, then the pane on `surface`
  (`SessionDetails(...).id(id)` or the "Pick a session" hint). Compact: `.sheet(item:)` with
  `SessionSheet(...).id(id)`, `.presentationDetents([.medium, .large])` opening at `.large`;
  shown only while the Schedule is on top (pushing Directions hides it, back shows it again,
  `openSessionId` is kept) and the first-run sheet is not up. A swipe-down closes the session;
  the window turning wide moves the details into the pane. Stale ids are dropped
  (`AppNavLogic.dropsStaleSession`). Escape on a hardware keyboard closes the wide pane's
  session (`AppNavLogic.backAction`).
- **First-run sheet**: `.sheet(isPresented:)` while `graph.showsFirstRunSheet`, detents
  `[.large]`; a swipe-down = `settings.dismissFirstRunForNow()`. The content finishes with
  `settings.finishFirstRun(name)` (closes it), never `dismiss()`.
- **Sheet presentation split**: the shell owns `.sheet` and `.presentationDetents`; the
  content view owns the rest (`.presentationBackground`, `.presentationCornerRadius`,
  `.presentationDragIndicator`). Do not set detents inside the content.
- **Reminder taps**: `NotificationCenterDelegate` -> `graph.notificationTapped(sessionId:)`;
  the window's root calls `graph.routePendingDirections(to: nav)` on appear and on
  `.onChange(of: graph.pendingDirectionsSessionId)` (Schedule with the details -> Directions).
  `willPresent` shows a reminder only if `graph.reminderFiring(...)` `.shows` (banner, list,
  sound); other notifications always show.

### Environment provided by the shell

```swift
@Environment(AppGraph.self) private var graph          // Kotlin LocalAppGraph.current (repository, settings, going, clock, details, router, dataSync, …)
@Environment(NavModel.self) private var nav            // this window's navigation (screens normally use their callbacks instead)
@Environment(\.detailsScrollCarry) private var carry   // DetailsScrollCarry? for this window (nil in previews)
```

### Screen entry points

The shell calls exactly these (stubs exist until the screen agents replace them; keep the
signatures, explicit `init`s, as shown). Closures are called on the main actor.

| File | Entry point | Called with |
|---|---|---|
| Schedule/ScheduleScreen.swift | `ScheduleScreen(selectedSessionId: String?, onOpenSession: @escaping (String) -> Void, onOpenDirections: @escaping (String) -> Void, onOpenSettings: @escaping () -> Void, twoPane: Bool)` | the shown session (sheet or pane), `nav.openSession`, `nav.openDirections`, `nav.openSettings`, `widthClass.isWide`; it fills its frame (the list pane's width when wide) |
| Session/SessionDetails.swift | `SessionDetails(sessionId: String, onDirections: @escaping (String) -> Void, contentPadding: EdgeInsets = EdgeInsets(), onClose: (() -> Void)? = nil)` | wide pane: `nav.openDirections`, `onClose: nav.closeSession`, no extra padding (the safe area reaches the scroll view); keyed `.id(sessionId)`; the pane is `surface` |
| Session/SessionSheet.swift | `SessionSheet(sessionId: String, onDismiss: @escaping () -> Void, onDirections: @escaping (String) -> Void)` | compact sheet content: `onDismiss: nav.closeSession` (the × button), `nav.openDirections`; keyed `.id(sessionId)` |
| Settings/SettingsScreen.swift | `SettingsScreen(onBack: @escaping () -> Void)` | pushed; `onBack: nav.pop` |
| Settings/FirstRunSheet.swift | `FirstRunSpeakerSheet()` | the first-run sheet content (reads `graph` itself) |
| Directions/DirectionsScreen.swift | `DirectionsScreen(sessionId: String, onBack: @escaping () -> Void)` | pushed (also from a reminder tap); `onBack: nav.pop` |

### Platform services (Sources/Platform)

| Type | Use |
|---|---|
| `DirectionsLocationService` | `@MainActor @Observable`, one per Directions screen: `@State private var location = DirectionsLocationService()` (cheap `init`; the `CLLocationManager` is made on the first start). Put `.tracksDirectionsLocation(location, for: vm)` on the live Directions content: it starts location + compass while the view is on screen in an `.active` scene, stops otherwise, keeps the screen on meanwhile (Kotlin `KeepScreenOn`) and follows rotations for the compass. It feeds the `DirectionsViewModel` (`onLocation`, `onHeading`, `trackingStarted/Stopped`, `onLocationFailure`, `setDeviceLocationOff`) as Core's `LocationTracker` / `CompassSensor` say, and asks for When-In-Use authorization once per screen. `location.locStatus(vm)` -> `LocStatus` for `DirectionsLogic.readout`; `location.authorization` (observable); `location.requestAccess()` for "Allow location" / "Turn on location" (the dialog while `.notDetermined`, else the app's Settings page); `location.refreshOrientation()` if the screen sees a size change itself. `DirectionsLocationService.installDeclinationSource()` runs at launch. |
| `SystemLinks` | `@MainActor`: `openAppSettings()`, `openNotificationSettings()`, `open(url)` / `open(string)` for non-view code (views use `@Environment(\.openURL)`), `await SystemLinks.turnOnNotifications(graph)` = the notifications-off hint's "Turn on" (`NotificationAsk.turnOn`: the system dialog via `graph.requestNotificationsNow()`, else the notification settings). |
| `NotificationCenterReminders`, `NotificationCenterPermission`, `NotificationCenterDelegate` | wired by the shell (`AppGraph.shared`, `AppDelegate`); screens read the permission through `graph.notificationPermission.status()`. |

## Directions (Sources/Directions)

Kotlin `ui/directions/DirectionsScreen.kt`, `VenueMap.kt`, `RouteViews.kt`, `DirectionsReadout.kt`.
The logic is Core's: `DirectionsViewModel` (location, heading, From choice, plan, calibration),
`DirectionsLogic.readout`, `FloorReminder`, `FromOptions` / `FromMenu`, `MapGeometry`, `SvgPath`,
`MapFraming`, `MapCameraState` (UILogic/Directions), and the views' inline rules in
`DirectionsScreenUI` + `ConeAngleTracker` (UILogic/Directions/DirectionsScreen+UI.swift: top bar
label, unavailable text, location action, readout/headline runs, menu row texts, step icon
roles, compact map height, map label rules, pulse, figure 8, camera storage).

| File | Views (internal unless noted) |
|---|---|
| DirectionsScreen.swift | `DirectionsScreen(sessionId:onBack:)` (the entry point), `DirectionsScreenModels` (`@MainActor @Observable`: the screen's `DirectionsViewModel`, rebuilt per `Repository` identity, and its `MapCameraState`); private `DirectionsTitle`, `DirectionsUnavailable`, `LiveDirections`, `RouteCard`, `MapNote` |
| VenueMap.swift | `VenueMap(venue:room:points:live:here:fix:heading:camera:)`; `Path(svgCommands: SvgPath.parse(d))` (SVG path data -> SwiftUI `Path`, reusable); private layers `MapBaseLayer`, `MapDestinationLayer`, `MapMeLayer` / `MapMeCanvas` (Animatable cone), `NorthRose`, `RefitButton` |
| RouteViews.swift | `StepIcon(kind)` (34 pt, drawn), `StepsList(steps:)`, `FromPicker(options:selected:expanded:onExpandedChange:)` (the outlined "From" field), `FromMenuSheet(menu:selected:onPick:)` (the open menu, as sheet content) |
| DirectionsReadout.swift | `FloorHeadline(reminder:)`, `FloorInstruction(reminder:)`, `LiveReadout(readout:floor:action:onAction:calibrate:)`, `CalibrationHint()`; `directionsRunsText(runs, style:, colors:)` (`[TextRun]` -> `Text`), `DirectionsAnnouncer.announce(_:)` (queued VoiceOver announcement) |

- **Header**: the system navigation bar (inline; back = the system's) shows the Kotlin top-bar
  label ("DIRECTIONS · WED 5:00–5:30 PM", `sectionLabel`, muted) as its principal item and as the
  navigation title; the session title (`cardTitle`, 2 lines) is the first row of the content.
  `onBack` stays in the signature but nothing calls it (the system back pops).
- **Location**: `@State DirectionsLocationService` + `.tracksDirectionsLocation(location, for: vm)`
  on `LiveDirections` only (not on the unavailable variant); `location.locStatus(vm)` feeds the
  readout; "Allow location" / "Turn on location" call `location.requestAccess()`.
- **State above the compact/wide branch** (Kotlin's hoisted `rememberSaveable`s): the From
  sheet's open flag and its sort point (`fromAt`, the fix when it opened) and the camera live in
  `DirectionsScreen`; the camera is also saved in `@SceneStorage("kcna26.directions.camera")`
  (`DirectionsScreenUI.storedCamera(sessionId, MapCameraState.Saver.save(cam))`) when the scene
  leaves `.active`, restored on the next creation for the same session, and cleared when the
  screen is popped.
- **From picker**: Kotlin's `ExposedDropdownMenu` is a `.sheet` (detents medium/large, presented by
  `LiveDirections`, content `FromMenuSheet` on `surface` with the drag indicator): a SwiftUI `Menu`
  reports no open/close and rebuilds while open, so the menu could not be sorted from the fix at
  opening and frozen. A new sheet per opening starts at the top. Picking: `vm.setFrom(key)` then
  `camera.refit()`.
- **Map**: three `Canvas` layers in a `ZStack` inside `TimelineView(.animation(paused:
  !camera.isAnimating))` (`camera.camera ?? MapFraming.fit(...)` per frame). The destination
  layer has its own `TimelineView` for the pulse (paused with Reduce Motion: the still ring); the
  me layer reads `heading()` itself (many updates a second) and animates the cone with
  `interpolatingSpring(stiffness: 300, damping: 2·√300)` (Compose `spring(1f, 300f)`), snapping
  when it appears (`ConeAngleTracker`). Framing: the map calls `camera.frame` on appear and when
  size/route/destination change, `camera.updateMe` when the fix moves; the SCREEN calls
  `camera.stopFraming()` on disappear (a compact/wide switch replaces the map, and the old map's
  `onDisappear` would otherwise cancel the new one's framing). Labels: resolved `Text` drawn 8×
  offset in the halo colour, then filled (Compose: a 3 dp stroke behind the fill).
- **Gestures**: `DragGesture(minimumDistance: 8)` simultaneously with `MagnifyGesture`, turned into
  Compose's per-step values for `camera.onGesture` (pan = Δtranslation, zoom = magnification /
  last). The first drag event only starts tracking (Compose drops the touch-slop movement: a tap
  never goes manual). While a pinch runs it zooms around where it began and the drag does not
  pan (no current centroid in `MagnifyGesture`; avoids drift if the drag follows one finger).
  No double tap (Kotlin has none); the round "fit" button (`DirectionsText.REFIT`) re-fits.
- **Accessibility**: the map is one element labelled `DirectionsText.mapDescription`; the
  readout line is labelled `readout.line`, has `.updatesFrequently`, and its changes are
  announced queued behind current speech (Kotlin's polite live region); the headline reads
  `FloorReminder.headline`; menu rows have `.isSelected`, the kind icon's label
  ("Entrance"/"Room") and "40 m, Level 2".

## Schedule and RSVP UI (Sources/Schedule, Sources/Going)

Kotlin `ui/schedule/ScheduleScreen.kt`, `ScheduleHeader.kt`, `ScheduleCards.kt`,
`ColocatedCards.kt`, the UI side of `ScheduleRows.kt`, and `ui/going/GoingUi.kt`. The logic is
Core's: `ScheduleScreenLogic` (state, layout, events, jumps), `ScheduleRows` (+ `sections`),
`ScheduleCardsLogic`, `ColocatedCardsLogic`, `ScheduleHeaderLogic`, `GoingUiLogic`, `GoingLogic`,
`GoingText`, and the SwiftUI-side helpers `ScheduleRows.sections(_:)` / `ScheduleRowSection`
(UILogic/Schedule/ScheduleRows+UI.swift) and `ScheduleScreenLogic.encodeSet` / `decodeSet` /
`unstarredKey` / `SavedUnstarred` / `hideColoScrollTarget(_:_:cardTop:)`
(UILogic/Schedule/ScheduleScreenLogic+UI.swift).

| File | Views and helpers (internal unless noted) |
|---|---|
| Schedule/ScheduleScreen.swift | `ScheduleScreen(selectedSessionId:onOpenSession:onOpenDirections:onOpenSettings:twoPane:)` (the entry point); private `ScheduleScreenMemo`, `JumpAnchor`, `RowTopReader` |
| Schedule/ScheduleHeader.swift | `ScheduleHeader(clock:tabs:currentDay:searching:sidePadding:onDay:onSettings:)`, `ScheduleSearchField(text:focus:)`, `DayHeading(view, large:) { trailing }`, `SearchHeading(text, large:) { trailing }` (both also without `trailing`), `MineBannerCard(banner:onTalk:)`; private `DayTabs`, `HeadingLine`, `BannerCountdown` |
| Schedule/ScheduleCards.swift | `SessionCard(block:status:me:index:selected:wide:onOpen:going:clash:onToggleGoing:)`, `WhereLine(roomName:building:note:ink:muted:noteColor:)`, `BreakRow(session:index:)`, `GroupCard(block:now:me:index:expanded:selectedId:revealId:wide:onExpand:onOpen:onRevealed:goingIds:clashIds:onToggleGoing:)`, `KidRow(model:me:index:onOpen:onRevealed:onToggleGoing:)`, `KidListRule()`, `kidRowScrollId(_:)` |
| Schedule/ColocatedCards.swift | `ColoCardRow(cards:columns:open:index:onToggle:)`, `ColoAgendaCard(card:attached:me:index:selectedId:revealId:onHide:onOpen:onRevealed:goingIds:clashIds:onToggleGoing:)`; private `ColoEventCard`, `ColoLineText`, `HideAgendaButton`, `ColoBreakRow`, `ColoFooter` |
| Schedule/TextRuns.swift | `colors.color(role)` (Core `PaletteRole` -> `Color`, Kotlin's formula), `runsText(runs, style:, colors:)` (`[TextRun]` -> concatenated `Text`; bold runs in `style.bold`, roles coloured; apply `.appTextStyle(style)` + the line colour to the result) |
| Schedule/NowTicking.swift | `.ticksNow($ticker, clock:)` (runs a `NowTicker?` held in `@State`, created on first appearance: resumed on appear and when the scene leaves the background, paused on disappear / background), `NowTicking.now(ticker, clock:)` (the ticker's now while it runs, else the clock), `NowReader { now in … }` (a small view re-rendered every 15 s) |
| Going/GoingUi.swift | `StarToggle`, `GoingStarFrame`, `GoingMark`, `GoingChip`, `GoingNextCard`, `GoingToggleButton`, `GoingClashNote`, `ClashNote`, `ClashTag`, `GoingReminderHint`, `NotificationsOffHint`, `GoingReminderSetting` (below) |

RSVP views for the details and Settings (Kotlin names; each reads `graph` itself where Kotlin
read `LocalAppGraph`):

```swift
GoingClashNote(session: s)                    // details, under the pills: nothing unless starred and clashing; own 12 pt top margin
GoingReminderHint(session: s, padding: EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
    .widthIn(max: CGFloat(Dimens.maxTextWidth))   // details, above the buttons (Kotlin Modifier.widthIn(...).padding(bottom = 8))
HStack(spacing: 8) { GoingToggleButton(session: s); directionsButton }   // 56 pt, natural width; nothing for breaks
GoingReminderSetting()                        // Settings' "RSVPS" section (padding around it is the caller's)
NotificationsOffHint(channel: .going, padding: EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
StarToggle(going: g, onToggle: { … }, label: s.title, onCard: mine, iconSize: 23)   // 48 pt, haptic, VoiceOver "RSVP: <title>"
ClashTag(onCard: mine); GoingMark("RSVP’d to 2 of these"); GoingChip(on: on, onToggle: { … })
```

- **Hidden hints take no space only in a `VStack(spacing: 0)`**: `GoingReminderHint` and
  `NotificationsOffHint` stay in the hierarchy as a zero-size view while hidden (they must, to
  read the notification status), and apply their `padding` only while shown. In a stack with
  spacing the spacing would show; wrap them.
- **Notification status**: `NotificationsOffHint` reads `graph.notificationPermission.status()`
  in `.task(id:)` keyed by `NotificationAsk.asking` and `scenePhase == .active` (Kotlin
  `rememberNotificationsBlocked`'s `LifecycleResumeEffect`), so it updates after the system
  dialog and after the user comes back from Settings; "Turn on" is
  `SystemLinks.turnOnNotifications(graph)`.
- **Time**: `GoingClashNote` / `GoingReminderHint` use `NowReader` (Kotlin `rememberNowState`);
  the clash note works per minute (`ScheduleLogic.minuteOf`).

Schedule screen notes:

- **List**: `ScrollViewReader { ScrollView { LazyVStack(alignment: .leading, spacing: 0, pinnedViews:
  [.sectionHeaders]) } }`; the Kotlin flat rows (`st.rows(columns, open)`) go through
  `ScheduleRows.sections(_:)`: each sticky row (`.slotHead` -> `RuledHeading(slot.label)`,
  `.section` -> `RuledHeading(title, topPadding: 16)`) is a pinned `Section` header over the rows
  up to the next one (rows above the first heading: a header-less section). `ForEach` ids are the
  row keys (`row.key`), section ids `ScheduleRowSection.id`; horizontal padding = the layout's
  `side`, 16 pt at the bottom.
- **State**: `@SceneStorage("schedule.selectedDay" / "schedule.search" / "schedule.expanded" /
  "schedule.coloOpen" / "schedule.goingOnly" / "schedule.unstarred")` (Kotlin `rememberSaveable`;
  sets saved with `ScheduleScreenLogic.encodeSet`, `unstarred` with its key, reset when
  `unstarredKey` changes). The derived state is memoized (`ScheduleScreenMemo`, keyed by the
  inputs; rows by state generation, columns and open cards), since the body also runs on every
  15 s tick. `ScheduleIndex.prewarmSearch()` runs in `Task.detached` per index.
- **Jumps** (banner / "Up next" taps): `ScheduleScreenLogic.onTalk`; the pending jump is
  re-checked on every rows change (`jumpTarget`) and falls back after `JUMP_WAIT_MS`
  (`jumpFallback`). Kotlin `scrollToItem(i, -stickyPx)`: every row has an invisible 36 pt
  `JumpAnchor` (id `"jump-" + row.key`) ending at its top; scrolling it to `.top` puts the row
  under its pinned heading. A row not laid out yet is first scrolled to by its key (the anchor
  then exists). After the scroll `revealsAfterJump` sets `revealId`; the kid row
  (`kidRowScrollId(id)`) reports itself and the screen scrolls it into view with `anchor: nil`
  (Kotlin `bringIntoView`) and clears `revealId`. Day tabs scroll to the search row (Kotlin
  `scrollToItem(0)`).
- **Hiding an agenda**: co-located card rows record their top in the list viewport
  (`coordinateSpace(.named("schedule.list"))`); `hideColoScrollTarget(rows, key, cardTop:)`
  decides the scroll-back (no first-visible-index API on iOS 17).
- **Kid row pills**: Compose draws "You"/"Anthropic"/"Live"/"Clash" inline in the title; here they
  lead the title in an `HStack(alignment: .firstTextBaseline, spacing: 6)` (`Pill(size: .kid)`),
  so a long title wraps beside them rather than under them.
- **Not ported**: Kotlin's `BackHandler` (Back hides the keyboard, then clears the search) has no
  iOS counterpart: the keyboard's Search key hides it, the field's clear button clears it.

## Session details and Settings (Sources/Session, Sources/Settings)

Kotlin `ui/session/SessionSheet.kt`, `SessionDetailsParts.kt`, `DetailsScrollCarry.kt` and
`ui/settings/SettingsScreen.kt`, `FirstRunSheet.kt`, `DataSourceRow.kt`. The logic is Core's:
`SessionDetailsLogic` (states, meta, pills, getting there, about, links, Directions bar),
`SessionText` (every details string), `DescriptionFormat` (description blocks / runs),
`DetailsRepository` (`graph.details`), `DetailsScrollCarry`, `SettingsScreenLogic`,
`FirstRunSheetLogic`, `SpeakerPicker`, `DataSourceText`, and the iOS-only end of Settings in
`SettingsScreenLogic` "+UI" (UILogic/Settings/SettingsScreen+UI.swift: credits, font licences,
app version). Kotlin's `SessionText.kt` and `SpeakerPicker.kt` are pure, so they have no app
file (and must not: Core has `SessionText.swift` / `SpeakerPicker.swift`, file names are unique
in the one module).

| File | Views (internal unless noted) |
|---|---|
| Session/SessionDetails.swift | `SessionDetails(sessionId:onDirections:contentPadding:onClose:)` (the wide pane's entry point) |
| Session/SessionSheet.swift | `SessionSheet(sessionId:onDismiss:onDirections:)` (the compact sheet's content), `SessionDetailsContent(sessionId:onDirections:contentPadding:onClose:inSheet:)` (shared by both: loading, scroll, ×, Directions bar); private `LoadedDetails` |
| Session/SessionDetailsParts.swift | `DetailsBody(session:repo:room:result:showLoading:me:reserveCloseSpace:)`, `DescriptionText(blocks:)` (+ `DescriptionText.attributed(rich, style:, linkColor:)`: a `DescriptionFormat.Rich` as an `AttributedString`), `DirectionsBar(session:room:onDirections:showDivider:horizontalPadding:bottomPadding:)`, `GrabBar()`, `CloseButton(onClick:)` (the 48 pt × on a `bg` circle, "Close"); private `MetaRow`, `WhereRow`, `DetailsColoInfo`, `DetailsPills` / `DetailsPillsLine`, `DetailsSectionLabel`, `SpeakerItem`, `GettingThereLine`, `AboutSection`, `LinksRow`, `LinkButton` |
| Session/DetailsScrollCarry.swift | `DetailsScrollView(sessionId:canScrollForward:) { content }` (Kotlin `verticalScroll(rememberDetailsScrollState(id))`); private `DetailsScrollMetrics`, `DetailsScrollTracker`, `DetailsRestoreMarker` |
| Settings/SettingsScreen.swift | `SettingsScreen(onBack:)` (the entry point), `OptionRow(title:subtitle:selected:onClick:)` (radio-style row), `SpeakerOptionsMemo` (`SpeakerPicker.options` once per `Repository`, held in `@State`); private `SpeakingAsIntro`, `CreditsSection`, `LicenseItem`, `LicenseSheet` |
| Settings/FirstRunSheet.swift | `FirstRunSpeakerSheet()` (the entry point), `PickRow(title:subtitle:accessibilityText:onClick:)` (a picking row, also the licence rows) |
| Settings/DataSourceRow.swift | `DataSourceRow()` ("SCHEDULE DATA", "Updated … · Check now", the source line) |

- **Loading** (Kotlin `produceState`): the body starts from `graph.details.peekResult(id)` (no
  I/O: the sheet is instant when the details are known); `.task(id:)` keyed by the details set
  (held and compared by identity: a live data update brings a new `DetailsRepository`) and the
  id runs `await details.load(id)` when `SessionDetailsLogic.needsLoad` (unknown or
  `.unavailable`). "Loading…" waits `LOADING_DELAY_MS` (a second `.task(id: result == nil)`);
  `SessionDetailsLogic.about` picks loading / unavailable / description / nothing.
- **Layout**: `VStack { ZStack(alignment: .topTrailing) { DetailsScrollView { body column ≤ maxTextWidth }; CloseButton }; DirectionsBar }`;
  side padding `SessionDetailsLogic.horizontalPadding(wide: widthClass.isWide && !inSheet)`
  (24 / 18), 20 pt above in the pane, the 25 pt `GrabBar` room in the sheet. The sheet sets
  `.presentationBackground(surface)`, `.presentationCornerRadius(sheetRadius)` and
  `.presentationDragIndicator(.visible)` (the system bar replaces Kotlin's own grab bar and lets
  VoiceOver resize the sheet); the shell keeps the detents. The bar is pinned: in the sheet it
  sits at the sheet's bottom (Kotlin's sheet wraps short content instead).
- **Description**: one `Text(AttributedString)` per block: bold runs in the style's bold face
  (`piece.font = style.bold.font`), italic `font.italic()`, links `.link` + `foregroundColor` +
  `underlineStyle = Text.LineStyle.single` in `category("talk")`, plus `.tint` (Text draws
  links in the tint). Links open through the environment's `openURL`.
- **Pills tick**: `DetailsPills` reads `NowReader`; its content is never empty (a zero-size
  placeholder), so the ticker runs and "Live · N min left" appears when the session starts.
- **Scroll carry** (`DetailsScrollView`): while on screen the offset is written to
  `\.detailsScrollCarry` (`put`); a new details view for the same session takes it once on its
  first layout and scrolls an invisible marker (an overlay, `.id`, `scrollTo(_, anchor: .top)`)
  to the top; on disappear the carry is emptied unless `nav.openSessionId` is still this
  session. This covers the sheet ↔ pane swap on a width-class change and the compact sheet
  coming back after Directions (the shell drops the sheet while Directions is pushed). It also
  reports `canScrollForward` (content bottom below the viewport) for the bar's hairline.
- **Settings**: the system navigation bar (back = the system's) with "SETTINGS"
  (`dayHeading` 26/28, ink) as its principal item and navigation title; then
  `GeometryReader { ScrollView { LazyVStack(pinnedViews: [.sectionHeaders]) } }` with the side
  padding `PageLayout.sidePadding(forWidth:maxContent: maxTextWidth)`: the RSVP setting, the data
  row, "I’m speaking as", then one `Section` whose pinned header is the speaker `SearchField`
  (`.words`, focus dropped on a pick) over None, the speakers, the no-match note, the theme note
  and the iOS credits (`CreditsSection`: README credits, a `PickRow` per bundled font opening
  `LicenseSheet` with `Licenses/<file>` from the bundle, the app version).
- **First run**: title and text (hidden while the search field has the focus, Kotlin's
  "keyboard up"), a hairline, the list, then search and Skip at the bottom; VoiceOver order
  title/text, search/Skip, list (`accessibilitySortPriority`). Skip is `Text("Skip")` in
  `type.button` (not caps, as Kotlin) on `OutlineButtonStyle(fillsWidth: true, shape: .capsule)`.
  Background `bg`, the system drag indicator; picking or Skip calls `settings.finishFirstRun`.
- **Data row**: "Check now" is a plain button in `type.button` (not caps, as Kotlin), pink,
  muted and disabled while `status.checking`; the source line is announced to VoiceOver when it
  changes (`DirectionsAnnouncer.announce`, Kotlin's polite live region). Times use the wall clock.
