app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Semver

# Slice 100 of the Talon registry plan; the rules are R-IK5 (Talon DESIGN-REGISTRY.md 5.1) and R-PK2 (DESIGN.md 6.1).
# Reference: research/semver-key/test.mjs in the Talon repository (cases S1 and S2).
# For 2 versions a and b from a domain with the edge values of the key (0xFFFE, 0xFFFF, 0x10000, U64 max),
# pre-releases and build metadata, where b is often a version near a:
#   R-IK5 property 1 (monotone): Before gives key(a) <= key(b), After gives key(a) >= key(b), Same gives equal keys.
#   R-IK5 property 2 (exact): `exact` is True exactly for a release with each part below 0xFFFF and no build metadata.
#     An exact key gives the version back with `from_key`. The key of a version with build metadata is the key of its release.
#   R-PK2 (from_key): for a key made from 16-bit fields (and for any U64), when from_key gives a version,
#     to_key of it gives the same key with `exact` True, and from_key gives a version exactly when the pre-release
#     code is 0xFFFF and each of major, minor and patch is below 0xFFFF.

## Part values with the edges of the key
part_pool : List(U64)
part_pool = [0, 1, 2, 3, 9, 10, 4094, 4095, 65534, 65535, 65536, 4294967295, U64.highest]

## Pre-release first identifiers to choose from: numeric, alphanumeric, and a number above U64 max
id_pool : List(Str)
id_pool = ["0", "1", "11", "4093", "4094", "4095", "99999", "123456789012345678901234567890", "alpha", "alpha4", "alpha10", "beta", "rc", "a", "A", "Z9", "x-y", "-", "0a", "1-", "zz"]

## Fields of a key to choose from: unused codes, the saturated value, and the edges of the codes
field_pool : List(U64)
field_pool = [0, 1, 2, 0x0fff, 0x1000, 0x19d7, 0x203e, 0x203f, 0xfffe, 0xffff]

Input := { bytes : List(U8), raw : U64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { bytes: Fuzz.list(Fuzz.u8, 40), raw: Fuzz.u64 }.Fuzz
}

at : List(U8), U64 -> U64
at = |bytes, i| (bytes.get(i) ?? 0).to_u64()

pick : List(a), U64 -> a
pick = |pool, i| pool.get(i % pool.len()) ?? crash "empty pool"

Spec : { major : U64, minor : U64, patch : U64, pre : List(Str), build : List(Str) }

## The version a from 10 bytes at `offset`: 3 parts, 0 to 3 pre-release identifiers, 0 or 1 build identifier
spec_at : List(U8), U64 -> Spec
spec_at = |bytes, offset| {
	b = |i| at(bytes, offset + i)
	pre_count = b(3) % 4
	pre = [b(4), b(5), b(6)].take_first(pre_count).map(|i| pick(id_pool, i))
	{
		major: pick(part_pool, b(0)),
		minor: pick(part_pool, b(1)),
		patch: pick(part_pool, b(2)),
		pre,
		build: if b(7) % 3 == 0 ["b${(b(8) % 3).to_str()}"] else [],
	}
}

## A version near a: one part or the pre-release changes, as in the reference (`near`)
near : Spec, List(U8) -> Spec
near = |a, bytes| {
	b = |i| at(bytes, 20 + i)
	new_part = |old| if b(2) % 3 == 0 old.plus_saturated(b(3) % 3) else pick(part_pool, b(3))
	match b(1) % 4 {
		0 => { ..a, build: [], major: new_part(a.major) }
		1 => { ..a, build: [], minor: new_part(a.minor) }
		2 => { ..a, build: [], patch: new_part(a.patch) }
		_ => { ..a, build: [], pre: if b(2) % 2 == 0 [] else [pick(id_pool, b(3))] }
	}
}

text_of : Spec -> Str
text_of = |s| {
	pre = if s.pre.is_empty() "" else "-${Str.join_with(s.pre, ".")}"
	build = if s.build.is_empty() "" else "+${Str.join_with(s.build, ".")}"
	"${s.major.to_str()}.${s.minor.to_str()}.${s.patch.to_str()}${pre}${build}"
}

parse : Str -> Semver
parse = |text|
	match Semver.parse(text) {
		Ok(v) => v
		Err(_) => crash "valid text ${text} did not parse"
	}

show_u64 : U64 -> Str
show_u64 = |n| Str.inspect(n)

check_pair : Str, Str -> {}
check_pair = |ta, tb| {
	a = parse(ta)
	b = parse(tb)
	ka = a.to_key().key
	kb = b.to_key().key
	ok =
		match Semver.order_relative_to(a, b) {
			Before => ka <= kb
			After => ka >= kb
			Same => ka == kb
		}
	if !ok {
		crash "key order differs from the order of versions: ${ta} (${show_u64(ka)}) and ${tb} (${show_u64(kb)})"
	}
	{}
}

check_exact : Str -> {}
check_exact = |text| {
	v = parse(text)
	k = v.to_key()
	small = v.major() < 65535 and v.minor() < 65535 and v.patch() < 65535
	want_exact = small and v.pre_release().is_empty() and v.build().is_empty()
	if k.exact != want_exact {
		crash "exact is ${Str.inspect(k.exact)} for ${text}"
	}
	# A release with build metadata is not exact, but its key is the key of the release: from_key gives the release.
	match Semver.from_key(k.key) {
		Ok(back) =>
			if k.exact {
				if back != v crash "from_key of the key of ${text} gives ${back.to_str()}" else {}
			} else if !small or !v.pre_release().is_empty() or back != Semver.new(v.major(), v.minor(), v.patch()) {
				crash "from_key of the key of ${text} (not exact) gives ${back.to_str()}"
			} else {
				{}
			}
		Err(NotExact) => if k.exact crash "exact key of ${text} gives NotExact" else {}
	}
}

check_key : U64 -> {}
check_key = |k| {
	f = |shift| (k // shift) % 65536
	fields_ok = f(281474976710656) < 65535 and f(4294967296) < 65535 and f(65536) < 65535
	want_ok = fields_ok and k % 65536 == 65535
	match Semver.from_key(k) {
		Ok(v) => {
			if !want_ok or v.to_key() != { key: k, exact: True } {
				crash "from_key(${show_u64(k)}) gives ${v.to_str()}, and to_key of it gives ${show_u64(v.to_key().key)}"
			}
			{}
		}
		Err(NotExact) => if want_ok crash "from_key(${show_u64(k)}) gives NotExact" else {}
	}
}

test : Input -> Fuzz.Outcome
test = |input| {
	a = spec_at(input.bytes, 0)
	b = if at(input.bytes, 20) % 2 == 0 near(a, input.bytes) else spec_at(input.bytes, 10)
	check_pair(text_of(a), text_of(b))
	check_exact(text_of(a))
	check_exact(text_of(b))
	c = |i| pick(field_pool, at(input.bytes, 30 + i))
	check_key(c(0) * 281474976710656 + c(1) * 4294967296 + c(2) * 65536 + c(3))
	check_key(input.raw)
	Fuzz.keep
}

target = Fuzz.target_with({
	name: "semver-key",
	generator: Input.generator_for(Default),
	test,
	show: |input| "${text_of(spec_at(input.bytes, 0))} ${text_of(spec_at(input.bytes, 10))} ${Str.inspect(input.bytes)} ${Str.inspect(input.raw)}",
})
