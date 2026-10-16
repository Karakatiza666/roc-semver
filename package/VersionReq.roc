# Ported from smores56/roc-semver (package/VersionReq.roc, package/Parse.roc), see LICENSE.
import Semver
import Internal/Comparator as Comparator
import Internal/Lex as Lex

## A version requirement: a list of comparators, such as `^2.1`, `=2.0.0`, `0.25.*`, `>=1.2, <1.5` or `*`.
## A version matches when it matches each comparator. Comparators are separated by `,`.
## Spaces are allowed at the start, after an operator and after a comma.
##
## | Form | Example | Matches |
## | --- | --- | --- |
## | Any | `*`, `x`, `X` | each version |
## | Exact, 3 parts | `=2.0.0`, `2.0.0` | that version only |
## | Exact, 1 or 2 parts | `=1.2`, `=1` | `>=1.2.0, <1.3.0`, `>=1.0.0, <2.0.0` |
## | Caret | `^1.2.3`, `^0.2.3`, `^0.0.3` | no change of the left-most part that is not zero: `<2.0.0`, `<0.3.0`, `<0.0.4` |
## | Caret, 1 or 2 parts | `^1`, `^1.2`, `^0.2`, `^0.0`, `^0` | `<2.0.0`, `<2.0.0`, `<0.3.0`, `<0.1.0`, `<1.0.0` |
## | Bare, 1 or 2 parts | `2`, `1.2`, `0` | as `^2`, `^1.2`, `^0` |
## | Wildcard | `2.x`, `2.1.*`, `2.x.x`, `0.x` | each version with the given parts |
## | Tilde | `~1.2.3`, `~1.2`, `~1` | `<1.3.0`, `<1.3.0`, `<2.0.0` |
## | Compare | `>1.2.3`, `>=1.2`, `<2`, `<=1.2` | as the operator, with missing parts as for `=`: `<=1.2` is `<1.3.0`, `>1` is `>=2.0.0` |
##
## An operator with a wildcard uses the parts before the wildcard: `^1.x` is `^1`.
## A range does not match a pre-release version. Build metadata is not allowed.
VersionReq :: { comparators : List(Comparator) }.{

	## The requirement `*`. It matches each version.
	star : VersionReq
	star = { comparators: [Comparator.any] }

	## Reads a requirement. The text must have no other characters.
	parse : Str -> Try(
		VersionReq,
		[
			InvalidComparator(
				{
					index : U64,
					error : [
						InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidMinorConstraint([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidPatchConstraint([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidPreReleaseConstraint([EmptySegment, InvalidIdentifier]),
						BuildMetadataNotAllowed,
						UnexpectedSuffix(Str),
					],
				},
			),
			TooManyComparators,
			UnexpectedSuffix(Str),
		],
	)
	parse = |text| {
		(req, rest) = VersionReq.parse_lazy(text)?
		if rest.is_empty() Ok(req) else Err(UnexpectedSuffix(rest))
	}

	## Reads a requirement at the start of the text, and gives the text after it.
	parse_lazy : Str -> Try(
		(VersionReq, Str),
		[
			InvalidComparator(
				{
					index : U64,
					error : [
						InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidMinorConstraint([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidPatchConstraint([Empty, InvalidNumber, CannotStartWithZero]),
						InvalidPreReleaseConstraint([EmptySegment, InvalidIdentifier]),
						BuildMetadataNotAllowed,
						UnexpectedSuffix(Str),
					],
				},
			),
			TooManyComparators,
		],
	)
	parse_lazy = |text| {
		(first, rest) = Comparator.parse(text.to_utf8()) ? |error| InvalidComparator({ index: 0, error })
		(comparators, after) = more_comparators(rest, [first])?
		Ok(({ comparators: comparators }, Lex.as_str(after)))
	}

	## The text form of the requirement.
	to_str : VersionReq -> Str
	to_str = |req| Str.join_with(req.comparators.map(Comparator.to_str), ", ")

	## True when the version is in the requirement.
	matches : VersionReq, Semver -> Bool
	matches = |req, version| {
		# A range does not match a pre-release version (Q6, Q12).
		release = (version.major(), version.minor(), version.patch())
		version.pre_release().is_empty() and req.comparators.all(|c| c.accepts(release))
	}
}

max_comparators : U64
max_comparators = 32

## The comparators after each `,`. Spaces after a comma are allowed.
more_comparators = |bytes, found|
	match bytes {
		[',', .. as rest] =>
			if found.len() >= max_comparators {
				Err(TooManyComparators)
			} else {
				(c, after) = Comparator.parse(rest) ? |error| InvalidComparator({ index: found.len(), error })
				more_comparators(after, found.append(c))
			}
		_ => Ok((found, bytes))
	}
