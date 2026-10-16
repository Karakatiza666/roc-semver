# Ported from smores56/roc-semver (package/Parse.roc), see LICENSE.

## Byte scanners for version text. Each scanner gives its value and the bytes after it.
Lex :: [].{

	## A number with no leading zero that fits in U64 (semver 2).
	number : List(U8) -> Try((U64, List(U8)), [Empty, InvalidNumber, CannotStartWithZero])
	number = |bytes| {
		(digits, rest) = take_while(bytes, is_digit)
		if digits.is_empty() {
			Err(Empty)
		} else if has_leading_zero(digits) {
			Err(CannotStartWithZero)
		} else {
			n = to_u64(digits)?
			Ok((n, rest))
		}
	}

	## The pre-release identifiers after the `-` (semver 9). A numeric identifier has no leading zero.
	pre_release : List(U8) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
	pre_release = |bytes| identifiers(bytes, |chars| !has_leading_zero(chars) or !chars.all(is_digit))

	## The build identifiers after the `+` (semver 10). A leading zero is valid.
	build : List(U8) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
	build = |bytes| identifiers(bytes, |_| True)

	## The bytes before the first byte that is not `keep`, and the bytes after them.
	take_while : List(U8), (U8 -> Bool) -> (List(U8), List(U8))
	take_while = |bytes, keep| {
		n = bytes.find_first_index(|b| !keep(b)) ?? bytes.len()
		{ before, others } = bytes.split_at(n)
		(before, others)
	}

	drop_spaces : List(U8) -> List(U8)
	drop_spaces = |bytes| take_while(bytes, |b| b == ' ').1

	is_digit : U8 -> Bool
	is_digit = |b| b >= '0' and b <= '9'

	## The bytes are a suffix of valid text at an ASCII byte, so they are valid UTF-8.
	as_str : List(U8) -> Str
	as_str = |bytes| Str.from_utf8(bytes) ?? ""
}

has_leading_zero : List(U8) -> Bool
has_leading_zero = |digits| digits.len() > 1 and digits.first() == Ok('0')

## Digits to a number. A number above U64 max is an error, not a crash (Q10).
to_u64 : List(U8) -> Try(U64, [InvalidNumber])
to_u64 = |digits| {
	var $n = 0.U64
	for d in digits {
		ten_times = $n.times_try(10) ? |_| InvalidNumber
		$n = ten_times.plus_try((d - '0').to_u64()) ? |_| InvalidNumber
	}
	Ok($n)
}

## [0-9A-Za-z-] (semver 9). The source accepted lower case letters only.
is_identifier_char : U8 -> Bool
is_identifier_char = |b| Lex.is_digit(b) or (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '-'

## Identifiers separated by `.`. When the first identifier is empty but text follows, the error is InvalidIdentifier.
identifiers : List(U8), (List(U8) -> Bool) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
identifiers = |bytes, is_valid| {
	first_error = |e|
		match e {
			EmptySegment if !bytes.is_empty() => InvalidIdentifier
			other => other
		}
	(first, rest) = identifier(bytes, is_valid) ? first_error
	more_identifiers(rest, [first], is_valid)
}

more_identifiers : List(U8), List(Str), (List(U8) -> Bool) -> Try((List(Str), List(U8)), [EmptySegment, InvalidIdentifier])
more_identifiers = |bytes, found, is_valid|
	match bytes {
		['.', .. as rest] => {
			(id, after) = identifier(rest, is_valid)?
			more_identifiers(after, found.append(id), is_valid)
		}
		_ => Ok((found, bytes))
	}

identifier : List(U8), (List(U8) -> Bool) -> Try((Str, List(U8)), [EmptySegment, InvalidIdentifier])
identifier = |bytes, is_valid| {
	(chars, rest) = Lex.take_while(bytes, is_identifier_char)
	if chars.is_empty() {
		Err(EmptySegment)
	} else if is_valid(chars) {
		Ok((Lex.as_str(chars), rest))
	} else {
		Err(InvalidIdentifier)
	}
}
