/*
	Weasel lexer / scanner.

	Reads a .weasel source file and produces a flat token stream, distinguishing
	Odin passthrough spans from Weasel element boundaries.

	State machine:
	  - depth == 0  →  Odin passthrough mode: accumulate OdinText until <[a-z_]
	  - depth  > 0  →  Element-content mode:
	                     $(…)  becomes Expr_Open (value=inner) + Expr_Close
	                     {…}   becomes Block_Open (value=inner) + Block_Close
	                     <tag> / </tag> continue nesting
	  - Expr and Block inner content is captured verbatim (parser recurses as needed)
*/
package transpiler

import "core:fmt"

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

// Token_Kind enumerates all lexical token types produced by scan().
Token_Kind :: enum u8 {
	EOF,
	// Verbatim Odin source (passthrough region or element text content)
	Odin_Text,
	// `<tagname` — opening of an element; value = tag name
	Element_Open,
	// `</tagname>` — closing tag; value = tag name
	Element_Close,
	// `name="value"` attribute; value = attr name, extra = string value (no quotes)
	Attr_Static,
	// `name={expr}` attribute; value = attr name, extra = expression (no braces)
	Attr_Dynamic,
	// `$(expr)` in element content; value = raw inner expression (no delimiters)
	Expr_Open,
	// `)` closing a preceding Expr_Open; value empty, pos = position of `)`
	Expr_Close,
	// `{block}` in element content; value = raw inner block (no braces)
	Block_Open,
	// `}` closing a preceding Block_Open; value empty, pos = position of `}`
	Block_Close,
	// `/>` — self-close marker for the preceding Element_Open
	Self_Close,
}

// Position records the source location of a token's first character.
Position :: struct {
	offset: int,
	line:   int,
	col:    int,
}

// Token is a single lexical unit produced from a .weasel source file.
//
// Field meanings by token kind:
//   Odin_Text                 →  value = verbatim source text
//   Element_Open / Close      →  value = tag name
//   Attr_Static               →  value = attr name,  extra = string value (no quotes)
//   Attr_Dynamic              →  value = attr name,  extra = expression   (no braces)
//   Expr_Open                 →  value = inner expression (no $( or ))
//   Expr_Close                →  value empty; pos = position of the closing )
//   Block_Open                →  value = inner block text (no { or })
//   Block_Close               →  value empty; pos = position of the closing }
//   Self_Close / EOF          →  value and extra are empty
Token :: struct {
	kind:  Token_Kind,
	value: string,
	extra: string,
	pos:   Position,
}

// Scan_Error records a lexer error with its source position.
Scan_Error :: struct {
	message: string,
	pos:     Position,
}

// ---------------------------------------------------------------------------
// Internal scanner state
// ---------------------------------------------------------------------------

_Scanner :: struct {
	src:    string,
	offset: int,
	line:   int,
	col:    int,
}

@(private = "file")
_pos :: #force_inline proc(s: ^_Scanner) -> Position {
	return {s.offset, s.line, s.col}
}

// Peek at the current character (returns 0 at EOF).
@(private = "file")
_peek :: #force_inline proc(s: ^_Scanner) -> byte {
	if s.offset < len(s.src) {return s.src[s.offset]}
	return 0
}

// Peek at the character one ahead of the current position (returns 0 at EOF).
@(private = "file")
_peek_next :: #force_inline proc(s: ^_Scanner) -> byte {
	if s.offset + 1 < len(s.src) {return s.src[s.offset + 1]}
	return 0
}

// Consume the current character, advancing line/col tracking.
@(private = "file")
_advance :: proc(s: ^_Scanner) -> byte {
	if s.offset >= len(s.src) {return 0}
	ch := s.src[s.offset]
	s.offset += 1
	if ch == '\n' {
		s.line += 1
		s.col = 1
	} else {
		s.col += 1
	}
	return ch
}

// Returns true when ch is a valid Weasel tag name starting character.
// Only lowercase ASCII letters and '_' are accepted; this is intentional —
// Weasel element tags always start with a lowercase letter or underscore.
@(private = "file")
_is_name_start :: #force_inline proc(ch: byte) -> bool {
	return (ch >= 'a' && ch <= 'z') || ch == '_'
}

// Returns true for characters valid anywhere in a tag name after the first.
// Includes '.' for package-qualified names (e.g. ui.card) and '-' for
// custom-element names (e.g. my-widget).
@(private = "file")
_is_name_cont :: #force_inline proc(ch: byte) -> bool {
	return (ch >= 'a' && ch <= 'z') ||
		(ch >= 'A' && ch <= 'Z') ||
		(ch >= '0' && ch <= '9') ||
		ch == '_' ||
		ch == '-' ||
		ch == '.'
}

// Skip ASCII whitespace.
@(private = "file")
_skip_ws :: proc(s: ^_Scanner) {
	for {
		ch := _peek(s)
		if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
			_advance(s)
		} else {
			break
		}
	}
}

// Scan a tag or attribute name, returning a slice into the source string.
@(private = "file")
_scan_name :: proc(s: ^_Scanner) -> string {
	start := s.offset
	for s.offset < len(s.src) && _is_name_cont(s.src[s.offset]) {
		_advance(s)
	}
	return s.src[start:s.offset]
}

// Scan a double-quoted string literal, returning the content without quotes.
// The scanner must be positioned at the opening '"'.
@(private = "file")
_scan_quoted_string :: proc(s: ^_Scanner, errs: ^[dynamic]Scan_Error) -> string {
	pos := _pos(s)
	_advance(s) // consume opening "
	start := s.offset
	for s.offset < len(s.src) {
		ch := s.src[s.offset]
		if ch == '"' {
			val := s.src[start:s.offset]
			_advance(s) // consume closing "
			return val
		}
		if ch == '\\' {
			_advance(s) // skip the backslash
		}
		_advance(s)
	}
	append(errs, Scan_Error{"unterminated string literal", pos})
	return s.src[start:s.offset]
}

// Scan a brace-enclosed expression `{…}`, returning the raw inner content.
// Handles nested braces, double-quoted strings, raw (backtick) strings,
// rune literals, line comments (//) and block comments (/* */).
// The scanner must be positioned at the opening '{'.
@(private = "file")
_scan_brace_expr :: proc(s: ^_Scanner, errs: ^[dynamic]Scan_Error) -> string {
	pos := _pos(s)
	_advance(s) // consume '{'
	start := s.offset
	depth := 1
	outer: for s.offset < len(s.src) {
		ch := s.src[s.offset]
		switch ch {
		case '{':
			depth += 1
			_advance(s)
		case '}':
			depth -= 1
			if depth == 0 {break outer}
			_advance(s)
		case '"':
			// Double-quoted string: skip until unescaped '"'.
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '"' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '`':
			// Raw string literal: no escape sequences, terminated by '`'.
			_advance(s)
			for s.offset < len(s.src) {
				if _advance(s) == '`' {break}
			}
		case '\'':
			// Rune literal.
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '\'' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '/':
			switch _peek_next(s) {
			case '/':
				// Line comment: skip to end of line.
				for s.offset < len(s.src) && s.src[s.offset] != '\n' {
					_advance(s)
				}
			case '*':
				// Block comment: skip until '*/'.
				_advance(s) // /
				_advance(s) // *
				for s.offset + 1 < len(s.src) {
					if s.src[s.offset] == '*' && s.src[s.offset + 1] == '/' {
						_advance(s) // *
						_advance(s) // /
						break
					}
					_advance(s)
				}
			case:
				_advance(s)
			}
		case:
			_advance(s)
		}
	}
	inner := s.src[start:s.offset]
	if depth != 0 {
		append(errs, Scan_Error{"unterminated brace expression", pos})
	} else {
		_advance(s) // consume closing '}'
	}
	return inner
}

// Scan a brace-delimited code block `{…}` inside an element body.
// Returns the raw inner content and the Position of the closing '}'.
// Handles nested braces, strings, rune literals, and comments identically to
// _scan_brace_expr; the scanner must be positioned at the opening '{'.
@(private = "file")
_scan_brace_block :: proc(
	s: ^_Scanner,
	errs: ^[dynamic]Scan_Error,
) -> (
	inner: string,
	close_pos: Position,
) {
	pos := _pos(s)
	_advance(s) // consume '{'
	start := s.offset
	depth := 1
	outer: for s.offset < len(s.src) {
		ch := s.src[s.offset]
		switch ch {
		case '{':
			depth += 1
			_advance(s)
		case '}':
			depth -= 1
			if depth == 0 {
				close_pos = _pos(s)
				break outer
			}
			_advance(s)
		case '"':
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '"' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '`':
			_advance(s)
			for s.offset < len(s.src) {
				if _advance(s) == '`' {break}
			}
		case '\'':
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '\'' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '/':
			switch _peek_next(s) {
			case '/':
				for s.offset < len(s.src) && s.src[s.offset] != '\n' {
					_advance(s)
				}
			case '*':
				_advance(s) // /
				_advance(s) // *
				for s.offset + 1 < len(s.src) {
					if s.src[s.offset] == '*' && s.src[s.offset + 1] == '/' {
						_advance(s) // *
						_advance(s) // /
						break
					}
					_advance(s)
				}
			case:
				_advance(s)
			}
		case:
			_advance(s)
		}
	}
	inner = s.src[start:s.offset]
	if depth != 0 {
		append(errs, Scan_Error{"unterminated brace block", pos})
	} else {
		_advance(s) // consume closing '}'
	}
	return
}

// Scan a paren-delimited expression `$(…)` inside an element body.
// Called when the scanner is positioned at '(' (the '$' has already been consumed).
// Returns the raw inner content and the Position of the closing ')'.
// Handles nested parentheses, strings, rune literals, and comments.
@(private = "file")
_scan_paren_expr :: proc(
	s: ^_Scanner,
	errs: ^[dynamic]Scan_Error,
) -> (
	inner: string,
	close_pos: Position,
) {
	pos := _pos(s)
	_advance(s) // consume '('
	start := s.offset
	depth := 1
	outer: for s.offset < len(s.src) {
		ch := s.src[s.offset]
		switch ch {
		case '(':
			depth += 1
			_advance(s)
		case ')':
			depth -= 1
			if depth == 0 {
				close_pos = _pos(s)
				break outer
			}
			_advance(s)
		case '"':
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '"' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '`':
			_advance(s)
			for s.offset < len(s.src) {
				if _advance(s) == '`' {break}
			}
		case '\'':
			_advance(s)
			for s.offset < len(s.src) {
				c := _advance(s)
				if c == '\'' {break}
				if c == '\\' && s.offset < len(s.src) {_advance(s)}
			}
		case '/':
			switch _peek_next(s) {
			case '/':
				for s.offset < len(s.src) && s.src[s.offset] != '\n' {
					_advance(s)
				}
			case '*':
				_advance(s) // /
				_advance(s) // *
				for s.offset + 1 < len(s.src) {
					if s.src[s.offset] == '*' && s.src[s.offset + 1] == '/' {
						_advance(s) // *
						_advance(s) // /
						break
					}
					_advance(s)
				}
			case:
				_advance(s)
			}
		case:
			_advance(s)
		}
	}
	inner = s.src[start:s.offset]
	if depth != 0 {
		append(errs, Scan_Error{"unterminated expression", pos})
	} else {
		_advance(s) // consume closing ')'
	}
	return
}

// Append an Odin_Text token for src[start:end] if the span is non-empty.
@(private = "file")
_emit_odin_text :: proc(tokens: ^[dynamic]Token, src: string, start, end: int, pos: Position) {
	if end > start {
		append(tokens, Token{kind = .Odin_Text, value = src[start:end], pos = pos})
	}
}

// Scan an element opening tag beginning with `<`.
// Emits: Element_Open, zero or more Attr_Static / Attr_Dynamic, then Self_Close if `/>`.
// Returns true when the element is self-closing (/>).
@(private = "file")
_scan_element_open :: proc(
	s: ^_Scanner,
	tokens: ^[dynamic]Token,
	errs: ^[dynamic]Scan_Error,
) -> (
	self_closing: bool,
) {
	tag_pos := _pos(s)  // record position of '<'
	_advance(s)          // consume '<'
	tag_name := _scan_name(s)
	append(tokens, Token{kind = .Element_Open, value = tag_name, pos = tag_pos})

	// Scan attributes.
	for {
		_skip_ws(s)
		ch := _peek(s)

		switch {
		case ch == '/' && _peek_next(s) == '>':
			sc_pos := _pos(s)
			_advance(s) // /
			_advance(s) // >
			append(tokens, Token{kind = .Self_Close, pos = sc_pos})
			return true

		case ch == '>':
			_advance(s) // >
			return false

		case ch == 0:
			append(errs, Scan_Error{"unexpected EOF inside element opening tag", _pos(s)})
			return false

		case _is_name_start(ch):
			// Attribute name: [a-zA-Z0-9_\-:]+
			attr_pos := _pos(s)
			attr_start := s.offset
			for s.offset < len(s.src) {
				c := s.src[s.offset]
				if (c >= 'a' && c <= 'z') ||
				   (c >= 'A' && c <= 'Z') ||
				   (c >= '0' && c <= '9') ||
				   c == '-' ||
				   c == '_' ||
				   c == ':' {
					_advance(s)
				} else {
					break
				}
			}
			attr_name := s.src[attr_start:s.offset]
			_skip_ws(s)

			if _peek(s) != '=' {
				// Boolean attribute (value-less, e.g. `disabled`).
				append(
					tokens,
					Token{kind = .Attr_Static, value = attr_name, extra = "", pos = attr_pos},
				)
				continue
			}
			_advance(s) // consume '='
			_skip_ws(s)

			switch _peek(s) {
			case '"':
				val := _scan_quoted_string(s, errs)
				append(
					tokens,
					Token{kind = .Attr_Static, value = attr_name, extra = val, pos = attr_pos},
				)
			case '{':
				expr := _scan_brace_expr(s, errs)
				append(
					tokens,
					Token{kind = .Attr_Dynamic, value = attr_name, extra = expr, pos = attr_pos},
				)
			case '$':
				if _peek_next(s) == '(' {
					_advance(s) // consume '$'
					expr, _ := _scan_paren_expr(s, errs)
					append(
						tokens,
						Token{kind = .Attr_Dynamic, value = attr_name, extra = expr, pos = attr_pos},
					)
				} else {
					append(
						errs,
						Scan_Error{fmt.aprintf("expected '$(' in attribute '%s'", attr_name), _pos(s)},
					)
					for s.offset < len(s.src) {
						c := s.src[s.offset]
						if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '>' {break}
						_advance(s)
					}
				}
			case:
				append(
					errs,
					Scan_Error {
						fmt.aprintf(
							"expected '\"' or '{' after '=' in attribute '%s', got '%c'",
							attr_name,
							_peek(s),
						),
						_pos(s),
					},
				)
				// Error recovery: skip to next whitespace or '>'.
				for s.offset < len(s.src) {
					c := s.src[s.offset]
					if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '>' {break}
					_advance(s)
				}
			}

		case:
			append(
				errs,
				Scan_Error{fmt.aprintf("unexpected character '%c' in attribute list", ch), _pos(s)},
			)
			_advance(s)
		}
	}
}

// Scan a closing tag `</tagname>`.
// Emits: Element_Close with the tag name as value.
@(private = "file")
_scan_element_close :: proc(s: ^_Scanner, tokens: ^[dynamic]Token, errs: ^[dynamic]Scan_Error) {
	pos := _pos(s)
	_advance(s) // <
	_advance(s) // /
	tag_name := _scan_name(s)
	_skip_ws(s)
	if _peek(s) == '>' {
		_advance(s)
	} else {
		append(errs, Scan_Error{"expected '>' after closing tag name", _pos(s)})
	}
	append(tokens, Token{kind = .Element_Close, value = tag_name, pos = pos})
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// scan tokenizes src and returns a flat token stream plus any scan errors.
//
// Caller owns the returned slices and is responsible for deletion.
//
// Token stream conventions:
//
//   • Odin_Text    — zero or more verbatim source characters (never empty)
//   • Element_Open — followed by Attr* tokens; ended by Self_Close or first non-Attr token
//   • Attr_Static  — value = name,  extra = unquoted string value
//   • Attr_Dynamic — value = name,  extra = raw expression (without surrounding braces)
//   • Self_Close   — closes the immediately preceding Element_Open
//   • Expr_Open    — value = inner expression of $(…) (no delimiters); always followed by Expr_Close
//   • Expr_Close   — pos = position of the closing ')'; value empty
//   • Block_Open   — value = inner text of {…} block (no braces); always followed by Block_Close
//   • Block_Close  — pos = position of the closing '}'; value empty
//   • Element_Close — value = tag name
//   • EOF          — always the final token
//
// The lexer does NOT recurse into Expr or Block content; nested elements inside
// block bodies are left verbatim for the parser to handle via recursive descent.
scan :: proc(src: string, allocator := context.allocator) -> ([dynamic]Token, [dynamic]Scan_Error) {
	s := _Scanner{src = src, line = 1, col = 1}
	tokens := make([dynamic]Token, allocator)
	errs := make([dynamic]Scan_Error, allocator)

	// depth tracks element nesting: 0 = Odin passthrough, >0 = element content.
	depth := 0
	// mark / mark_pos delimit the current OdinText accumulation region.
	mark := 0
	mark_pos := Position{0, 1, 1}

	for s.offset < len(s.src) {
		ch := s.src[s.offset]

		// ── Element open: `<[a-z_]` ─────────────────────────────────────────
		if ch == '<' && _is_name_start(_peek_next(&s)) {
			_emit_odin_text(&tokens, s.src, mark, s.offset, mark_pos)
			self_closing := _scan_element_open(&s, &tokens, &errs)
			if !self_closing {
				depth += 1
			}
			mark = s.offset
			mark_pos = _pos(&s)
			continue
		}

		// ── Element close: `</` ──────────────────────────────────────────────
		if ch == '<' && _peek_next(&s) == '/' {
			_emit_odin_text(&tokens, s.src, mark, s.offset, mark_pos)
			_scan_element_close(&s, &tokens, &errs)
			depth -= 1
			if depth < 0 {depth = 0}
			mark = s.offset
			mark_pos = _pos(&s)
			continue
		}

		// ── Expression: `$(expr)` inside element content ─────────────────────
		if ch == '$' && _peek_next(&s) == '(' && depth > 0 {
			_emit_odin_text(&tokens, s.src, mark, s.offset, mark_pos)
			expr_pos := _pos(&s)
			_advance(&s) // consume '$'
			inner, close_pos := _scan_paren_expr(&s, &errs)
			append(&tokens, Token{kind = .Expr_Open, value = inner, pos = expr_pos})
			append(&tokens, Token{kind = .Expr_Close, pos = close_pos})
			mark = s.offset
			mark_pos = _pos(&s)
			continue
		}

		// ── Code block: `{block}` inside element content ──────────────────────
		if ch == '{' && depth > 0 {
			_emit_odin_text(&tokens, s.src, mark, s.offset, mark_pos)
			block_pos := _pos(&s)
			inner, close_pos := _scan_brace_block(&s, &errs)
			append(&tokens, Token{kind = .Block_Open, value = inner, pos = block_pos})
			append(&tokens, Token{kind = .Block_Close, pos = close_pos})
			mark = s.offset
			mark_pos = _pos(&s)
			continue
		}

		_advance(&s)
	}

	// Flush any trailing Odin passthrough text.
	_emit_odin_text(&tokens, s.src, mark, s.offset, mark_pos)
	append(&tokens, Token{kind = .EOF, pos = _pos(&s)})
	return tokens, errs
}
