app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Semver
import pkg.VersionReq

# Caret ranges with the npm and Cargo rule (Q1, Q2, Q3 settled; R-I7, R-SL15):
# a caret allows the updates that do not change the left-most part that is not zero.
# Oracle: [lower, upper), with the missing parts of the lower bound as 0.
#   3 parts M.m.p: M > 0: <(M+1).0.0. M = 0, m > 0: <0.(m+1).0. M = 0, m = 0: <0.0.(p+1).
#   2 parts M.m:   M > 0: <(M+1).0.0. M = 0: <0.(m+1).0.
#   1 part M:      <(M+1).0.0.
# Forms: `^M.m.p`; `^M.m`, `M.m`, `^M.m.x`; `^M`, `M`, `M.x`, `^M.x`.
# Release versions only: a range does not match a pre-release version (Q6 settled, L0 T-VR45).

Input := { range : List(U64), version : List(U64) }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { range: Fuzz.list(Fuzz.u64_in(0, 3), 3), version: Fuzz.list(Fuzz.u64_in(0, 3), 3) }.Fuzz
}

le : (U64, U64, U64), (U64, U64, U64) -> Bool
le = |(a1, a2, a3), (b1, b2, b3)| a1 < b1 or (a1 == b1 and (a2 < b2 or (a2 == b2 and a3 <= b3)))

lt : (U64, U64, U64), (U64, U64, U64) -> Bool
lt = |a, b| le(a, b) and a != b

check : Str, (U64, U64, U64), (U64, U64, U64), (U64, U64, U64) -> {}
check = |text, lower, upper, v| {
	r =
		match VersionReq.parse(text) {
			Ok(x) => x
			Err(_) => crash "range ${text} did not parse"
		}
	want = le(lower, v) and lt(v, upper)
	got = r.matches(Semver.new(v.0, v.1, v.2))
	if want != got {
		crash "${text} on ${v.0.to_str()}.${v.1.to_str()}.${v.2.to_str()}: got ${Str.inspect(got)}, want ${Str.inspect(want)}"
	}
	{}
}

test : Input -> Fuzz.Outcome
test = |input| {
	r = |i| input.range.get(i) ?? 0
	w = |i| input.version.get(i) ?? 0
	(m1, m2, m3) = (r(0), r(1), r(2))
	v = (w(0), w(1), w(2))
	(s1, s2, s3) = (m1.to_str(), m2.to_str(), m3.to_str())

	upper3 = if m1 > 0 (m1 + 1, 0, 0) else if m2 > 0 (0, m2 + 1, 0) else (0, 0, m3 + 1)
	check("^${s1}.${s2}.${s3}", (m1, m2, m3), upper3, v)

	upper2 = if m1 > 0 (m1 + 1, 0, 0) else (0, m2 + 1, 0)
	check("^${s1}.${s2}", (m1, m2, 0), upper2, v)
	check("${s1}.${s2}", (m1, m2, 0), upper2, v)
	check("^${s1}.${s2}.x", (m1, m2, 0), upper2, v)

	upper1 = (m1 + 1, 0, 0)
	check("^${s1}", (m1, 0, 0), upper1, v)
	check("${s1}", (m1, 0, 0), upper1, v)
	check("${s1}.x", (m1, 0, 0), upper1, v)
	check("^${s1}.x", (m1, 0, 0), upper1, v)
	Fuzz.keep
}

target = Fuzz.target_with({
	name: "req-caret",
	generator: Input.generator_for(Default),
	test,
	show: |input| "${Str.inspect(input.range)} ${Str.inspect(input.version)}",
})
