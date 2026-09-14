# RoostDesign

The app's design system as a Swift package: colour tokens and the semantic roles on top of
them, a Dynamic Type ramp in the three Roost typefaces, spacing and radius scales, elevation,
motion, Liquid Glass wrappers, haptics, and a swatchbook that shows the lot. SwiftUI only.
iOS 26+, macOS 26+.

Source of truth for the colour and type values is `roost-app-mockup.html` (the `:root` blocks
and the `.app-shell` block). Change the HTML first, then this package, so the two never drift.
Everything else — spacing, radius, elevation, motion, haptics — is native iOS practice and is
documented here.

## The rules

1. **No hex in the app.** Screens use `RoostColor.Role`, never a raw `…Token`, never a literal.
2. **No point sizes in the app.** Screens use `.roostType(_:)` or `RoostType.<style>`. A hardcoded
   size does not scale with the reader's text size, which is the whole reason the ramp exists.
3. **No loose numbers for space.** Screens use `RoostSpacing` and `RoostRadius`. If a gap you need
   isn't on the scale, the answer is almost always a value that is.
4. **One spring vocabulary.** `RoostMotion.Named` has four entries and does not need a fifth.
   Always pass animations through `reduceMotionAware(_:reduceMotion:)` or use `.roostAnimation(_:value:)`.
5. **Glass is the floating layer only**, and exactly one tinted glass surface per screen.
6. **Haptics are rare.** Six named moments, all user-initiated.

If a screen needs something this package doesn't have, add it here first.

## Colours

`RoostColor.<name>` is a `Color` that resolves per appearance. `RoostColor.<name>Token` exposes
the raw hex for both schemes.

The mockup carries two light palettes. `:root` styles the marketing page; `.app-shell` (the phone
frame, "Colorful app styling") overrides ten tokens with a more saturated set. The app is the phone
frame, so the defaults below use the `.app-shell` values where they exist. Dark values are the
`:root` dark block; `.app-shell` has no dark override.

| Token | App light | Dark | Used for |
|---|---|---|---|
| `bg` | `#F3F6F2` | `#121A15` | page background |
| `surface` | `#FFFFFF` | `#1B241D` | cards |
| `surface2` | `#FBFDFA` | `#212C22` | inset panels |
| `ink` | `#1F2A22` | `#EAF2EC` | text |
| `inkSoft` | `#5C6C60` | `#9FB3A4` | secondary text |
| `line` | `#DCE6DA` | `#2B3830` | dividers, strokes |
| `accent` | `#2F8F72` | `#6FC2A6` | primary green |
| `accentSoft` | `#CFEEE1` | `#1E362E` | accent background |
| `gold` | `#E08F2E` | `#D9A754` | bonus / points |
| `goldSoft` | `#FBE3C2` | `#3A2D15` | |
| `info` | `#4C7FE0` | `#7FB3D9` | neutral notices |
| `infoSoft` | `#DEE6FC` | `#1E2E3A` | |
| `tease` | `#D6487A` | `#E389A8` | 3-day nudge |
| `teaseSoft` | `#FBDCE8` | `#3A2129` | |
| `alert` | `#E2233F` | `#FF6478` | 5-day red alert |
| `alertSoft` | `#FCD9DF` | `#3D1620` | |
| `meal` | `#C2571F` | `#E8935A` | meals tab |
| `mealSoft` | `#F5DCC8` | `#3A2415` | |
| `assign` | `#6B4FA0` | `#B79EE0` | auto-assigned / pinned |
| `assignSoft` | `#E6DFF5` | `#332750` | |
| `anne` | `#2F8F72` | `#6FC2A6` | Anne (own token; same hex as accent) |
| `anneSoft` | `#CFEEE1` | `#1E362E` | |
| `wes` | `#4C7FE0` | `#7FB3D9` | Wes (own token; same hex as info) |
| `wesSoft` | `#DEE6FC` | `#1E2E3A` | |
| `nudge` | `#4C7FE0` | `#7FB3D9` | 1–2 day nudge (own token; same hex as info) |
| `nudgeSoft` | `#DEE6FC` | `#1E2E3A` | |
| `shadow` | `rgba(31,42,34,0.14)` | `rgba(0,0,0,0.45)` | card shadow |

`RoostColor.all` lists every token; `RoostColor.pairs` gives the ten strong/soft pairs.

### Roles

A token is a value; a role is a meaning. Screens name meanings, so nothing on a screen has to
decide what colour "done" is, and re-tinting the app later is one edit in `RoostColorRole.swift`.

`RoostColor.Role.<name>.color` follows the appearance; `.color(_ scheme:)` pins a scheme (the
swatchbook shows both); `.token` is the raw token behind it; `.soft` is the soft partner where
there is one.

| Role | Token | Used for |
|---|---|---|
| `background` | `bg` | the page |
| `surface` | `surface` | cards, sheets |
| `surfaceElevated` | `surface2` | a panel inside a card, a row's pressed fill |
| `textPrimary` | `ink` | titles, body |
| `textSecondary` | `inkSoft` | subtitles, meta, captions |
| `separator` | `line` | hairlines, the resting check control |
| `accent` / `accentSoft` | `accent` / `accentSoft` | primary action, selection |
| `onAccent` | `surface` | labels and glyphs sitting on an accent fill (near-white in light, near-black in dark) |
| `success` / `successSoft` | `accent` / `accentSoft` | done, on time, claimed |
| `warning` / `warningSoft` | `tease` / `teaseSoft` | the 3-day nudge |
| `danger` / `dangerSoft` | `alert` / `alertSoft` | 5 days late |
| `bonus` / `bonusSoft` | `gold` / `goldSoft` | bonus chores, points |
| `assigned` / `assignedSoft` | `assign` / `assignSoft` | auto-assigned by the rotation |
| `notice` / `noticeSoft` | `info` / `infoSoft` | neutral information, sync state |
| `nudge` / `nudgeSoft` | `nudge` / `nudgeSoft` | 1–2 days late (own tokens) |
| `anne` / `anneSoft` | `anne` / `anneSoft` | Anne (mockup `.avatar-a`, `.tally-fill-a`; own tokens) |
| `wes` / `wesSoft` | `wes` / `wesSoft` | Wes (mockup `.avatar-p`, `.tally-fill-p`; own tokens) |
| `catCare` / `catCareSoft` | `accent` / `accentSoft` | cat care (mockup `.icon-cat`) |
| `home` / `homeSoft` | `gold` / `goldSoft` | household chores (mockup `.icon-chore`) |
| `meals` / `mealsSoft` | `meal` / `mealSoft` | meals (mockup `.icon-meal`) |
| `shadow` | `shadow` | shadow tint; prefer `.roostElevation(_:)` |

Cat care and "done" still share the accent green — that is the mockup's palette. Anne, Wes, and
the 1–2 day nudge each have their own tokens (same hex as the roles they used to borrow), so
tinting a person or a nudge does not also recolour notices or the primary action.

`RoostPerson` (`.anne`, `.wes`) and `RoostCategory` (`.catCare`, `.home`, `.meals`, `.bonus`) wrap
the person and category roles with a `color`, a `softColor`, and an SF Symbol name, so view code
takes a person or a category rather than a colour.

### Page palette

The marketing page's `:root` light values for the ten overridden tokens live under
`RoostColor.Page.<name>` (same dark values), in case that page is ever rebuilt in SwiftUI. App
screens should not use them.

| Token | Page light |
|---|---|
| `accent` / `accentSoft` | `#2F6F5E` / `#DCEBE3` |
| `gold` / `goldSoft` | `#B9812E` / `#F3E4C9` |
| `info` / `infoSoft` | `#3E6B8A` / `#DCE7EE` |
| `tease` / `teaseSoft` | `#AE4568` / `#F4DEE6` |
| `alert` / `alertSoft` | `#C81E3A` / `#FBDCE1` |

## Type

Three faces, twelve rungs. Every rung is built with `Font.custom(_:size:relativeTo:)`, so the
custom faces scale with the reader's text size. When a face isn't registered the rung falls back
to `Font.system(textStyle, design:weight:)`, which lands on the same size.

| Face | Family | File | Fallback |
|---|---|---|---|
| display | Fraunces | `Fraunces-Variable.ttf` | system serif |
| body | Nunito Sans | `NunitoSans-Variable.ttf` | system sans |
| mono | IBM Plex Mono | `IBMPlexMono-{Regular,Medium,SemiBold}.ttf` | system mono |

| Rung | Face | Size | Scales with | Weight | Used for |
|---|---|---|---|---|---|
| `displayLarge` | Fraunces | 34 | `.largeTitle` | semibold | screen title ("Today") |
| `display` | Fraunces | 28 | `.title` | semibold | hero line, empty states, a streak number |
| `title` | Fraunces | 22 | `.title2` | semibold | card and section titles |
| `rowTitle` | Fraunces | 17 | `.headline` | semibold | a chore row's title |
| `headline` | Nunito Sans | 17 | `.headline` | semibold | emphasised sans line, form labels |
| `body` | Nunito Sans | 17 | `.body` | regular | body copy |
| `callout` | Nunito Sans | 16 | `.callout` | regular | notes under a control |
| `subheadline` | Nunito Sans | 15 | `.subheadline` | regular | row subtitle, meta line |
| `footnote` | Nunito Sans | 13 | `.footnote` | regular | hints |
| `caption` | Nunito Sans | 12 | `.caption` | regular | timestamps, tag text |
| `monoTally` | IBM Plex Mono | 13 | `.footnote` | medium | tallies and counts (monospaced digits) |
| `monoLabel` | IBM Plex Mono | 12 | `.caption` | semibold | uppercase eyebrow label, tracking 1 |

Row titles are serif on purpose: `.app-shell .item-title` in the mockup is Fraunces 600, and it is
the detail that stops the app reading as a stock list. Body copy is never set in a custom display
face — that rule is in the tests.

```swift
Text("Today").roostType(.displayLarge)
Text(chore.title).roostType(.rowTitle)
Text("CAT CARE").roostType(.monoLabel)
Text("\(done)/\(total)").roostType(.monoTally)
```

`.roostType(_:)` applies the font, its tracking, and its line spacing together. `RoostType.body`
and friends give the bare `Font` when a modifier isn't possible. `Text.roostFont(_:)` is the
`Text`-returning version, for when a `Text`-only modifier has to follow.

`RoostType.scaledSize(_:at:)` and `RoostType.referenceBodySize(for:)` give the approximate rendered
size at a Dynamic Type setting (the system `.body` ramp: 14 pt at `.xSmall` to 53 pt at
`.accessibility5`). They're reference numbers for layout maths and tests — `Font.custom` does the
real scaling.

### Registering the fonts

The font files ship inside the package under `Resources/Fonts` with their SIL Open Font License
texts. Register once at launch:

```swift
@main struct RoostApp: App {
    init() { try? RoostFonts.register() }
    ...
}
```

Until `register()` runs, every rung returns the system fallback, so nothing breaks in previews or
tests that skip it. `register()` is idempotent and throws only if a bundled file is missing, which
is a packaging error.

`RoostFont.display(size:weight:)` / `.body` / `.mono` are still here for a literal point size —
a fixed-size numeral in custom-drawn content, for instance. Screens use `RoostType`.

## Spacing

A 4-pt scale, plus the four values a screen actually reaches for. `xxs` is the one value off the
grid: 2 pt, the hairline gap inside a single group.

| Name | Value | Used for |
|---|---|---|
| `xxs` | 2 | inside one group (a title over its meta line) |
| `xs` | 4 | icon to text, title to subtitle |
| `sm` | 8 | standard small gap, chips in a line |
| `md` | 12 | row padding, compact card padding |
| `lg` | 16 | screen margin, card padding |
| `xl` | 24 | between sections, card to card, breathing room around a hero number |
| `xxl` | 32 | large break between unrelated blocks |
| `xxxl` | 48 | hero spacing, empty and celebration screens |
| `screenMargin` | 16 | every screen's side margin |
| `cardPadding` | 16 | inside a card |
| `rowPadding` | 12 | vertical padding of a tappable row |
| `sectionGap` | 24 | between two labelled sections |
| `minTapTarget` | 44 | use with `.frame(minHeight:)`, never a fixed height |

## Radius

Continuous corners, spaced so that a shape inset inside another lands on a real step of the scale.

| Name | Value | Used for |
|---|---|---|
| `sm` | 6 | tags, badges, the check control |
| `md` | 10 | small controls, chips |
| `lg` | 14 | list rows |
| `xl` | 18 | inset panels inside a card |
| `card` | 22 | cards and sheets |
| `pill` | 999 | capsules — prefer `RoostRadius.pillShape` |

`RoostRadius.concentricInner(outer:inset:minimum:)` is iOS 26's concentric rule — inner radius =
outer − inset, clamped at 4 so a corner never goes visually square. A row inset by `sm` inside a
`card` lands exactly on `lg`: 22 − 8 = 14.

`RoostRadius.shape(_:)`, `.cardShape`, `.rowShape`, and `.pillShape` are type-erased continuous
shapes, for `.background(_:in:)` and `.roostGlass(_:in:)`.

## Elevation

Three steps, applied with `.roostElevation(_:cornerRadius:)`. Light-mode shadows are tinted with
the mockup's ink-based `--shadow`, never pure black. Dark mode keeps 60% of the geometry and adds a
1-pt white hairline instead, which is how the system's own dark surfaces read.

| Step | Light | Dark | Used for |
|---|---|---|---|
| `card` | radius 8, y 3, 10% | radius 4.8, y 1.8, 28% + hairline 6% | resting cards and rows |
| `lifted` | radius 16, y 8, 14% | radius 9.6, y 4.8, 36% + hairline 8% | long-press lift, drag, popover |
| `floating` | radius 24, y 12, 18% | radius 14.4, y 7.2, 45% + hairline 10% | glass bars, floating buttons |

Pass the shape's corner radius so dark mode can draw its hairline in the right shape.

## Components

The rung above tokens: three pieces, each themed from the scales above and each on the swatchbook.

- **`RoostButtonStyle`** (`.roostPress` / `.roostPressQuiet`) — the press vocabulary: scale 0.97 and
  opacity 0.85 on touch-down with the `quick` spring, back on release, plus `RoostHaptic.press`
  (light impact, touch-down only). The quiet variant skips the haptic for a row whose tap already
  carries one. Put any background in the button's *label*, so the press scales it too.
- **`.roostCard()`** — the surface fill, the `card` radius and the `card` elevation as one modifier.
  Padding stays the caller's.
- **`RoostAvatar(person:label:)`** — the initial on a soft circle in a `RoostPerson`'s colours,
  capped at `glyphCeiling` so the largest text size cannot turn a marker into a button. The label
  says what the avatar means ("Added by Anne"); it defaults to the person's name.

## Motion

Four springs, and the Reduce Motion answer for each.

| Name | Duration | Bounce | Reduce Motion | Used for |
|---|---|---|---|---|
| `quick` | 0.18 s | 0 | instant | press states, toggles, chips |
| `standard` | 0.32 s | 0.16 | 0.18 s cross-fade | row insert/remove, expand, tab indicator, numbers |
| `gentle` | 0.45 s | 0 | 0.22 s cross-fade | sheets, whole-list changes |
| `bouncyCelebration` | 0.60 s | 0.34 | 0.20 s cross-fade | streak milestones only |

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

withAnimation(RoostMotion.reduceMotionAware(.standard, reduceMotion: reduceMotion)) {
    done.insert(chore.id)
}
```

`.roostAnimation(_:value:)` does the same thing declaratively and is always scoped to a value —
there is deliberately no unscoped version, because a bare `.animation(_)` animates state changes
you didn't mean. `RoostMotion.kind(_:reduceMotion:)` says what you'll get (`.spring`,
`.crossFade`, `.instant`) without building the animation. `RoostMotion.staggerDelay(index:)` gives
a capped 40 ms-per-row delay for a list's first appearance, and zero under Reduce Motion.

`.roostTransition(_:)` covers the three cases rows need, and flattens to a fade under Reduce Motion:

| Transition | Insert | Remove |
|---|---|---|
| `row` | from the top, fading in | scale to 96%, fading out |
| `checkOff` | fade | collapse from the leading edge, so rows below rise into the gap |
| `badge` | scale from 70% | scale to 70% |

Guidance that comes with the vocabulary: animate what the user did and let data changes simply
appear; give elements driven by the same number one animation so a tally bar, its digits, and the
crown move as one thing; entrances slower than exits (`.standard` in, `.quick` out); stagger a
list's first appearance only, never on every scroll.

## Glass

`.roostGlass(_:in:)` puts a view on a Liquid Glass surface, with a `.thinMaterial` fallback and an
opaque fallback when the reader has Reduce Transparency on. `RoostGlassContainer` groups glass
surfaces that sit near each other so they share one blur and can merge as they move.

| Style | Tint | Interactive | Used for |
|---|---|---|---|
| `clear` | none | yes | floating bars, secondary controls |
| `primary` | accent | yes | the one primary action on a screen |
| `quiet` | none | no | floating chrome that isn't tappable |

Only `primary` carries a tint, so a screen cannot tint everything by accident. Glass is for the
floating control layer — cards and page backgrounds stay opaque, because glass exists to show the
content behind it.

## Haptics

`.roostHaptic(_:trigger:)` fires on a change; the closure form picks a haptic from the new value.

| Moment | `SensoryFeedback` | Used for |
|---|---|---|
| `checkOff` | `.success` | a chore checked off |
| `undo` | `.impact(flexibility: .soft)` | a chore un-checked |
| `error` | `.error` | the action failed |
| `milestone` | `.levelChange` | a streak milestone, a week decided |
| `selection` | `.selection` | tab, day, or person changed |
| `press` | `.impact(weight: .light)` | touch-down on a button or row; `RoostButtonStyle` fires it, so no screen does |

```swift
row.roostHaptic(trigger: isDone) { _, now in now ? .checkOff : .undo }
```

Never on cold launch (the engine is asleep and lags), never per scrolled row, never to confirm
something the user already watched happen.

## How to build a screen with this

Name meanings, not values. A section of a chore list, whole:

```swift
import RoostDesign
import SwiftUI

struct ChoreSection: View {
    let category: RoostCategory
    let chores: [Chore]
    let toggle: (Chore) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            HStack {
                Label(category.rawValue.uppercased(), systemImage: category.symbol)
                    .roostType(.monoLabel)
                    .foregroundStyle(category.color)
                Spacer()
                Text("\(chores.count(where: \.isDone))/\(chores.count)")
                    .roostType(.monoTally)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }

            ForEach(chores) { chore in
                ChoreRow(chore: chore) { toggle(chore) }
                    .roostTransition(.row)
            }
        }
        .padding(RoostSpacing.cardPadding)
        .background(RoostColor.Role.surface.color, in: RoostRadius.cardShape)
        .roostElevation(.card, cornerRadius: RoostRadius.card)
        .roostAnimation(.standard, value: chores.map(\.isDone))
    }
}

struct ChoreRow: View {
    let chore: Chore
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            Image(systemName: chore.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(chore.isDone ? RoostColor.Role.success.color : RoostColor.Role.separator.color)
                .symbolEffect(.bounce, value: chore.isDone)

            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(chore.title)
                    .roostType(.rowTitle)
                    .strikethrough(chore.isDone)
                Text(chore.owner.shortName)
                    .roostType(.subheadline)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }

            Spacer(minLength: RoostSpacing.sm)
        }
        .padding(.horizontal, RoostSpacing.sm)
        .padding(.vertical, RoostSpacing.rowPadding)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .background(
            chore.isDone ? RoostColor.Role.successSoft.color : RoostColor.Role.surfaceElevated.color,
            in: RoostRadius.rowShape
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .roostHaptic(trigger: chore.isDone) { _, now in now ? .checkOff : .undo }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
```

What that buys, in order: the row is legible at every text size; the tap target clears 44 pt even
at the smallest one; the colours follow light and dark and Increase Contrast; the check-off feels
right and sounds right to VoiceOver; and Reduce Motion is handled without a branch in the view.

## Swatchbook

`RoostSwatchbook()` renders the whole system on one page: every role in both schemes, the raw
tokens, the strong/soft pairs, the type ramp with its usage notes, the ramp again at three Dynamic
Type sizes, the spacing and radius scales, the elevation steps, the four springs on a row that
actually checks off, and a glass sample. Four `#Preview`s are in the file: light, dark,
accessibility 3, and one with the fonts deliberately unregistered so the fallbacks can be checked.

## Test

```bash
cd Packages/RoostDesign && swift test
```

Checks hex values against the mockup, resolves each dynamic colour per scheme, verifies every role
lands on a real token, that the type ramp grows monotonically across all twelve Dynamic Type
settings, that the spacing and radius numbers are the ones documented above, that Reduce Motion
produces a non-spring animation for every spring, and that the fonts register with their OFL texts
bundled.

## Platform floor

iOS 26 / macOS 26, spelled as version strings in `Package.swift` because `.iOS(.v26)` needs a
swift-tools-version of 6.2 and the repo standardises on 6.0.

One consequence to know before adding code: with a macOS floor of 26, any reference to a macOS
26-only SwiftUI symbol links strongly, so `swift test` and Mac previews cannot load on an older
Mac — an `#available` check does not weaken that link. iOS 26-only API therefore lives behind
`#if os(iOS)` with a material fallback for the macOS build. `RoostGlass.swift` is the example.

## License

Fraunces, Nunito Sans, and IBM Plex Mono are distributed under the SIL Open Font License 1.1. The
license text for each ships next to the files.
