app [main!] { pkg: "../package/main.roc" }

import pkg.Semver
import pkg.VersionReq

main! = |_args| Ok({})

# L0 tests of the 64-bit order key (slice 100 of the Talon registry plan, Design 6.1 R-PK2).
# Sources:
#   R-IK5   = Talon DESIGN-REGISTRY.md 5.1, rule R-IK5: the layout, the 3 properties, the examples
#   R-PK2   = Talon DESIGN.md 6.1: the 3 signatures
#   S1 to S5 = the cases of research/semver-key/ in the Talon repository (the reference, key.mjs and test.mjs)
#   semver N = https://semver.org/spec/v2.0.0.html section N
#
# Layout of the key, high to low: major 16 bits, minor 16, patch 16, pre-release code 16.
# A part of 0xFFFF or more gives 0xFFFF for itself and for each field after it.
# Pre-release code: no pre-release 0xFFFF. Numeric first identifier n: 0x0001 + min(n, 0x0FFE).
# Alphanumeric first identifier: 0x1000 + 65 * r(c1) + r(c2), with r(none) = 0, r('-') = 1, r('0'..'9') = 2..11,
# r('A'..'Z') = 12..37, r('a'..'z') = 38..63.

## A version for the test setup. A text that does not parse stops the test.
ver : Str -> Semver
ver = |text|
	match Semver.parse(text) {
		Ok(v) => v
		Err(_) => crash "test setup: ${text} does not parse"
	}

req : Str -> VersionReq
req = |text|
	match VersionReq.parse(text) {
		Ok(r) => r
		Err(_) => crash "test setup: requirement ${text} does not parse"
	}

key_of : Str -> U64
key_of = |text| ver(text).to_key().key

KeyRow : { text : Str, key : U64, exact : Bool }

## The texts of the rows whose `to_key` is not the expected value. An empty list is a pass.
wrong_rows : List(KeyRow) -> List(Str)
wrong_rows = |rows| rows.keep_if(|r| ver(r.text).to_key() != { key: r.key, exact: r.exact }).map(|r| r.text)

## Every pair (a, b) of the list where a comes before b by `order_relative_to` and the key of a is larger.
violations : List(Str) -> List((Str, Str))
violations = |texts| {
	versions = texts.map(ver)
	versions.join_map(
		|a|
			versions.join_map(
				|b|
					if Semver.order_relative_to(a, b) == Before and a.to_key().key > b.to_key().key {
						[(a.to_str(), b.to_str())]
					} else {
						[]
					},
			),
	)
}

## The list is in strict ascending order by `order_relative_to`.
ascending : List(Str) -> Bool
ascending = |texts| {
	pairs = List.map2(texts, texts.drop_first(1), |a, b| (a, b))
	pairs.all(|(a, b)| Semver.order_relative_to(ver(a), ver(b)) == Before)
}

# ---- Semver.to_key: the examples of R-IK5 ----

# T-K1 (R-IK5 examples, S3): the 3 keys of the design, in hex
expect {
	wrong_rows([
		{ text: "1.2.3", key: 0x100020003ffff, exact: True },
		{ text: "1.2.3-beta1", key: 0x1000200031a11, exact: False },
		{ text: "1.2.3-alpha4", key: 0x10002000319d7, exact: False },
	]) == []
}

# T-K2 (R-IK5 layout, S2): the fields of a release, each part below 0xFFFF, are in their 16 bits
expect {
	wrong_rows([
		{ text: "0.0.0", key: 0xffff, exact: True },
		{ text: "0.0.1", key: 0x1ffff, exact: True },
		{ text: "1.0.0", key: 0x100000000ffff, exact: True },
		{ text: "0.1.0", key: 0x1_0000_ffff, exact: True },
		{ text: "65534.65534.65534", key: 0xfffefffefffeffff, exact: True },
		{ text: "0.0.65534", key: 0xfffeffff, exact: True },
	]) == []
}

# T-K3 (R-IK5 layout, S1): a part of 0xFFFF or more is 0xFFFF, and so is each field after it
expect {
	wrong_rows([
		{ text: "65535.0.0", key: 0xffffffffffffffff, exact: False },
		{ text: "65536.8.0", key: 0xffffffffffffffff, exact: False },
		{ text: "65535.7.8", key: 0xffffffffffffffff, exact: False },
		{ text: "4294967295.0.0", key: 0xffffffffffffffff, exact: False },
		{ text: "18446744073709551615.18446744073709551615.18446744073709551615", key: 0xffffffffffffffff, exact: False },
		{ text: "1.65535.0", key: 0x1ffffffffffff, exact: False },
		{ text: "2.65535.7", key: 0x2ffffffffffff, exact: False },
		{ text: "0.65536.0", key: 0xffffffffffff, exact: False },
		{ text: "0.65535.0", key: 0xffffffffffff, exact: False },
		{ text: "1.2.65535", key: 0x10002ffffffff, exact: False },
		{ text: "0.0.65535", key: 0xffffffff, exact: False },
	]) == []
}

# T-K4 (R-IK5 layout, S1): after a saturated part the pre-release code is 0xFFFF too, also for an alphanumeric identifier
expect {
	wrong_rows([
		{ text: "65535.0.0-alpha", key: 0xffffffffffffffff, exact: False },
		{ text: "65536.8.0-b.-", key: 0xffffffffffffffff, exact: False },
		{ text: "4294967295.0.0-99999.beta", key: 0xffffffffffffffff, exact: False },
	]) == []
}

# T-K5 (R-IK5 code, numeric first identifier, semver 11.4.1): 0x0001 + min(n, 0x0FFE).
# Only the first identifier counts. A number above U64 max (valid in a pre-release) gives the maximum code.
expect {
	wrong_rows([
		{ text: "1.0.0-0", key: 0x1000000000001, exact: False },
		{ text: "1.0.0-1", key: 0x1000000000002, exact: False },
		{ text: "1.0.0-4093", key: 0x1000000000ffe, exact: False },
		{ text: "1.0.0-4094", key: 0x1000000000fff, exact: False },
		{ text: "1.0.0-4095", key: 0x1000000000fff, exact: False },
		{ text: "1.0.0-99999", key: 0x1000000000fff, exact: False },
		{ text: "1.0.0-123456789012345678901234567890", key: 0x1000000000fff, exact: False },
		{ text: "1.0.0-0.5", key: 0x1000000000001, exact: False },
		{ text: "1.0.0-1.alpha", key: 0x1000000000002, exact: False },
	]) == []
}

# T-K6 (R-IK5 code, alphanumeric first identifier): 0x1000 + 65 * r(c1) + r(c2) from the first 2 characters.
# The text after the second character, and the later identifiers, do not change the code.
# An identifier with a digit first and a letter or `-` later is alphanumeric, not numeric.
expect {
	wrong_rows([
		{ text: "1.0.0-alpha", key: 0x10000000019d7, exact: False },
		{ text: "1.0.0-alpha4", key: 0x10000000019d7, exact: False },
		{ text: "1.0.0-alpha10", key: 0x10000000019d7, exact: False },
		{ text: "1.0.0-alpha.4", key: 0x10000000019d7, exact: False },
		{ text: "1.0.0-al", key: 0x10000000019d7, exact: False },
		{ text: "1.0.0-beta", key: 0x1000000001a11, exact: False },
		{ text: "1.0.0-beta1", key: 0x1000000001a11, exact: False },
		{ text: "1.0.0-rc", key: 0x1000000001e1f, exact: False },
		{ text: "1.0.0-rc.1", key: 0x1000000001e1f, exact: False },
		{ text: "1.0.0-a", key: 0x10000000019a6, exact: False },
		{ text: "1.0.0--", key: 0x1000000001041, exact: False },
		{ text: "1.0.0---", key: 0x1000000001042, exact: False },
		{ text: "1.0.0-0a", key: 0x10000000010a8, exact: False },
		{ text: "1.0.0-1-", key: 0x10000000010c4, exact: False },
		{ text: "1.0.0-9z", key: 0x100000000130a, exact: False },
		{ text: "1.0.0-A", key: 0x100000000130c, exact: False },
		{ text: "1.0.0-Z", key: 0x1000000001965, exact: False },
		{ text: "1.0.0-Zz", key: 0x10000000019a4, exact: False },
		{ text: "1.0.0-x-y", key: 0x1000000001f7e, exact: False },
		{ text: "1.0.0-z", key: 0x1000000001fff, exact: False },
		{ text: "1.0.0-zz", key: 0x100000000203e, exact: False },
	]) == []
}

# T-K7 (R-IK5 property 2, exact flag): the key is exact only for a release version with each part below 0xFFFF.
# A pre-release, build metadata, or a part of 0xFFFF or more makes it not exact.
expect {
	exact_of = |text| ver(text).to_key().exact
	exact_of("0.0.0")
		and exact_of("1.2.3")
			and exact_of("65534.65534.65534")
				and !exact_of("1.2.3+b")
					and !exact_of("1.2.3-0")
						and !exact_of("1.2.3-alpha")
							and !exact_of("1.2.3-alpha+b")
								and !exact_of("65535.0.0")
									and !exact_of("0.65535.0")
										and !exact_of("0.0.65535")
											and !exact_of("0.0.18446744073709551615")
}

# T-K8 (R-IK5, semver 10): build metadata has no effect on the key
expect {
	key_of("1.2.3+a") == key_of("1.2.3") and key_of("1.2.3+build.5") == key_of("1.2.3") and key_of("1.2.3-beta1+x") == key_of("1.2.3-beta1")
}

# ---- Semver.to_key: the order (property 1 and 3) ----

# T-K9 (R-IK5 property 1, S3): the chain of semver 11.4 has keys in order
expect {
	chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
	ascending(chain) and violations(chain) == []
}

# T-K10 (R-IK5 example, S3): 1.2.3-alpha4 < 1.2.3-beta1 < 1.2.3 with 3 different keys
expect {
	a = ver("1.2.3-alpha4").to_key()
	b = ver("1.2.3-beta1").to_key()
	r = ver("1.2.3").to_key()
	a.key < b.key and b.key < r.key and !a.exact and r.exact
}

# T-K11 (R-IK5 property 3, semver 11.4.2): alpha10 and alpha4 are one identifier compared as text, so alpha10 is before
# alpha4. Both get the code of `al`: one key, and `order_relative_to` gives the rest of the order.
expect {
	Semver.order_relative_to(ver("1.2.3-alpha10"), ver("1.2.3-alpha4")) == Before
		and key_of("1.2.3-alpha10") == key_of("1.2.3-alpha4")
}

# T-K12 (R-IK5, semver 11.4.1): the dotted form alpha.4 and alpha.10 compares numbers. Same key (same first identifier).
expect {
	Semver.order_relative_to(ver("1.2.3-alpha.4"), ver("1.2.3-alpha.10")) == Before
		and key_of("1.2.3-alpha.4") == key_of("1.2.3-alpha.10")
}

# T-K13 (R-IK5 code, S1 mutation "prenum", semver 11.4.3): a numeric first identifier has a smaller key than an
# alphanumeric one, also near the top of the patch range
expect {
	Semver.order_relative_to(ver("0.6.65534-0.0"), ver("0.6.65534-A")) == Before
		and key_of("0.6.65534-0.0") == 0x6fffe0001
			and key_of("0.6.65534-0.0") < key_of("0.6.65534-A")
				and key_of("1.0.0-99999") < key_of("1.0.0--")
}

# T-K14 (R-IK5 layout, S1 mutation "nosat", S4): a part of 0xFFFF or more saturates the fields after it, so the key
# of an earlier version is not larger than the key of a later one
expect {
	Semver.order_relative_to(ver("65536.8.0-b.-"), ver("4294967295.0.0-99999.beta")) == Before
		and key_of("65536.8.0-b.-") <= key_of("4294967295.0.0-99999.beta")
			and key_of("0.65536.9") <= key_of("0.4294967295.0-beta")
}

# T-K15 (R-IK5 property 1, S1): 37 versions in strict precedence order with the edges 0xFFFE, 0xFFFF, 0x10000, U64 max,
# a numeric and an alphanumeric first identifier, and a saturated part with a pre-release. Each pair is in key order.
expect {
	texts = [
		"0.0.0-0",
		"0.0.0-1",
		"0.0.0-4094",
		"0.0.0-99999",
		"0.0.0--",
		"0.0.0-A",
		"0.0.0-alpha",
		"0.0.0-alpha.1",
		"0.0.0-beta",
		"0.0.0-rc.1",
		"0.0.0",
		"0.0.1-rc",
		"0.0.1",
		"0.0.65534",
		"0.0.65535-alpha",
		"0.0.65535",
		"0.0.65536-alpha",
		"0.0.65536",
		"0.1.0-alpha",
		"0.1.0",
		"0.65534.0",
		"0.65535.0-beta",
		"0.65535.1",
		"1.0.0-alpha",
		"1.0.0",
		"1.2.3-alpha4",
		"1.2.3-beta1",
		"1.2.3",
		"1.2.4",
		"65534.65534.65534-rc",
		"65534.65534.65534",
		"65535.0.0-alpha",
		"65535.0.0",
		"65535.1.0",
		"65536.8.0-b.-",
		"4294967295.0.0-99999.beta",
		"18446744073709551615.0.0",
	]
	ascending(texts) and violations(texts) == []
}

# ---- Semver.from_key ----

# T-K16 (R-IK5 property 2, R-PK2, S2): the key of an exact version gives the version back
expect {
	texts = ["0.0.0", "0.0.1", "1.0.0", "1.2.3", "0.65534.0", "65534.65534.65534", "10.20.30"]
	texts.all(
		|text| {
			v = ver(text)
			k = v.to_key()
			k.exact and Semver.from_key(k.key) == Ok(v)
		},
	)
}

# T-K17 (R-IK5 example, R-PK2): from_key of the hex keys of the design
expect Semver.from_key(0x100020003ffff) == Ok(Semver.new(1, 2, 3))

expect Semver.from_key(0xffff) == Ok(Semver.new(0, 0, 0))

# T-K18 (R-PK2, S2): a key that `to_key` gives with `exact` False for a pre-release or a saturated part gives Err(NotExact)
expect {
	texts = ["1.2.3-beta1", "1.2.3-alpha4", "1.0.0-0", "65535.0.0", "65536.8.0-b.-", "1.65535.0", "1.2.65535", "0.0.65535"]
	texts.all(|text| Semver.from_key(key_of(text)) == Err(NotExact))
}

# T-K18b (R-IK5 property 2, reference fromKey): from_key reads the key only. The key of a version with build metadata is
# the key of its release, so from_key gives the release without the build (`exact` was False, so Talon keeps the text)
expect Semver.from_key(key_of("1.2.3+build.5")) == Ok(Semver.new(1, 2, 3))

# T-K19 (R-PK2, reference fromKey): a key that no version has gives Err(NotExact): the key 0 (R-IK5: "unknown is the
# key 0, no version has the pre-release code 0x0000"), the unused codes 0x0000 and 0x203F to 0xFFFE, and a field of 0xFFFF
expect {
	keys : List(U64)
	keys = [0, 0x100020003fffe, 0x1000200030000, 0x100020000203f, 0xfffefffefffefffe, 0x1ffffffffffff, 0x10002ffffffff, 0xffffffff, 0xffffffffffffffff]
	keys.all(|k| Semver.from_key(k) == Err(NotExact))
}

# T-K20 (R-IK5 property 2, R-PK2): when from_key gives a version, to_key of it gives the same key and `exact` True
expect {
	keys : List(U64)
	keys = [0xffff, 0x1ffff, 0x100020003ffff, 0xfffefffefffeffff, 0x200000000ffff]
	keys.all(
		|k|
			match Semver.from_key(k) {
				Ok(v) => v.to_key() == { key: k, exact: True }
				Err(_) => False
			},
	)
}

# ---- VersionReq.key_bounds ----

# T-K21 (R-IK5 query row, S5): the caret bounds of the reference. lo is the key of the lower bound, hi is the key of the
# upper bound (exclusive in the range, inclusive here, so a saturated key is inside).
expect {
	req("^1.2.3").key_bounds() == { lo: 0x100020003ffff, hi: 0x200000000ffff }
		and req("^0.2.3").key_bounds() == { lo: 0x20003ffff, hi: 0x30000ffff }
			and req("^0.0.3").key_bounds() == { lo: 0x3ffff, hi: 0x4ffff }
}

## All range forms of the README, with the edge values of the key (0xFFFE, 0xFFFF, 0x10000, U64 max), and ranges that match nothing
req_texts : List(Str)
req_texts = [
	"*",
	"x",
	"1.2.3",
	"=1.2.3",
	"=1.2",
	"=1",
	"^1.2.3",
	"^0.2.3",
	"^0.0.3",
	"^0",
	"^0.0",
	"^1.2",
	"^2",
	"1.2",
	"2",
	"2.x",
	"1.2.x",
	">1.2.3",
	">=1.2.3",
	"<2.0.0",
	"<=1.2",
	">1",
	"<1",
	"~1.2.3",
	"~1.2",
	"~1",
	">=1.2, <2",
	">1.0.0, <1.0.4",
	">=1.2.3-alpha",
	"^1.2.3-alpha",
	"<1.2.3-alpha",
	"^65534.0.0",
	"^65535.0.0",
	"^65536.0.0",
	"^0.65535.5",
	"^0.0.65535",
	"^0.0.65536",
	"=65535.1.1",
	"~0.65535.0",
	">=65536.0.0",
	"<65536.0.0",
	"<=65535.65535.65535",
	">65535.65535.65535",
	">=0.0.0, <0.0.0",
	">2, <1",
	"^18446744073709551615.0.0",
	"^0.18446744073709551615.0",
	"^0.0.18446744073709551615",
	">=18446744073709551615.18446744073709551615.18446744073709551615",
	"<=18446744073709551615.0.0",
]

## Release versions: the cross product of edge values for the 3 parts (175 versions)
edge_versions : List(Semver)
edge_versions = {
	majors : List(U64)
	majors = [0, 1, 2, 65534, 65535, 65536, U64.highest]
	minors : List(U64)
	minors = [0, 1, 2, 65535, U64.highest]
	patches : List(U64)
	patches = [0, 3, 4, 65535, U64.highest]
	majors.join_map(|ma| minors.join_map(|mi| patches.map(|pa| Semver.new(ma, mi, pa))))
}

## (requirement, version) pairs where the version matches and its key is outside the bounds
## (a function, so that no `crash` runs at compile time)
outside : List(Str) -> List((Str, Str))
outside = |texts|
	texts.join_map(
		|text| {
			r = req(text)
			b = r.key_bounds()
			edge_versions.keep_if(
				|v| {
					k = v.to_key().key
					r.matches(v) and (k < b.lo or k > b.hi)
				},
			).map(|v| (text, v.to_str()))
		},
	)

## The number of (requirement, version) pairs where the version matches
match_count : List(Str) -> U64
match_count = |texts| texts.map(|text| edge_versions.count_if(|v| req(text).matches(v))).sum()

# T-K22 (R-IK5 query row, S5): each release version that matches a requirement has its key in the bounds.
# All range forms. key_bounds does not crash for a part of U64 max, nor for a range that matches nothing.
# The sample is not empty: many (requirement, version) pairs match, so the check is not true by luck of the setup.
expect outside(req_texts) == [] and match_count(req_texts) > 500

# T-K23 (R-IK5 query row): a version that matches is inside for the saturated and the exact keys alike. `*` takes
# the key 0xFFFF of 0.0.0 and the key U64 max of 65536.0.0, so the bounds of `*` hold both.
expect {
	b = req("*").key_bounds()
	b.lo <= key_of("0.0.0") and b.hi >= key_of("65536.0.0") and b.hi >= key_of("18446744073709551615.18446744073709551615.18446744073709551615")
}
