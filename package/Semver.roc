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
