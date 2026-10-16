app [main!] { pkg: "../package/main.roc" }

import pkg.Semver
import pkg.VersionReq

main! = |_args| Ok({})

# Sources:
#   smores VersionReq.roc = smores56/roc-semver package/VersionReq.roc (the port source, R-GA6)
#   smores Parse.roc      = smores56/roc-semver package/Parse.roc
#   R-xxx                 = a rule id of the Talon design (DESIGN.md, DESIGN-CLI.md, DESIGN-RESOLUTION.md)
#   Design 4.3            = the talon.toml example of DESIGN.md 4.3
#   Q<n> settled          = an answer of the human review (slice roc-semver.md, section Settled)
#   npm, Cargo            = node-semver README "Advanced Range Syntax", Cargo book "Specifying Dependencies"

ver : Str -> Semver
ver = |text|
	match Semver.parse(text) {
		Ok(v) => v
		Err(_) => crash "test setup: version ${text} does not parse"
	}

req : Str -> VersionReq
req = |text|
	match VersionReq.parse(text) {
		Ok(r) => r
		Err(_) => crash "test setup: requirement ${text} does not parse"
	}

## The parse result with no requirement value: VersionReq has no `==` (decision D7).
parse_err : Str -> Try({}, _)
parse_err = |text| VersionReq.parse(text).map_ok(|_| {})

## Each version is in the requirement.
all_in : Str, List(Str) -> Bool
all_in = |r, versions| versions.all(|v| req(r).matches(ver(v)))

## No version is in the requirement.
none_in : Str, List(Str) -> Bool
none_in = |r, versions| versions.all(|v| !req(r).matches(ver(v)))

# ---- Ported from smores ----

# T-VR1 (smores VersionReq.roc): star prints as `*`
expect VersionReq.star.to_str() == "*"

# T-VR2 (smores VersionReq.roc): star matches a version
expect VersionReq.star.matches(ver("1.2.3"))

# T-VR3 (smores VersionReq.roc): a full version matches that version
expect req("1.2.3").matches(ver("1.2.3"))

# T-VR4 (smores VersionReq.roc): a wildcard prints with `*`
expect req("1.3.*").to_str() == "1.3.*"

# T-VR5 (smores VersionReq.roc): a caret with 2 parts prints as written
expect req("^2.5").to_str() == "^2.5"

# T-VR6 (smores Parse.roc): empty text
expect parse_err("") == Err(InvalidComparator({ index: 0, error: InvalidMajorVersion(Empty) }))

# T-VR7 (smores Parse.roc): `*` parses and matches each version
expect all_in("*", ["0.0.0", "1.2.3", "99.0.0"])

# T-VR8 (smores Parse.roc): 1, 2 and 3 parts, and a pre-release, parse
expect ["123", "123.456", "123.456.789", "123.456.789-alpha"].all(|s| VersionReq.parse(s).is_ok())

# T-VR9 (Q8 settled): build metadata is not allowed in a requirement, valid or not.
# Changed from smores Parse.roc (InvalidBuildConstraint(EmptySegment) and InvalidBuildConstraint(InvalidIdentifier)).
expect parse_err("123.456.789-alpha+") == Err(InvalidComparator({ index: 0, error: BuildMetadataNotAllowed }))
expect parse_err("123.456.789-alpha+?") == Err(InvalidComparator({ index: 0, error: BuildMetadataNotAllowed }))
expect parse_err("=1.2.3+b") == Err(InvalidComparator({ index: 0, error: BuildMetadataNotAllowed }))
expect parse_err(">=1.0.0, <2.0.0+build.5") == Err(InvalidComparator({ index: 1, error: BuildMetadataNotAllowed }))

# T-VR10 (smores Parse.roc, Cargo): after a wildcard part, no number. (`2.x.x` is valid: T-VR33.)
expect parse_err("2.x.3") == Err(UnexpectedSuffix(".3"))

# T-VR11 (smores Parse.roc): parse_lazy gives the text after the requirement
expect
	match VersionReq.parse_lazy("4.x ?") {
		Ok((r, rest)) => rest == " ?" and r.matches(ver("4.1.0")) and !r.matches(ver("5.0.0"))
		Err(_) => Bool.False
	}

# T-VR12 (smores Parse.roc): parse takes the whole text
expect parse_err("4.x ?") == Err(UnexpectedSuffix(" ?"))

# ---- The range forms of the design (R-PK2) ----

# T-VR13 (R-I7): `^2.1` is >=2.1.0, <3.0.0
expect all_in("^2.1", ["2.1.0", "2.1.5", "2.9.9"])
expect none_in("^2.1", ["2.0.9", "3.0.0", "1.9.0"])

# T-VR14 (R-I7): `^0.25.1` is >=0.25.1, <0.26.0
expect all_in("^0.25.1", ["0.25.1", "0.25.9"])
expect none_in("^0.25.1", ["0.25.0", "0.26.0", "1.0.0"])

# T-VR15 (R-I4): the implied range `^0.25.0` is >=0.25.0, <0.26.0
expect all_in("^0.25.0", ["0.25.0", "0.25.3"])
expect none_in("^0.25.0", ["0.24.9", "0.26.0"])

# T-VR16 (R-I4): the implied range `^2.1.0` is >=2.1.0, <3.0.0
expect all_in("^2.1.0", ["2.1.0", "2.99.0"])
expect none_in("^2.1.0", ["2.0.9", "3.0.0"])

# T-VR17 (R-SL15, R-AD26): `2.x`, `^2` and `2` are the same: >=2.0.0, <3.0.0
expect ["2.x", "^2", "2"].all(|r| all_in(r, ["2.0.0", "2.5.1", "2.99.99"]))
expect ["2.x", "^2", "2"].all(|r| none_in(r, ["1.9.9", "3.0.0"]))

# T-VR18 (R-SL15): `2.1.x` is >=2.1.0, <2.2.0
expect all_in("2.1.x", ["2.1.0", "2.1.9"])
expect none_in("2.1.x", ["2.0.9", "2.2.0", "3.1.0"])

# T-VR19 (R-SL15): below 1.0, `0.25`, `0.25.x` and `^0.25` are the same: >=0.25.0, <0.26.0
expect ["0.25", "0.25.x", "^0.25"].all(|r| all_in(r, ["0.25.0", "0.25.7"]))
expect ["0.25", "0.25.x", "^0.25"].all(|r| none_in(r, ["0.24.9", "0.26.0", "1.25.0"]))

# T-VR20 (R-SL15): `0.x` spans all series below 1.0
expect all_in("0.x", ["0.0.0", "0.1.0", "0.99.1"])
expect none_in("0.x", ["1.0.0", "2.0.0"])

# T-VR21 (R-SL15): with fewer than 3 parts, a version is a caret range: `1.2` is `^1.2`, >=1.2.0, <2.0.0.
# Port change: smores Parse.roc reads `1.2` as `1.2.*` (an Exact relation on 2 parts).
expect ["1.2", "^1.2"].all(|r| all_in(r, ["1.2.0", "1.2.9", "1.9.0"]))
expect ["1.2", "^1.2"].all(|r| none_in(r, ["1.1.9", "2.0.0"]))

# T-VR22 (R-SL15): with 3 parts, a version is an exact version
expect all_in("1.2.3", ["1.2.3"])
expect none_in("1.2.3", ["1.2.4", "1.3.0", "1.2.2"])

# T-VR23 (Design 4.3 `parser = "=2.0.0"`, R-AD25): `=` with a full version is a hard pin
expect all_in("=2.0.0", ["2.0.0"])
expect none_in("=2.0.0", ["2.0.1", "1.9.9", "2.1.0"])

# T-VR24 (Design 4.3 `roc = "*"`, R-NS7): `*` matches each release version
expect all_in("*", ["0.0.0", "0.25.1", "1.2.3", "18446744073709551615.0.0"])

# T-VR25 (R-NS7): `^1` is >=1.0.0, <2.0.0
expect all_in("^1", ["1.0.0", "1.9.9"])
expect none_in("^1", ["0.9.9", "2.0.0"])

# T-VR26 (Design 4.3 `pf = "0.25.*"`, R-NS7 `0.1.*`, R-PK2 names `*` and `x`): `*` in a part is the same as `x`
expect ["0.25.*", "0.25.x"].all(|r| all_in(r, ["0.25.0", "0.25.4"]))
expect ["0.25.*", "0.25.x"].all(|r| none_in(r, ["0.24.0", "0.26.0"]))
expect all_in("0.1.*", ["0.1.0", "0.1.12"])
expect none_in("0.1.*", ["0.2.0", "0.0.9"])

# T-VR27 (R-UP5): each form that R-UP5 writes parses
expect ["^3.0", "^0.26", "0.26.*", "3", "=3.0.0"].all(|s| VersionReq.parse(s).is_ok())

# T-VR28 (R-TF4: a range that does not parse is an error): text that is in no form
expect ["abc", "^", "=", "1.2.3.4", "1..2"].all(|s| VersionReq.parse(s).is_err())

# ---- Caret edge forms (Q1, Q2 settled: npm and Cargo) ----

# T-VR29 (Q1 settled): the caret keeps the left-most non-zero part
expect all_in("^1.2.3", ["1.2.3", "1.9.0"])
expect none_in("^1.2.3", ["1.2.2", "2.0.0"])
expect all_in("^0.2.3", ["0.2.3", "0.2.9"])
expect none_in("^0.2.3", ["0.2.2", "0.3.0"])

# T-VR30 (Q1 settled): `^0.0.3` is >=0.0.3, <0.0.4
expect all_in("^0.0.3", ["0.0.3"])
expect none_in("^0.0.3", ["0.0.2", "0.0.4", "0.1.0"])

# T-VR31 (Q1 settled, npm, Cargo): `^0.0` and the bare `0.0` are >=0.0.0, <0.1.0
expect ["^0.0", "0.0"].all(|r| all_in(r, ["0.0.0", "0.0.9"]))
expect ["^0.0", "0.0"].all(|r| none_in(r, ["0.1.0", "1.0.0"]))

# T-VR32 (Q2 settled): `^0` and the bare `0` are >=0.0.0, <1.0.0
expect ["^0", "0"].all(|r| all_in(r, ["0.0.0", "0.0.5", "0.25.1"]))
expect ["^0", "0"].all(|r| none_in(r, ["1.0.0", "2.3.4"]))

# ---- Wildcards (Q3, Q5 settled) ----

# T-VR33 (Q5 settled, npm): `2.x.x` and `1.*.*` are the same as `2.x` and `1.*`
expect all_in("2.x.x", ["2.0.0", "2.9.9"])
expect none_in("2.x.x", ["1.9.9", "3.0.0"])
expect all_in("1.*.*", ["1.0.0", "1.5.0"])
expect none_in("1.*.*", ["2.0.0"])

# T-VR34 (Q5 settled, npm, Cargo): `X` is a wildcard
expect all_in("1.X", ["1.0.0", "1.9.9"])
expect none_in("1.X", ["2.0.0"])
expect all_in("1.2.X", ["1.2.0", "1.2.7"])
expect none_in("1.2.X", ["1.3.0"])
expect all_in("X", ["0.0.0", "5.0.0"])

# T-VR35 (Q3 settled, npm, Cargo): an operator with a wildcard is the operator with the parts before the wildcard
expect ["^1.x", "^1.*", "=1.*", "=1.x"].all(|r| all_in(r, ["1.0.0", "1.9.9"]))
expect ["^1.x", "^1.*", "=1.*", "=1.x"].all(|r| none_in(r, ["0.9.9", "2.0.0"]))
expect all_in("^0.x", ["0.0.0", "0.9.9"])
expect none_in("^0.x", ["1.0.0"])
expect all_in("^0.0.x", ["0.0.0", "0.0.9"])
expect none_in("^0.0.x", ["0.1.0"])
expect all_in(">=1.x", ["1.0.0", "7.0.0"])
expect none_in(">=1.x", ["0.9.9"])
expect all_in("<=1.2.x", ["1.2.9", "0.1.0"])
expect none_in("<=1.2.x", ["1.3.0"])

# ---- `=` with fewer parts (Q4 settled: Cargo) ----

# T-VR36 (Q4 settled): `=1.2` is >=1.2.0, <1.3.0, and `=1` is >=1.0.0, <2.0.0
expect all_in("=1.2", ["1.2.0", "1.2.9"])
expect none_in("=1.2", ["1.1.9", "1.3.0"])
expect all_in("=1", ["1.0.0", "1.9.9"])
expect none_in("=1", ["0.9.9", "2.0.0"])

# ---- Operators, lists, spaces (Q7 settled: kept from the source) ----

# T-VR37 (smores Comparator.roc): each operator on the full version 1.2.3, against 1.2.3
expect ["=1.2.3", "<=1.2.3", ">=1.2.3", "~1.2.3", "^1.2.3"].all(|r| all_in(r, ["1.2.3"]))
expect ["<1.2.3", ">1.2.3"].all(|r| none_in(r, ["1.2.3"]))

# T-VR38 (Q7 settled, npm, Cargo): `>`, `>=`, `<`, `<=` on a full version
expect all_in(">1.2.3", ["1.2.4", "2.0.0"])
expect none_in(">1.2.3", ["1.2.3", "1.0.0"])
expect all_in("<1.2.3", ["1.2.2", "0.0.0"])
expect none_in("<1.2.3", ["1.2.3", "1.3.0"])
expect all_in("<=1.2.3", ["1.2.3", "1.0.0"])
expect none_in("<=1.2.3", ["1.2.4"])

# T-VR39 (Q7 settled, npm, Cargo): the operators on a partial version
expect all_in(">1.2", ["1.3.0"])
expect none_in(">1.2", ["1.2.9"])
expect all_in(">1", ["2.0.0"])
expect none_in(">1", ["1.9.9"])
expect all_in(">=1.2", ["1.2.0"])
expect none_in(">=1.2", ["1.1.9"])
expect all_in("<1.2", ["1.1.9"])
expect none_in("<1.2", ["1.2.0"])
expect all_in("<=1.2", ["1.2.9"])
expect none_in("<=1.2", ["1.3.0"])
expect all_in("<=1", ["1.9.9"])
expect none_in("<=1", ["2.0.0"])

# T-VR40 (Q7 settled, npm, Cargo): `~` allows patch updates (and minor updates for `~1`)
expect all_in("~1.2.3", ["1.2.3", "1.2.9"])
expect none_in("~1.2.3", ["1.2.2", "1.3.0"])
expect all_in("~1.2", ["1.2.0", "1.2.9"])
expect none_in("~1.2", ["1.3.0"])
expect all_in("~1", ["1.0.0", "1.9.9"])
expect none_in("~1", ["2.0.0"])
expect all_in("~0.2.3", ["0.2.3", "0.2.9"])
expect none_in("~0.2.3", ["0.3.0"])

# T-VR41 (smores Parse.roc): a comma list matches when each comparator matches
expect all_in(">=1.2.3, <1.8.0-alpha.beta", ["1.2.3", "1.7.9"])
expect none_in(">=1.2.3, <1.8.0-alpha.beta", ["1.2.2", "1.8.0"])
expect all_in(">=1.2.2-alpha.beta, <2", ["1.2.2", "1.9.0"])
expect none_in(">=1.2.2-alpha.beta, <2", ["1.2.1", "2.0.0"])

# T-VR42 (smores Parse.roc): at most 32 comparators
expect VersionReq.parse(Str.join_with(List.repeat("123", 32), ",")).is_ok()
expect parse_err(Str.join_with(List.repeat("123", 33), ",")) == Err(TooManyComparators)

# T-VR43 (Q7 settled, smores Parse.roc): spaces at the start, after an operator, and after a comma
expect ["^1.2,<1.5", "^1.2, <1.5", " ^1.2, <1.5", "^ 1.2, < 1.5"].all(|r| all_in(r, ["1.2.0", "1.4.9"]))
expect ["^1.2,<1.5", "^1.2, <1.5", " ^1.2, <1.5", "^ 1.2, < 1.5"].all(|r| none_in(r, ["1.1.9", "1.5.0"]))

# T-VR44 (Q7 settled, smores VersionReq.roc): a list prints with ", "
expect req("^2.5, <3").to_str() == "^2.5, <3"

# ---- Pre-release versions (Q6 settled) ----

# T-VR45 (Q6 settled): a range does not match a pre-release version.
# Each case has no comparator with a pre-release on the same major.minor.patch (see question Q12).
expect ["*", "^1.2", ">=1.0.0", "1.x", "^1.2.3"].all(|r| none_in(r, ["1.3.0-rc.1", "1.2.3-rc.1"]))
expect none_in(">=1.2.3-alpha", ["1.3.0-rc.1", "2.0.0-alpha"])

# T-VR46 (semver 11.3): a pre-release bound is below its release, so the release matches
expect all_in(">=1.2.3-alpha", ["1.2.3", "1.3.0"])
expect none_in("<1.2.3-alpha", ["1.2.3"])

# ---- Print (Q9 settled: the written form is kept) ----

# T-VR47 (Q9 settled): to_str gives the parsed text back for each form with no spaces
expect ["=2.0.0", "2.0.0", "2.x", "2.X", "0.25.*", "2", "1.2", "^2.1", "^0.0.3", "~1.2.3", ">=1.2.0", "<2", "=1.2", "^1.x", "*"].all(|s| req(s).to_str() == s)

# ---- Numbers (Q10 settled) ----

# T-VR48 (Q10 settled): a number larger than U64 max is an error, not a crash
expect parse_err("^18446744073709551616") == Err(InvalidComparator({ index: 0, error: InvalidMajorVersion(InvalidNumber) }))
expect parse_err("1.18446744073709551616") == Err(InvalidComparator({ index: 0, error: InvalidMinorConstraint(InvalidNumber) }))
expect parse_err("1.0.18446744073709551616") == Err(InvalidComparator({ index: 0, error: InvalidPatchConstraint(InvalidNumber) }))

# T-VR49 (Q1 settled): an upper bound past U64 max does not crash, and has no effect
expect all_in("^18446744073709551615", ["18446744073709551615.0.0", "18446744073709551615.7.1"])
expect none_in("^18446744073709551615", ["18446744073709551614.0.0"])
expect all_in("<=18446744073709551615.18446744073709551615", ["18446744073709551615.18446744073709551615.5"])
expect none_in(">18446744073709551615", ["18446744073709551615.18446744073709551615.18446744073709551615"])

# ---- Settled by slice proposal, after review 1 (human to confirm) ----

# T-VR50 (Q12 settled by slice proposal): a range never matches a pre-release version,
# also when a comparator has a pre-release on the same major.minor.patch. npm and Cargo match these.
expect none_in("=1.0.0-rc.1", ["1.0.0-rc.1"])
expect none_in(">=1.2.3-alpha", ["1.2.3-beta", "1.2.3-alpha.1"])
expect none_in("^1.2.3-alpha", ["1.2.3-alpha.1"])
expect none_in(">=1.2.3-alpha.beta, <2", ["1.2.3-alpha.beta"])

# T-VR51 (Q14 settled by slice proposal, npm): an operator with `*` alone
expect ["^*", ">=*", "~*", "=*", "<=*"].all(|r| all_in(r, ["0.0.0", "1.2.3", "99.0.0"]))
expect [">*", "<*"].all(|r| none_in(r, ["0.0.0", "1.2.3", "99.0.0"]))

# T-VR52 (Q14 settled by slice proposal, smores Parse.roc): a space before a comma or at the end is a suffix
expect parse_err("^1.2 , <2") == Err(UnexpectedSuffix(" , <2"))
expect parse_err("^1.2 ") == Err(UnexpectedSuffix(" "))

# ---- Gaps found by the verify agent (mutations M12, M42, M56) ----

# T-VR53 (Q10 settled, M12): an overflow in the multiply step is an error in a requirement too
expect parse_err("^99999999999999999999") == Err(InvalidComparator({ index: 0, error: InvalidMajorVersion(InvalidNumber) }))
expect parse_err(">=1.184467440737095516150") == Err(InvalidComparator({ index: 0, error: InvalidMinorConstraint(InvalidNumber) }))
expect parse_err("=1.0.99999999999999999999") == Err(InvalidComparator({ index: 0, error: InvalidPatchConstraint(InvalidNumber) }))

# T-VR54 (Q5 settled, M42): `x.x.x`, `*.*.*` and `X.X.X` are the same as `*`, and print back
expect ["x.x.x", "*.*.*", "X.X.X"].all(|r| all_in(r, ["0.0.0", "1.2.3", "99.0.0"]))
expect ["x.x.x", "*.*.*", "X.X.X"].all(|s| req(s).to_str() == s)

# T-VR55 (semver 11.3, M56): a pre-release bound is below its release, also for `>`, `<=` and `=`
expect all_in(">1.2.3-alpha", ["1.2.3", "1.2.4"])
expect none_in(">1.2.3-alpha", ["1.2.2"])
expect all_in("<=1.2.3-alpha", ["1.2.2", "1.0.0"])
expect none_in("<=1.2.3-alpha", ["1.2.3", "1.2.4"])
expect none_in("=1.2.3-alpha", ["1.2.2", "1.2.3", "1.2.4"])
