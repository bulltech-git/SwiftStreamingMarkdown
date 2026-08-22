# This is MakeNess AI's fork

Upstream: [microsoft/SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown)

The MakeNess AI app builds against the **`makeness`** branch, not `main`.
`main` is kept as a clean mirror of upstream so the two can always be compared.

## Why the fork exists

Upstream hard-codes `NSTextAlignment.left` in the text views that render every
paragraph, heading, list item and the text-selection sheet. That makes Arabic,
Hebrew and every other right-to-left language render flush-left with a ragged
right edge, and no public API on `MarkdownRenderConfig` can override it —
SwiftUI's `\.layoutDirection` never reaches those UIKit/AppKit views.

Our patch switches them to `.natural`, so TextKit resolves alignment per
paragraph from the text's own script. Block quotes render through a plain
SwiftUI `Text`, which has no paragraph style for `.natural` to act on, so they
read `String.startsRightToLeft` instead.

Alignment follows the **content**, never the device locale — an Arabic answer
reads right-to-left on an English phone, and vice versa.

Covered by `Tests/MarkdownTextTests/RightToLeftAlignmentTests.swift`.

## How the app consumes it

The three Xcode projects (`MakeNess_iOS`, `MakeNess_mac`, `MakeNess_visionOS`)
reference this repo by **exact revision**, so a build is always reproducible and
an upstream sync can never change the app without a deliberate bump.

To move the app to a newer commit, update `revision =` in all three
`project.pbxproj` files.

## Staying current with upstream

`.github/workflows/sync-upstream.yml` checks upstream every Monday (and on
demand from the Actions tab). When upstream is ahead it merges into a
`upstream-sync` branch and opens a PR against `makeness` — clean merges and
conflicts both, so a human always sees what changed before it reaches the
branch the app builds against.

> **Enable it once:** GitHub disables Actions on new forks. Open the fork's
> **Actions** tab and click *I understand my workflows, go ahead and enable them*,
> otherwise the weekly check never runs.

Manually, the same thing is:

```bash
git fetch upstream
git checkout makeness
git merge upstream/main
swift test --filter RightToLeftAlignmentTests   # our patch must still hold
```

## Working on the patch

```bash
swift test --filter RightToLeftAlignmentTests   # our tests
swift test                                       # whole suite
```

The full suite reports ~56 pre-existing failures on Xcode 27 beta. They are
snapshot-image mismatches caused by newer OS text rendering, present on
unmodified upstream too, and unrelated to this fork's changes.
