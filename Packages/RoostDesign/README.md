# RoostDesign

The mockup's visual system as a Swift package: color tokens that follow light/dark, the three typefaces, and a swatchbook preview. SwiftUI only. iOS 18+, macOS 15+.

Source of truth for the values is `roost-app-mockup.html` (the `:root` blocks and the `.app-shell` block). Change the HTML first, then this package, so the two never drift.

## Colors

`RoostColor.<name>` is a `Color` that resolves per appearance. `RoostColor.<name>Token` exposes the raw hex for both schemes.

The mockup carries two light palettes. `:root` styles the marketing page; `.app-shell` (the phone frame, "Colorful app styling") overrides ten tokens with a more saturated set. The app is the phone frame, so the defaults below use the `.app-shell` values where they exist. Dark values are the `:root` dark block; `.app-shell` has no dark override.

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
| `shadow` | `rgba(31,42,34,0.14)` | `rgba(0,0,0,0.45)` | card shadow |

`RoostColor.all` lists every token; `RoostColor.pairs` gives the seven strong/soft pairs.

### Page palette

The marketing page's `:root` light values for the ten overridden tokens live under `RoostColor.Page.<name>` (same dark values), in case that page is ever rebuilt in SwiftUI. App screens should not use them.

| Token | Page light |
|---|---|
| `accent` / `accentSoft` | `#2F6F5E` / `#DCEBE3` |
| `gold` / `goldSoft` | `#B9812E` / `#F3E4C9` |
| `info` / `infoSoft` | `#3E6B8A` / `#DCE7EE` |
| `tease` / `teaseSoft` | `#AE4568` / `#F4DEE6` |
| `alert` / `alertSoft` | `#C81E3A` / `#FBDCE1` |

## Type

| Role | Family | File | Fallback |
|---|---|---|---|
| display | Fraunces | `Fraunces-Variable.ttf` | system serif |
| body | Nunito Sans | `NunitoSans-Variable.ttf` | system sans |
| labels | IBM Plex Mono | `IBMPlexMono-{Regular,Medium,SemiBold}.ttf` | system mono |

```swift
Text("Roost").font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
Text("Body").font(RoostFont.body(size: RoostFont.Size.body))
Text("EYEBROW").font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold)).kerning(1.2)
```

`RoostFont.Size` holds the mockup's sizes (eyebrow 11.5, badge 10, caption 12, meta 13.5, body 15, section title 19, title 30, large title 38).

### Registering the fonts

The font files ship inside the package under `Resources/Fonts` with their SIL Open Font License texts. Register once at launch:

```swift
@main struct RoostApp: App {
    init() { try? RoostFonts.register() }
    ...
}
```

Until `register()` runs, every `RoostFont` call returns the system fallback, so nothing breaks in previews or tests that skip it. `register()` is idempotent and throws only if a bundled file is missing, which is a packaging error.

## Preview

`RoostSwatchbook()` renders every token in the current scheme, the strong/soft pairs, and the type ramp, with a line saying which custom fonts are live. Two `#Preview`s (light and dark) are in the file.

## Test

```bash
cd Packages/RoostDesign && swift test
```

Checks hex values against the mockup, resolves each dynamic color per scheme and compares components, verifies the fonts register and the OFL texts are bundled.

## License

Fraunces, Nunito Sans, and IBM Plex Mono are distributed under the SIL Open Font License 1.1. The license text for each ships next to the files.
