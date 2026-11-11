# Personal 1.9.3: exact raster baseline evidence

Source before baseline changes: `e4a0113162e984c51f4300a78db4897e66a8f154`.
The local process reports macOS 27.0.1 (26A434), a 2× screen, Xcode 27.2,
Swift 6.4.2 and SDK 27.2. This is local evidence, not a release-runner pass.

The existing exact artwork and static-scene tests failed before this release
preparation; the microphone fix does not change any icon renderer or artwork.
All six `Issue30WiFiAlignmentTests` passed with their original assertions.

## Independent offscreen checks

Export current artwork without changing expectations:

```sh
STATUS_TRIO_APP_ICON_ARTWORK_DIR="$PWD/.build/verification/personal-release-1.9.3/current-artwork" \
STATUS_TRIO_STATIC_ICON_DIAGNOSTICS=1 \
bash scripts/test.sh 'AppIconPreviewTests|ChargingEffectRenderingTests|Issue30WiFiAlignmentTests'
```

A temporary, separately reviewed offscreen probe exported full, center-only
and non-center 40×40 scenes. It independently created AppKit `wifi.slash`
at semibold 38 pt, white hierarchical color, measured its ink at 6×, and
drew it at the fixed anchor `(59.5, 61.48715261785473)`. It called no product
symbol measurement/drawing helper and created no window or status item.

- Image size was 50×47, horizontal measured bounds 24…272, offset −0.25.
- The independent glyph and product center were byte-identical, SHA-256
  `fdeaad1681f1e38e14203050340293364874f2f562d8add81bf295d7e49add75`.
- The full scene was
  `6f5b14cf75299fc873d0b2b75949417d1e68ae8ccd641d84d76753299e8ee1ec`.
- Non-center pixels were
  `03159ca152599ae8e4664fbd434d73a1327f4f8584f4e21f45db32d433d00ef7`.
- Constructing `NSApplication.shared` without launching/presenting anything
  changed none of those fingerprints; that initialization hypothesis was
  explicitly rejected.
- Independently reconstructing the pre-#260 square transform produced exactly
  the same current light/dark artwork, ruling out transform drift.

Comparing normalized committed and current artwork isolated every changed
pixel to the Wi-Fi glyph. Light differed in 4,086 pixels, dark in 3,893;
both inclusive bounding boxes were `(396,418)`…`(660,619)`. Background,
ring, charging bolt and footer pixels outside that box were byte-identical.

The newly proven exact rendered hashes, paired with the unchanged committed
asset hashes, are:

| Appearance | Committed pixels | Rendered pixels |
| --- | --- | --- |
| Light | `9baf1717eded52a1253362e1d7d10f288109c3c6d7f11a145b67dabff2cf5981` | `6cf5f6801889c2d04cc9252077613dd38217cdcc9b97224f04234eae69a4b63c` |
| Dark | `a29cba2760415d0de093df7dbb9bccc71d22028bea89eb8af64e2d67fdfecb63` | `747a3fcb24415dd0e0b6844670029c3eea00bbd621a9650de05d94a344423f84` |

## Scope of the baseline update

Keep every prior exact baseline and the original alignment assertions. Add
only the independently reproduced full-scene hash in the macOS-27/50×47
branch and the two artwork pairs. Correct the diagnostic-only symbol y
anchor from the obsolete 64 to the current ring center. Production drawing,
cache policy and committed artwork remain unchanged.

An earlier full-suite `db42f0d…` variant differs only in central symbol ink,
but its exact trigger has not been independently reproduced. It is not
approved by this evidence. A fresh full-profile failure remains a finding.

Local detailed notes, raw pixels, logs and the archived temporary probe are
under `.build/verification/personal-release-1.9.3/`; the temporary test was
removed before delivery. Visible UI, real Dock/Menu Bar interaction and
macOS 13 runtime acceptance are not covered by these offscreen checks.
