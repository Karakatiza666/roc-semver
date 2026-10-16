# Ported from smores56/roc-semver (package/Compare.roc), see LICENSE.

## The precedence rules of semver section 11.
Precedence :: [].{

	## Major, then minor, then patch, as numbers (semver 11.2).
	order_triple : (U64, U64, U64), (U64, U64, U64) -> [Before, Same, After]
	order_triple = |(a1, a2, a3), (b1, b2, b3)|
		then_order(a1.order_relative_to(b1), |_| then_order(a2.order_relative_to(b2), |_| a3.order_relative_to(b3)))

	## Pre-release identifiers (semver 11.3, 11.4). No identifiers is a release, after each pre-release.
	order_pre_release : List(Str), List(Str) -> [Before, Same, After]
	order_pre_release = |a, b|
		if a.is_empty() and b.is_empty() {
			Same
		} else if a.is_empty() {
			After
		} else if b.is_empty() {
			Before
		} else {
			order_identifier_lists(a, b)
		}
}

then_order : [Before, Same, After], ({} -> [Before, Same, After]) -> [Before, Same, After]
then_order = |first, next| if first == Same next({}) else first

## The first identifier that differs decides. If all common identifiers are equal, more identifiers is after (semver 11.4.4).
order_identifier_lists : List(Str), List(Str) -> [Before, Same, After]
order_identifier_lists = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => then_order(order_identifier(x, y), |_| order_identifier_lists(xs, ys))
	}

## Numeric before alphanumeric (semver 11.4.3). Numbers of any size compare by value (Q13): a numeric identifier has no leading zero, so more digits is a larger number.
order_identifier : Str, Str -> [Before, Same, After]
order_identifier = |x, y| {
	xb = x.to_utf8()
	yb = y.to_utf8()
	match (is_numeric(xb), is_numeric(yb)) {
		(True, True) => then_order(xb.len().order_relative_to(yb.len()), |_| order_bytes(xb, yb))
		(True, False) => Before
		(False, True) => After
		(False, False) => order_bytes(xb, yb)
	}
}

is_numeric : List(U8) -> Bool
is_numeric = |bytes| bytes.all(|b| b >= '0' and b <= '9')

## ASCII order, byte by byte (semver 11.4.2). A prefix is before the longer text.
order_bytes : List(U8), List(U8) -> [Before, Same, After]
order_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x == y order_bytes(xs, ys) else x.order_relative_to(y)
	}
