app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Semver
import pkg.VersionReq

# Slice 100 of the Talon registry plan; the rules are R-IK5 (Talon DESIGN-REGISTRY.md 5.1, the query row "range") and R-PK2.
# Reference: research/semver-key/test.mjs, case S5 (caret bounds are a superset).
# For a requirement of each operator and each number of parts (also a wildcard, and a second comparator), and a
# version with parts from the same small pool with the edges of the key (0xFFFE, 0xFFFF, 0x10000, U64 max):
#   when the requirement matches the version, the key of the version is in `lo` to `hi` (R-IK5).
#   A key in the bounds does not always match (the Worker checks each row with `matches`), so the property is one way only.
# `key_bounds` must not crash for any requirement, also for parts of U64 max and for a range that matches nothing.

## Part values: small numbers so that many versions match, and the edges of the key
part_pool : List(U64)
part_pool = [0, 1, 2, 3, 65534, 65535, 65536, U64.highest]

## Operators of the README. The empty text is no operator.
op_pool : List(Str)
op_pool = ["", "^", "~", "=", ">", ">=", "<", "<="]

Input := { req : List(U8), ver : List(U8) }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { req: Fuzz.list(Fuzz.u8, 12), ver: Fuzz.list(Fuzz.u8, 3) }.Fuzz
}

at : List(U8), U64 -> U64
at = |bytes, i| (bytes.get(i) ?? 0).to_u64()

pick : List(a), U64 -> a
pick = |pool, i| pool.get(i % pool.len()) ?? crash "empty pool"

## One comparator from 5 bytes at `offset`: an operator, then 1 to 3 parts, with a wildcard in place of the last parts for some forms
comparator_at : List(U8), U64 -> Str
comparator_at = |bytes, offset| {
	b = |i| at(bytes, offset + i)
	op = pick(op_pool, b(0))
	parts = [pick(part_pool, b(2)), pick(part_pool, b(3)), pick(part_pool, b(4))].take_first(1 + b(1) % 3).map(U64.to_str)
	wild = if parts.len() < 3 and b(1) % 7 == 3 ".x" else ""
	"${op}${Str.join_with(parts, ".")}${wild}"
}

requirement_text : List(U8) -> Str
requirement_text = |bytes| {
	first = comparator_at(bytes, 1)
	match at(bytes, 0) % 6 {
		0 => "*"
		1 => "${first}, ${comparator_at(bytes, 6)}"
		_ => first
	}
}

version_text : List(U8) -> Str
version_text = |bytes|
	"${pick(part_pool, at(bytes, 0)).to_str()}.${pick(part_pool, at(bytes, 1)).to_str()}.${pick(part_pool, at(bytes, 2)).to_str()}"

test : Input -> Fuzz.Outcome
test = |input| {
	rt = requirement_text(input.req)
	vt = version_text(input.ver)
	r =
		match VersionReq.parse(rt) {
			Ok(x) => x
			Err(_) => crash "requirement ${rt} did not parse"
		}
	v =
		match Semver.parse(vt) {
			Ok(x) => x
			Err(_) => crash "version ${vt} did not parse"
		}
	b = r.key_bounds()
	k = v.to_key().key
	if r.matches(v) and (k < b.lo or k > b.hi) {
		crash "${rt} matches ${vt}, but its key ${k.to_str()} is outside ${b.lo.to_str()} to ${b.hi.to_str()}"
	}
	Fuzz.keep
}

target = Fuzz.target_with({
	name: "req-key-bounds",
	generator: Input.generator_for(Default),
	test,
	show: |input| "${requirement_text(input.req)} ${version_text(input.ver)} ${Str.inspect(input.req)} ${Str.inspect(input.ver)}",
})
