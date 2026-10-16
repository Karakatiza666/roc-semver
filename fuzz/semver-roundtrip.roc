app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Semver

# TESTING.md 4: parse(to_str(v)) == v. Semver 2, 9, 10: the valid text forms.
# The target makes a valid version text from typed parts. parse must accept it,
# to_str must give the same text back, and parse of that text must give the same value.

## The characters of an identifier (semver 9, 10): [0-9A-Za-z-]
alphabet : List(U8)
alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-".to_utf8()

Input := { major : U64, minor : U64, patch : U64, pre : List(List(U8)), build : List(List(U8)) }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		major: Fuzz.u64,
		minor: Fuzz.u64,
		patch: Fuzz.u64,
		pre: Fuzz.list(Fuzz.list(Fuzz.u8_in(0, 62), 8), 4),
		build: Fuzz.list(Fuzz.list(Fuzz.u8_in(0, 62), 8), 4),
	}.Fuzz
}

## An identifier that is not empty (semver 9, 10)
ident : List(U8) -> Str
ident = |codes| {
	chars = codes.map(|c| alphabet.get(c.to_u64()) ?? '-')
	if chars.is_empty() "0" else Str.from_utf8(chars) ?? "0"
}

## A numeric pre-release identifier has no leading zero (semver 9): "007" becomes "1007"
pre_ident : List(U8) -> Str
pre_ident = |codes| {
	s = ident(codes)
	bytes = s.to_utf8()
	all_digits = bytes.all(|b| b >= '0' and b <= '9')
	if all_digits and bytes.len() > 1 and bytes.first() == Ok('0') "1${s}" else s
}

text_of : Input -> Str
text_of = |input| {
	pre = input.pre.map(pre_ident)
	build = input.build.map(ident)
	pre_part = if pre.is_empty() "" else "-${Str.join_with(pre, ".")}"
	build_part = if build.is_empty() "" else "+${Str.join_with(build, ".")}"
	"${input.major.to_str()}.${input.minor.to_str()}.${input.patch.to_str()}${pre_part}${build_part}"
}

test : Input -> Fuzz.Outcome
test = |input| {
	text = text_of(input)
	match Semver.parse(text) {
		Ok(v) => {
			parts_ok = v.major() == input.major and v.minor() == input.minor and v.patch() == input.patch
			if parts_ok and v.to_str() == text and Semver.parse(v.to_str()) == Ok(v) {
				Fuzz.keep
			} else {
				crash "round trip failed for ${text}"
			}
		}
		Err(_) => crash "valid text ${text} did not parse"
	}
}

target = Fuzz.target_with({
	name: "semver-roundtrip",
	generator: Input.generator_for(Default),
	test,
	show: |input| text_of(input),
})
