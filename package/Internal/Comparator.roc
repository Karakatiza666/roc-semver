# Ported from smores56/roc-semver (package/Comparator.roc, package/Parse.roc), see LICENSE.
import Lex
import Precedence

## One comparator of a requirement: its text and the release versions that it matches.
## The versions are the interval from `lower` (inclusive) to `upper` (exclusive). `End` is after each version.
## Only release versions match (Q6, Q12), so a pre-release in the comparator changes only the bounds.
Comparator :: {
	text : Str,
	lower : [At(U64, U64, U64), End],
	upper : [At(U64, U64, U64), End],
}.{

	## The comparator `*`.
	any : Comparator
	any = { text: "*", lower: At(0, 0, 0), upper: End }

	## Reads one comparator. Spaces are allowed at the start and after the operator.
	parse : List(U8) -> Try(
		(Comparator, List(U8)),
		[
			InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
			InvalidMinorConstraint([Empty, InvalidNumber, CannotStartWithZero]),
			InvalidPatchConstraint([Empty, InvalidNumber, CannotStartWithZero]),
			InvalidPreReleaseConstraint([EmptySegment, InvalidIdentifier]),
			BuildMetadataNotAllowed,
			UnexpectedSuffix(Str),
		],
	)
	parse = |bytes| {
		start = Lex.drop_spaces(bytes)
		(op, op_len) = operator(start)
		version = Lex.drop_spaces(start.drop_first(op_len))
		(parts, wild, rest) = parse_parts(version)?
		if rest.first() == Ok('+') {
			Err(BuildMetadataNotAllowed)
		} else {
			# The text keeps the written form, with no spaces (Q9).
			text = Lex.as_str(start.take_first(op_len).concat(version.take_first(version.len() - rest.len())))
			(lower, upper) = bounds(resolve(op, parts, wild), parts)
			Ok(({ text, lower, upper }, rest))
		}
	}

	to_str : Comparator -> Str
	to_str = |c| c.text

	## True when the release version (major, minor, patch) is in the interval.
	accepts : Comparator, (U64, U64, U64) -> Bool
	accepts = |c, v| at_or_after(v, c.lower) and before(v, c.upper)
}

Op : [Eq, Gt, Ge, Lt, Le, Tilde, Caret]

## The given parts of the version. `Patch` records if a pre-release follows.
Parts : [Any, Major(U64), Minor(U64, U64), Patch(U64, U64, U64, Bool)]

Bound : [At(U64, U64, U64), End]

## The operator and its length in bytes. `Bare` is no operator.
operator : List(U8) -> ([Bare, Given(Op)], U64)
operator = |bytes|
	match bytes {
		['>', '=', ..] => (Given(Ge), 2)
		['<', '=', ..] => (Given(Le), 2)
		['>', ..] => (Given(Gt), 1)
		['<', ..] => (Given(Lt), 1)
		['=', ..] => (Given(Eq), 1)
		['~', ..] => (Given(Tilde), 1)
		['^', ..] => (Given(Caret), 1)
		_ => (Bare, 0)
	}

## With no operator: a wildcard or 3 parts is exact, 1 or 2 parts is a caret (R-SL15, T-VR21).
resolve : [Bare, Given(Op)], Parts, Bool -> Op
resolve = |op, parts, wild|
	match op {
		Given(given) => given
		Bare =>
			match parts {
				Patch(_, _, _, _) => Eq
				_ => if wild Eq else Caret
			}
	}

## The parts of the version, if a wildcard was written, and the bytes after the version.
## After a wildcard, only wildcard parts can follow (Q5). An operator with a wildcard uses the parts before it (Q3).
parse_parts : List(U8) -> Try(
	(Parts, Bool, List(U8)),
	[
		InvalidMajorVersion([Empty, InvalidNumber, CannotStartWithZero]),
		InvalidMinorConstraint([Empty, InvalidNumber, CannotStartWithZero]),
		InvalidPatchConstraint([Empty, InvalidNumber, CannotStartWithZero]),
		InvalidPreReleaseConstraint([EmptySegment, InvalidIdentifier]),
	],
)
parse_parts = |bytes|
	match wildcard(bytes) {
		Ok(rest) => Ok((Any, True, skip_wildcards(rest, 2)))
		Err(NotWildcard) => {
			(major, b1) = Lex.number(bytes) ? InvalidMajorVersion
			(minor, b2) = part(b1) ? InvalidMinorConstraint
			match minor {
				Missing => Ok((Major(major), False, b2))
				Wild => Ok((Major(major), True, skip_wildcards(b2, 1)))
				Num(mi) => {
					(patch, b3) = part(b2) ? InvalidPatchConstraint
					match patch {
						Missing => Ok((Minor(major, mi), False, b3))
						Wild => Ok((Minor(major, mi), True, b3))
						Num(p) => {
							(pre, b4) = pre_release(b3) ? InvalidPreReleaseConstraint
							Ok((Patch(major, mi, p, !pre.is_empty()), False, b4))
						}
					}
				}
			}
		}
	}

## The part after a `.`: a number, a wildcard, or no part.
part : List(U8) -> Try(([Num(U64), Wild, Missing], List(U8)), [Empty, InvalidNumber, CannotStartWithZero])
part = |bytes|
	match bytes {
		['.', .. as rest] =>
			match wildcard(rest) {
				Ok(after) => Ok((Wild, after))
				Err(NotWildcard) => {
					(n, after) = Lex.number(rest)?
					Ok((Num(n), after))
				}
			}
		_ => Ok((Missing, bytes))
	}

pre_release : List(U8) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
pre_release = |bytes|
	match bytes {
		['-', .. as rest] => Lex.pre_release(rest)
		_ => Ok(([], bytes))
	}

is_wildcard : U8 -> Bool
is_wildcard = |b| b == '*' or b == 'x' or b == 'X'

wildcard : List(U8) -> Try(List(U8), [NotWildcard])
wildcard = |bytes|
	match bytes {
		[b, .. as rest] if is_wildcard(b) => Ok(rest)
		_ => Err(NotWildcard)
	}

## Drops at most `count` parts `.x` after a wildcard.
skip_wildcards : List(U8), U64 -> List(U8)
skip_wildcards = |bytes, count|
	match bytes {
		['.', b, .. as rest] if count > 0 and is_wildcard(b) => skip_wildcards(rest, count - 1)
		_ => bytes
	}

## The interval of an operator (npm and Cargo meaning, Q1 to Q4, Q7, Q14).
bounds : Op, Parts -> (Bound, Bound)
bounds = |op, parts|
	match op {
		Eq => (floor(parts), next(parts))
		Gt => (next(parts), End)
		Ge => (floor(parts), End)
		Lt => (At(0, 0, 0), floor(parts))
		Le => (At(0, 0, 0), next(parts))
		Tilde => (floor(parts), tilde_upper(parts))
		Caret => (floor(parts), caret_upper(parts))
	}

## The first release version with the given parts. Missing parts are 0.
floor : Parts -> Bound
floor = |parts|
	match parts {
		Any => At(0, 0, 0)
		Major(ma) => At(ma, 0, 0)
		Minor(ma, mi) => At(ma, mi, 0)
		Patch(ma, mi, pa, _) => At(ma, mi, pa)
	}

## The first release version after the versions with the given parts.
## A pre-release `M.m.p-pre` is below `M.m.p`, so the next release version is `M.m.p`.
next : Parts -> Bound
next = |parts|
	match parts {
		Any => End
		Major(ma) => after_major(ma)
		Minor(ma, mi) => after_minor(ma, mi)
		Patch(ma, mi, pa, has_pre) => if has_pre At(ma, mi, pa) else after_patch(ma, mi, pa)
	}

## `~` allows patch updates, and minor updates when only the major is given.
tilde_upper : Parts -> Bound
tilde_upper = |parts|
	match parts {
		Any => End
		Major(ma) => after_major(ma)
		Minor(ma, mi) => after_minor(ma, mi)
		Patch(ma, mi, _, _) => after_minor(ma, mi)
	}

## `^` allows no change of the left-most part that is not zero (Q1). `^0` and `^0.0` keep the given zeros (Q1, Q2).
caret_upper : Parts -> Bound
caret_upper = |parts|
	match parts {
		Any => End
		Major(ma) => after_major(ma)
		Minor(ma, mi) => if ma > 0 after_major(ma) else after_minor(0, mi)
		Patch(ma, mi, pa, _) =>
			if ma > 0 {
				after_major(ma)
			} else if mi > 0 {
				after_minor(0, mi)
			} else {
				after_patch(0, 0, pa)
			}
	}

## The successors carry past U64 max, so an upper bound past U64 max is `End` (Q10).
after_major : U64 -> Bound
after_major = |ma| if ma == U64.highest End else At(ma + 1, 0, 0)

after_minor : U64, U64 -> Bound
after_minor = |ma, mi| if mi == U64.highest after_major(ma) else At(ma, mi + 1, 0)

after_patch : U64, U64, U64 -> Bound
after_patch = |ma, mi, pa| if pa == U64.highest after_minor(ma, mi) else At(ma, mi, pa + 1)

at_or_after : (U64, U64, U64), Bound -> Bool
at_or_after = |v, bound|
	match bound {
		End => False
		At(ma, mi, pa) => Precedence.order_triple(v, (ma, mi, pa)) != Before
	}

before : (U64, U64, U64), Bound -> Bool
before = |v, bound|
	match bound {
		End => True
		At(ma, mi, pa) => Precedence.order_triple(v, (ma, mi, pa)) == Before
	}
