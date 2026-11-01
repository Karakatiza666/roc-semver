# roc-semver

[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) versions and version ranges for Roc. A port of [smores56/roc-semver](https://github.com/smores56/roc-semver) to the new Roc compiler.

| Module | Functions |
| --- | --- |
| `Semver` | `new`, `parse`, `parse_lazy`, `to_str`, `order_relative_to` (`[Before, Same, After]`, semver section 11), `to_key`, `from_key` (the 64-bit order key, see below), `major`, `minor`, `patch`, `pre_release`, `build`. `==` includes the build metadata. |
| `VersionReq` | `star`, `parse`, `parse_lazy`, `to_str`, `key_bounds`, `matches` |

## Range forms

The caret rule is the npm and Cargo rule: an update must not change the left-most part that is not zero.

| Form | Matches |
| --- | --- |
| `^1.2.3` | `>=1.2.3, <2.0.0` |
| `^0.2.3` | `>=0.2.3, <0.3.0` |
| `^0.0.3` | `>=0.0.3, <0.0.4` |
| `^0`, `0` | `>=0.0.0, <1.0.0` |
| `1.2`, `1.2.x` | `^1.2` |
| `2`, `2.x` | `^2` |
| `1.2.3`, `=1.2.3` | `1.2.3` only |
| `=1.2` | `>=1.2.0, <1.3.0` |
| `*`, `x`, `X`, `1.x`, `2.x.x`, `^1.x`, `=1.*` | A wildcard part matches any value |
| `>`, `>=`, `<`, `<=`, `~` | The usual compare. `~1.2.3` is `>=1.2.3, <1.3.0`. |
| `>=1.2, <2` | A comma list: each comparator must match (up to 32) |

| Rule | Behavior |
| --- | --- |
| Pre-release versions | A range never matches a pre-release version. A pre-release in a comparator only moves its bound. |
| Build metadata | Not allowed in a range: `BuildMetadataNotAllowed` |
| Numbers | A number above the U64 maximum is `InvalidNumber`. A leading zero is an error. |

## Order key

From 0.2.0. `Semver.to_key` gives a `U64` key and a flag `exact`. A database can sort and filter versions by the key.

| Bits | Field |
| --- | --- |
| 63 to 48 | major |
| 47 to 32 | minor |
| 31 to 16 | patch |
| 15 to 0 | pre-release code |

| Rule | Behavior |
| --- | --- |
| Saturation | A part of 0xFFFF or more gives 0xFFFF for itself and for each field after it. |
| Pre-release code | No pre-release: 0xFFFF. Numeric first identifier `n`: `0x0001 + min(n, 0x0FFE)`. Other first identifier: `0x1000 + 65 * r(c1) + r(c2)` from its first 2 characters. `r` is 0 for no character, 1 for `-`, 2 to 11 for `0` to `9`, 12 to 37 for `A` to `Z`, 38 to 63 for `a` to `z`. |
| Monotone | When `a` is before `b` by `order_relative_to`, `a.to_key().key <= b.to_key().key`. Two versions with one key are ordered with `order_relative_to`. |
| `exact` | True when each part is below 0xFFFF and the version has no pre-release and no build metadata. |
| `Semver.from_key` | `Ok(version)` when the pre-release code is 0xFFFF and the 3 parts are below 0xFFFF. Else `Err(NotExact)`. |
| `VersionReq.key_bounds` | `{ lo, hi }`. Each version that matches has its key from `lo` to `hi`. A key in the bounds does not always match: check each row with `matches`. A requirement that matches nothing can give `lo > hi`. |

Example: `1.2.3` has the key `0x100020003ffff`, and `1.2.3-beta1` has `0x1000200031a11`.

## Usage

Add the release to the header of your app, package or platform:

```roc
semver: "https://github.com/Karakatiza666/roc-semver/releases/download/0.1.0/KFKmXaroJeaPkQmAaqm83fTP9yhnEkTQwE97a5BtFSX.tar.zst",
```

Then:

```roc
import semver.Semver
import semver.VersionReq

expect {
	version = Semver.parse("1.4.0")?
	req = VersionReq.parse("^1.2")?
	req.matches(version)
}

expect Semver.new(1, 0, 0).order_relative_to(Semver.new(1, 2, 0)) == Before
```

## Tests

| Layer | Files | Tool |
| --- | --- | --- |
| L0 | `tests/*.roc` (cases ported from smores56/roc-semver, and semver.org sections) | `roc test` |
| L1 | `fuzz/*.roc` (properties: round trip, total preorder, caret ranges against an oracle, the order key, the key bounds) | [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.4.3 |

`scripts/test.sh [ROC [FUZZ_ROC]]` runs `roc check`, `roc fmt --check`, the L0 tests and the L1 targets. Use the nightly in `.roc-version`. CI (`.github/workflows/ci.yml`) runs the same checks on that nightly.

## Release

`.github/workflows/release.yml` makes a release with [roc-lang/release-package](https://github.com/roc-lang/release-package): `gh workflow run release.yml --ref main -f release_version=X.Y.Z`. The tag is `X.Y.Z` with no prefix, and the one package asset is `<hash>.tar.zst` from `roc bundle`.

## License

UPL-1.0, see `LICENSE`. The code ported from smores56/roc-semver keeps its copyright line in `LICENSE`.
