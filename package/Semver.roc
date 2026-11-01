# Ported from smores56/roc-semver (package/Semver.roc, package/Parse.roc), see LICENSE.
import Internal/Lex as Lex
import Internal/Precedence as Precedence

## A semantic version, as Semantic Versioning 2.0.0 gives it (https://semver.org/spec/v2.0.0.html).
##
## A value always has a valid form: `parse` and `new` are the only ways to make one.
## So `Semver.parse(v.to_str()) == Ok(v)` for each value `v`.
##
## `==` compares all parts, also the build metadata. `order_relative_to` gives the
## precedence of semver section 11, which ignores the build metadata.
Semver :: {
	major : U64,
	minor : U64,
	patch : U64,
	pre_release : List(Str),
	build : List(Str),
}.{
	is_eq : _
	to_hash : _

	## The release version `major.minor.patch`, with no pre-release and no build metadata.
	new : U64, U64, U64 -> Semver
	new = |major, minor, patch| { major, minor, patch, pre_release: [], build: [] }

	## Reads a version such as `1.2.3-alpha.1+build.5`. The text must have no other characters.
	parse : Str -> Try(
		Semver,
		[
			EmptySemver,
			InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
			NoPeriodAfterMajorVersion,
			InvalidMinorVersion([Empty, InvalidNumber, CannotStartWithZero]),
			NoPeriodAfterMinorVersion,
			InvalidPatchVersion([Empty, InvalidNumber, CannotStartWithZero]),
			InvalidPreRelease([EmptySegment, InvalidIdentifier]),
			InvalidBuild([EmptySegment, InvalidIdentifier]),
			UnexpectedSuffix(Str),
		],
	)
	parse = |text| {
		(version, rest) = Semver.parse_lazy(text)?
		if rest.is_empty() Ok(version) else Err(UnexpectedSuffix(rest))
	}

	## Reads a version at the start of the text, and gives the text after it.
	parse_lazy : Str -> Try(
		(Semver, Str),
		[
			EmptySemver,
			InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
			NoPeriodAfterMajorVersion,
			InvalidMinorVersion([Empty, InvalidNumber, CannotStartWithZero]),
			NoPeriodAfterMinorVersion,
			InvalidPatchVersion([Empty, InvalidNumber, CannotStartWithZero]),
			InvalidPreRelease([EmptySegment, InvalidIdentifier]),
			InvalidBuild([EmptySegment, InvalidIdentifier]),
		],
	)
	parse_lazy = |text|
		if text.is_empty() {
			Err(EmptySemver)
		} else {
			b0 = text.to_utf8()
			(major, b1) = Lex.number(b0) ? InvalidMajorVersion
			b2 = after_byte(b1, '.') ? |_| NoPeriodAfterMajorVersion
			(minor, b3) = Lex.number(b2) ? InvalidMinorVersion
			b4 = after_byte(b3, '.') ? |_| NoPeriodAfterMinorVersion
			(patch, b5) = Lex.number(b4) ? InvalidPatchVersion
			(pre_release, b6) = optional(b5, '-', Lex.pre_release) ? InvalidPreRelease
			(build, b7) = optional(b6, '+', Lex.build) ? InvalidBuild
			Ok(({ major, minor, patch, pre_release, build }, Lex.as_str(b7)))
		}

	## The text form: `major.minor.patch`, then `-` and the pre-release identifiers, then `+` and the build identifiers.
	to_str : Semver -> Str
	to_str = |v| {
		pre = if v.pre_release.is_empty() "" else "-${Str.join_with(v.pre_release, ".")}"
		build = if v.build.is_empty() "" else "+${Str.join_with(v.build, ".")}"
		"${v.major.to_str()}.${v.minor.to_str()}.${v.patch.to_str()}${pre}${build}"
	}

	## Precedence (semver section 11). Build metadata has no effect (semver section 10).
	## Use it with `List.sort_with`.
	order_relative_to : Semver, Semver -> [Before, Same, After]
	order_relative_to = |a, b|
		match Precedence.order_triple((a.major, a.minor, a.patch), (b.major, b.minor, b.patch)) {
			Same => Precedence.order_pre_release(a.pre_release, b.pre_release)
			other => other
		}

	## The 64-bit order key of the version (Talon registry R-IK5), and whether the key alone gives the version back.
	## Layout, high to low: major 16 bits, minor 16, patch 16, pre-release code 16.
	## Monotone: when `a` comes before `b` by `order_relative_to`, `a.to_key().key <= b.to_key().key`.
	## `exact` is True when each of major, minor and patch is below 0xFFFF and the version has no pre-release and no build metadata.
	to_key : Semver -> { key : U64, exact : Bool }
	to_key = |v| {
		major = v.major.min(field_max)
		minor = saturated_after(major, v.minor)
		patch = saturated_after(minor, v.patch)
		code = if patch == field_max field_max else pre_release_code(v.pre_release)
		key = major.shl_wrap(48).bitwise_or(minor.shl_wrap(32)).bitwise_or(patch.shl_wrap(16)).bitwise_or(code)
		{ key, exact: patch != field_max and v.pre_release.is_empty() and v.build.is_empty() }
	}

	## The release version of a key: the pre-release code is 0xFFFF and major, minor and patch are below 0xFFFF.
	## Each other key gives `Err(NotExact)`. The key of an exact version gives that version.
	from_key : U64 -> Try(Semver, [NotExact])
	from_key = |key| {
		major = key.shr_zf_wrap(48)
		minor = key.shr_zf_wrap(32).bitwise_and(field_max)
		patch = key.shr_zf_wrap(16).bitwise_and(field_max)
		code = key.bitwise_and(field_max)
		if code == field_max and major < field_max and minor < field_max and patch < field_max {
			Ok(Semver.new(major, minor, patch))
		} else {
			Err(NotExact)
		}
	}

	major : Semver -> U64
	major = |v| v.major

	minor : Semver -> U64
	minor = |v| v.minor

	patch : Semver -> U64
	patch = |v| v.patch

	## The pre-release identifiers, in order. Empty for a release version.
	pre_release : Semver -> List(Str)
	pre_release = |v| v.pre_release

	## The build metadata identifiers, in order.
	build : Semver -> List(Str)
	build = |v| v.build
}

## The largest value of a 16-bit field of the key. It also means a saturated part, and no pre-release.
field_max : U64
field_max = 0xFFFF

## The field of a part. A part of `field_max` or more gives `field_max`, and so does each part after it.
saturated_after : U64, U64 -> U64
saturated_after = |previous, part| if previous == field_max field_max else part.min(field_max)

## The 16-bit pre-release code of the key, from the first identifier (R-IK5):
## no pre-release `field_max`, numeric `0x0001 + min(n, 0x0FFE)`, other `0x1000 + 65 * rank(c1) + rank(c2)`.
pre_release_code : List(Str) -> U64
pre_release_code = |identifiers|
	match identifiers {
		[] => field_max
		[first, ..] => {
			chars = first.to_utf8()
			if chars.all(Lex.is_digit) {
				1 + chars.fold(0, |n, digit| (n * 10 + (digit - '0').to_u64()).min(0x0FFE))
			} else {
				0x1000 + 65 * char_rank(chars.get(0)) + char_rank(chars.get(1))
			}
		}
	}

## The place of a character of an identifier in ASCII order: none 0, `-` 1, digits 2 to 11, `A` to `Z` 12 to 37, `a` to `z` 38 to 63.
char_rank : Try(U8, [OutOfBounds]) -> U64
char_rank = |char|
	match char {
		Err(OutOfBounds) => 0
		Ok(c) =>
			if c == '-' {
				1
			} else if c <= '9' {
				2 + (c - '0').to_u64()
			} else if c <= 'Z' {
				12 + (c - 'A').to_u64()
			} else {
				38 + (c - 'a').to_u64()
			}
	}

after_byte : List(U8), U8 -> Try(List(U8), [ByteNotFound])
after_byte = |bytes, byte|
	match bytes {
		[first, .. as rest] if first == byte => Ok(rest)
		_ => Err(ByteNotFound)
	}

## The identifiers after `marker`, or no identifiers when the marker is not there.
optional : List(U8), U8, (List(U8) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
optional = |bytes, marker, identifiers|
	match after_byte(bytes, marker) {
		Ok(rest) => identifiers(rest)
		Err(ByteNotFound) => Ok(([], bytes))
	}
