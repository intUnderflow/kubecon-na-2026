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
  with `.readsWindowWidth()` (full window width, safe-area insets included, like Android). It
  lives in Theme/ because Core has no UILogic/Adaptive yet; if Core adds `WidthClass`, delete
  the enum from Theme/WidthClass.swift and keep the environment part.

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
