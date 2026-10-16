app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Semver

# TESTING.md 4: the order is total and agrees with a tuple compare. Semver 10, 11.
# For 3 versions a, b, c from a small domain (so that ties and pre-releases are frequent):
#   Same on itself, antisymmetric, transitive (a total preorder),
#   build metadata has no effect (semver 10), a pre-release is before its release (semver 11.3).
# For 2 release versions with any U64 parts: the order equals the compare of (major, minor, patch).

## Pre-release identifiers to choose from (semver 9)
pool : List(Str)
pool = ["alpha", "beta", "rc", "0", "1", "2", "11", "a-b", "A", "Z9"]

Input := { small : List(U8), big : List(U64) }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { small: Fuzz.list(Fuzz.u8, 30), big: Fuzz.list(Fuzz.u64, 6) }.Fuzz
}

at : List(U8), U64 -> U8
at = |bytes, i| bytes.get(i) ?? 0

## Version text number n (0, 1 or 2) from 10 bytes: parts 0 to 2, 0 to 3 pre-release identifiers, 0 or 1 build identifier
small_text : List(U8), U64 -> Str
small_text = |bytes, n| {
	b = |i| at(bytes, n * 10 + i)
	core = "${(b(0) % 3).to_str()}.${(b(1) % 3).to_str()}.${(b(2) % 3).to_str()}"
	pre_count = (b(3) % 4).to_u64()
	pre = [b(4), b(5), b(6)].take_first(pre_count).map(|i| pool.get((i % 10).to_u64()) ?? "alpha")
	pre_part = if pre.is_empty() "" else "-${Str.join_with(pre, ".")}"
	build_part = if b(7) % 2 == 0 "" else "+b${(b(8) % 3).to_str()}"
	"${core}${pre_part}${build_part}"
}

## The text with no build metadata, and the text with no pre-release and no build metadata
no_build : Str -> Str
no_build = |text| text.split_on("+").first() ?? text

no_pre : Str -> Str
no_pre = |text| no_build(text).split_on("-").first() ?? text

parse : Str -> Semver
parse = |text|
	match Semver.parse(text) {
		Ok(v) => v
		Err(_) => crash "valid text ${text} did not parse"
	}

flip : [Before, Same, After] -> [Before, Same, After]
flip = |o|
	match o {
		Before => After
		Same => Same
		After => Before
	}

tuple_order : (U64, U64, U64), (U64, U64, U64) -> [Before, Same, After]
tuple_order = |(a1, a2, a3), (b1, b2, b3)|
	if a1 != b1 {
		U64.order_relative_to(a1, b1)
	} else if a2 != b2 {
		U64.order_relative_to(a2, b2)
	} else {
		U64.order_relative_to(a3, b3)
	}

test : Input -> Fuzz.Outcome
test = |input| {
	ta = small_text(input.small, 0)
	tb = small_text(input.small, 1)
	tc = small_text(input.small, 2)
	(a, b, c) = (parse(ta), parse(tb), parse(tc))
	ord = Semver.order_relative_to
	if ord(a, a) != Same {
		crash "${ta} is not Same as itself"
	}
	if ord(a, b) != flip(ord(b, a)) {
		crash "not antisymmetric: ${ta}, ${tb}"
	}
	if ord(a, b) != After and ord(b, c) != After and ord(a, c) == After {
		crash "not transitive: ${ta} <= ${tb} <= ${tc}"
	}
	if ord(a, b) == Before and ord(b, c) == Before and ord(a, c) != Before {
		crash "not transitive: ${ta} < ${tb} < ${tc}"
	}
	if ord(a, parse(no_build(ta))) != Same {
		crash "build metadata changes the order: ${ta}"
	}
	if no_build(ta) != no_pre(ta) and ord(a, parse(no_pre(ta))) != Before {
		crash "pre-release is not before its release: ${ta}"
	}
	g = |i| input.big.get(i) ?? 0
	(p, q) = ((g(0), g(1), g(2)), (g(3), g(4), g(5)))
	vp = Semver.new(p.0, p.1, p.2)
	vq = Semver.new(q.0, q.1, q.2)
	if ord(vp, vq) != tuple_order(p, q) {
		crash "order differs from the tuple compare: ${vp.to_str()}, ${vq.to_str()}"
	}
	Fuzz.keep
}

target = Fuzz.target_with({
	name: "semver-order",
	generator: Input.generator_for(Default),
	test,
	show: |input| "${small_text(input.small, 0)} ${small_text(input.small, 1)} ${small_text(input.small, 2)} ${Str.inspect(input.big)}",
})
