app [main!] { pkg: "../package/main.roc" }

import pkg.Semver

main! = |_args| Ok({})

# Sources:
#   smores Parse.roc   = smores56/roc-semver package/Parse.roc (the port source, R-GA6)
#   smores Compare.roc = smores56/roc-semver package/Compare.roc
#   smores Semver.roc  = smores56/roc-semver package/Semver.roc
#   smores README.md   = smores56/roc-semver README.md
#   semver N           = https://semver.org/spec/v2.0.0.html section N
#   Q<n> settled       = an answer of the human review (slice roc-semver.md, section Settled)

## A version for the test setup. A text that does not parse stops the test.
ver : Str -> Semver
ver = |text|
	match Semver.parse(text) {
		Ok(v) => v
		Err(_) => crash "test setup: ${text} does not parse"
	}

## All parts of a parsed version, for one compare.
fields : Str -> Try((U64, U64, U64, List(Str), List(Str)), _)
fields = |text| Semver.parse(text).map_ok(|v| (v.major(), v.minor(), v.patch(), v.pre_release(), v.build()))

ord : Str, Str -> [Before, Same, After]
ord = |a, b| Semver.order_relative_to(ver(a), ver(b))

## Each adjacent pair is in order: Before one way, After the other way.
ascending : List(Str) -> Bool
ascending = |texts| {
	pairs = List.map2(texts, texts.drop_first(1), |a, b| (a, b))
	pairs.all(|(a, b)| ord(a, b) == Before and ord(b, a) == After)
}

# ---- Parse: errors (ported from smores Parse.roc) ----

# T-SV1 (smores Parse.roc): empty text
expect Semver.parse("") == Err(EmptySemver)

# T-SV2 (smores Parse.roc): a major only
expect Semver.parse("0") == Err(NoPeriodAfterMajorVersion)

# T-SV3 (smores Parse.roc): no minor after the period
expect Semver.parse("0.") == Err(InvalidMinorVersion(Empty))

# T-SV4 (smores Parse.roc): major and minor only
expect Semver.parse("0.1") == Err(NoPeriodAfterMinorVersion)

# T-SV5 (smores Parse.roc): no patch after the period
expect Semver.parse("0.1.") == Err(InvalidPatchVersion(Empty))

# T-SV6 (smores Parse.roc): a period after the patch is a suffix
expect Semver.parse("0.1.0.") == Err(UnexpectedSuffix("."))

# T-SV7 (smores Parse.roc, semver 2): a leading zero in the patch
expect Semver.parse("0.1.00") == Err(InvalidPatchVersion(CannotStartWithZero))

# T-SV8 (smores Parse.roc): an empty pre-release
expect Semver.parse("0.1.0-") == Err(InvalidPreRelease(EmptySegment))

# T-SV9 (smores Parse.roc): a pre-release with a character that is not allowed
expect Semver.parse("0.1.0-?") == Err(InvalidPreRelease(InvalidIdentifier))

# T-SV10 (smores Parse.roc): empty build metadata
expect Semver.parse("0.1.0+") == Err(InvalidBuild(EmptySegment))

# T-SV11 (smores Parse.roc): build metadata with a character that is not allowed
expect Semver.parse("0.1.0+?") == Err(InvalidBuild(InvalidIdentifier))

# ---- Parse: valid forms (ported from smores) ----

# T-SV12 (smores Parse.roc): a release version
expect fields("0.1.0") == Ok((0, 1, 0, [], []))

# T-SV13 (smores Parse.roc): pre-release identifiers
expect fields("0.1230.0-alpha.beta") == Ok((0, 1230, 0, ["alpha", "beta"], []))

# T-SV14 (smores Parse.roc): build identifiers
expect fields("0.1230.0+alpha.beta") == Ok((0, 1230, 0, [], ["alpha", "beta"]))

# T-SV15 (smores Parse.roc): a hyphen inside a pre-release identifier, then build metadata
expect fields("0.1230.0-alpha-beta+gamma.delta") == Ok((0, 1230, 0, ["alpha-beta"], ["gamma", "delta"]))

# T-SV16 (smores Parse.roc): a hyphen after `+` is part of the build metadata
expect fields("0.1230.0+alpha-beta") == Ok((0, 1230, 0, [], ["alpha-beta"]))

# T-SV17 (smores README.md): pre-release and build metadata
expect fields("1.2.3-alpha.beta+build--") == Ok((1, 2, 3, ["alpha", "beta"], ["build--"]))

# T-SV18 (smores Semver.roc, doc of parse)
expect fields("1.2.3-alpha+beta") == Ok((1, 2, 3, ["alpha"], ["beta"]))

# T-SV19 (smores Semver.roc, doc of parse_lazy): the text after the version
expect Semver.parse_lazy("1.2.3 abc") == Ok((Semver.new(1, 2, 3), " abc"))

# T-SV20 (smores Semver.roc, doc of parse_lazy): no text after the version
expect Semver.parse_lazy("1.2.3") == Ok((Semver.new(1, 2, 3), ""))

# ---- Parse: semver.org rules ----

# T-SV21 (semver 2): no leading zeros in major and minor
expect Semver.parse("01.0.0") == Err(InvalidMajorVersion(CannotStartWithZero))
expect Semver.parse("1.01.0") == Err(InvalidMinorVersion(CannotStartWithZero))

# T-SV22 (semver 2): the numbers are non-negative integers
expect Semver.parse("-1.0.0").is_err()
expect Semver.parse("1.-1.0").is_err()
expect Semver.parse("a.b.c").is_err()

# T-SV23 (semver 2): the form is X.Y.Z, exactly 3 numbers
expect Semver.parse("1.0").is_err()
expect Semver.parse("1.0.0.0").is_err()

# T-SV24 (semver 9): the pre-release examples of the spec
expect fields("1.0.0-alpha") == Ok((1, 0, 0, ["alpha"], []))
expect fields("1.0.0-alpha.1") == Ok((1, 0, 0, ["alpha", "1"], []))
expect fields("1.0.0-0.3.7") == Ok((1, 0, 0, ["0", "3", "7"], []))
expect fields("1.0.0-x.7.z.92") == Ok((1, 0, 0, ["x", "7", "z", "92"], []))
expect fields("1.0.0-x-y-z.--") == Ok((1, 0, 0, ["x-y-z", "--"], []))

# T-SV25 (semver 9): identifiers are [0-9A-Za-z-], so upper case letters are valid.
# Port change: the is_letter of smores Parse.roc accepts lower case only.
expect fields("1.0.0-RC.1") == Ok((1, 0, 0, ["RC", "1"], []))
expect fields("1.0.0+Build.ABC") == Ok((1, 0, 0, [], ["Build", "ABC"]))

# T-SV26 (semver 9): a numeric pre-release identifier has no leading zero
expect Semver.parse("1.0.0-alpha.01").is_err()
expect Semver.parse("1.0.0-00").is_err()

# T-SV27 (semver 9): a leading zero is valid in an identifier that is not numeric
expect fields("1.0.0-0a") == Ok((1, 0, 0, ["0a"], []))

# T-SV28 (semver 9): an empty pre-release identifier is not valid
expect Semver.parse("1.0.0-a..b").is_err()
expect Semver.parse("1.0.0-a.").is_err()

# T-SV29 (semver 9): a character outside [0-9A-Za-z-] is not valid
expect Semver.parse("1.0.0-alpha_beta").is_err()

# T-SV30 (semver 10): the build metadata examples of the spec. A leading zero is valid in build metadata.
expect fields("1.0.0-alpha+001") == Ok((1, 0, 0, ["alpha"], ["001"]))
expect fields("1.0.0+20130313144700") == Ok((1, 0, 0, [], ["20130313144700"]))
expect fields("1.0.0-beta+exp.sha.5114f85") == Ok((1, 0, 0, ["beta"], ["exp", "sha", "5114f85"]))
expect fields("1.0.0+21AF26D3----117B344092BD") == Ok((1, 0, 0, [], ["21AF26D3----117B344092BD"]))

# T-SV31 (semver 10): an empty build identifier is not valid
expect Semver.parse("1.0.0+a..b").is_err()

# T-SV32 (semver FAQ "Is v1.2.3 a semantic version?": no)
expect Semver.parse("v1.2.3").is_err()

# T-SV33 (smores Semver.roc, doc of parse: no other text): no space before or after
expect Semver.parse(" 1.2.3").is_err()
expect Semver.parse("1.2.3 ").is_err()

# T-SV52 (Q10 settled): a number larger than U64 max is an error, not a crash
expect Semver.parse("18446744073709551616.0.0") == Err(InvalidMajorVersion(InvalidNumber))
expect Semver.parse("0.18446744073709551616.0") == Err(InvalidMinorVersion(InvalidNumber))
expect Semver.parse("0.0.18446744073709551616") == Err(InvalidPatchVersion(InvalidNumber))
expect fields("18446744073709551615.18446744073709551615.18446744073709551615") == Ok((18446744073709551615, 18446744073709551615, 18446744073709551615, [], []))

# T-SV53 (Q13 settled by slice proposal): a numeric pre-release identifier above U64 max is valid (semver 9)
expect fields("1.0.0-18446744073709551616") == Ok((1, 0, 0, ["18446744073709551616"], []))
expect ver("1.0.0-99999999999999999999999.x").to_str() == "1.0.0-99999999999999999999999.x"

# T-SV54 (Q13 settled by slice proposal, semver 11.4.1): it compares as a number of any size
expect ascending(["1.0.0-2", "1.0.0-18446744073709551615", "1.0.0-18446744073709551616", "1.0.0-99999999999999999999", "1.0.0-100000000000000000000", "1.0.0-a"])

# T-SV55 (Q10 settled): an overflow in the multiply step (n * 10) is an error, not a wrap
expect Semver.parse("99999999999999999999.0.0") == Err(InvalidMajorVersion(InvalidNumber))
expect Semver.parse("184467440737095516150.0.0") == Err(InvalidMajorVersion(InvalidNumber))
expect Semver.parse("0.99999999999999999999.0") == Err(InvalidMinorVersion(InvalidNumber))
expect Semver.parse("0.0.184467440737095516150") == Err(InvalidPatchVersion(InvalidNumber))

# ---- Print ----

# T-SV34 (smores Semver.roc): a release version
expect Semver.new(1, 2, 3).to_str() == "1.2.3"

# T-SV35 (smores Semver.roc): pre-release, then build metadata
expect ver("1.2.3-abc+def-.ghi").to_str() == "1.2.3-abc+def-.ghi"

# T-SV36 (TESTING.md 4, semver 9, 10): to_str gives the parsed text back for each valid sample
expect {
	samples = [
		"0.0.0",
		"0.1.0",
		"18446744073709551615.0.1",
		"1.2.3-alpha+beta",
		"1.2.3-alpha.beta+build--",
		"1.0.0-x.7.z.92",
		"1.0.0-x-y-z.--",
		"1.0.0-RC.1",
		"1.0.0-0a",
		"1.0.0-alpha+001",
		"1.0.0+21AF26D3----117B344092BD",
	]
	samples.all(|s| ver(s).to_str() == s)
}

# ---- new, accessors, equality ----

# T-SV37 (R-PK2): new gives a release version
expect Semver.new(0, 25, 1) == ver("0.25.1")
expect fields("0.25.1") == Ok((0, 25, 1, [], []))

# T-SV38 (decision D5): == compares all parts, also the build metadata
expect ver("1.0.0") == ver("1.0.0")
expect ver("1.0.0+a") != ver("1.0.0+b")
expect ver("1.0.0-alpha") != ver("1.0.0")

# ---- Order (semver 11) ----

# T-SV39 (semver 11.2): major, minor, patch compare as numbers
expect ascending(["1.0.0", "2.0.0", "2.1.0", "2.1.1"])
expect ascending(["1.9.0", "1.10.0", "1.11.0"])

# T-SV40 (semver 11.3): a pre-release is before its release
expect ord("1.0.0-alpha", "1.0.0") == Before

# T-SV41 (semver 11.4): the example chain of the spec
expect ascending(["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"])

# T-SV42 (semver 11): a version is Same as itself
expect ["1.0.0", "1.0.0-alpha.1", "0.0.1+b"].all(|s| ord(s, s) == Same)

# T-SV43 (semver 10, 11): build metadata does not change the precedence
expect ord("1.0.0+a", "1.0.0+b") == Same
expect ord("1.0.0-alpha+001", "1.0.0-alpha") == Same

# T-SV44 (semver 11, List.sort_with): sort gives the order of the spec
expect {
	sorted = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "2.0.0", "2.1.0", "2.1.1"]
	mixed = ["2.1.1", "1.0.0-beta.11", "1.0.0", "1.0.0-alpha.beta", "2.0.0", "1.0.0-alpha", "1.0.0-rc.1", "2.1.0", "1.0.0-beta.2", "1.0.0-alpha.1", "1.0.0-beta"]
	mixed.map(ver).sort_with(Semver.order_relative_to).map(Semver.to_str) == sorted
}

# T-SV45 (smores Compare.roc): major first, then minor, then patch
expect ord("1.2.3", "2.2.3") == Before
expect ord("1.2.3", "0.2.3") == After
expect ord("1.2.3", "1.1.3") == After
expect ord("1.2.3", "1.3.3") == Before
expect ord("1.2.3", "0.3.3") == After
expect ord("1.2.3", "1.2.2") == After
expect ord("1.2.3", "1.2.4") == Before
expect ord("1.2.3", "0.2.4") == After
expect ord("1.2.3", "1.1.4") == After

# T-SV46 (smores Compare.roc): pre-release compares only when major, minor and patch are the same
expect ord("1.2.3-alpha", "1.2.3") == Before
expect ord("1.2.3", "0.2.3-alpha") == After
expect ord("1.2.3", "1.1.3-alpha") == After
expect ord("1.2.3", "1.2.2-alpha") == After

# T-SV47 (smores Compare.roc): build metadata is ignored
expect ord("1.2.3", "1.2.3+alpha") == Same

# T-SV48 (smores Compare.roc, semver 11.4.4): with equal common identifiers, more identifiers is after
expect ord("1.0.0-a", "1.0.0-a") == Same
expect ord("1.0.0-a.a", "1.0.0-a") == After
expect ord("1.0.0-a", "1.0.0-a.a") == Before

# T-SV49 (smores Compare.roc, semver 11.4.1): numeric identifiers compare as numbers.
# Port change: the source case ["10"] against ["00"] is not a valid version ("00"), so this file uses 10 against 9.
expect ord("1.0.0-1", "1.0.0-2") == Before
expect ord("1.0.0-2", "1.0.0-1") == After
expect ord("1.0.0-10", "1.0.0-9") == After

# T-SV50 (smores Compare.roc, semver 11.4.3): a numeric identifier is before an alphanumeric one
expect ord("1.0.0-0", "1.0.0-a") == Before
expect ord("1.0.0-a", "1.0.0-0") == After
expect ord("1.0.0-9", "1.0.0-Z") == Before

# T-SV51 (smores Compare.roc, semver 11.4.2): alphanumeric identifiers compare in ASCII order
expect ord("1.0.0-abc", "1.0.0-def") == Before
expect ord("1.0.0-def", "1.0.0-abc") == After
expect ord("1.0.0-a", "1.0.0-A") == After
expect ord("1.0.0-a", "1.0.0-ab") == Before
expect ord("1.0.0-ab", "1.0.0-a") == After
