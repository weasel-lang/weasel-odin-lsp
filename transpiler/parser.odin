/*
	Weasel recursive descent parser.

	Consumes the token stream produced by scan() and returns a minimal AST.
	Weasel elements become typed nodes; Odin spans are preserved verbatim as
	Odin_Span leaf nodes.

	Node kinds:
	  Odin_Span     — verbatim Odin passthrough text
	  Expr_Node     — {expr} interpolation (HTML-escaped output)
	  Element_Node  — raw HTML element or component proc call
	  Odin_Block    — control-flow block (for/if/when/switch) containing elements
	  Template_Proc — top-level Weasel template function declaration
*/
package transpiler

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// AST node types
// ---------------------------------------------------------------------------

// Attr is a single element attribute.
//   Boolean   (e.g. `disabled`)      — name set, value and expr empty
//   Static    (e.g. `class="card"`)  — name and value set, is_dynamic false
//   Dynamic   (e.g. `class={cls}`)   — name and expr set,  is_dynamic true
Attr :: struct {
	name:       string,
	value:      string,
	expr:       string,
	is_dynamic: bool,
	pos:        Position,
}

// Odin_Span carries verbatim Odin source emitted unchanged.
Odin_Span :: struct {
	text: string,
	pos:  Position,
}

// Expr_Node is an inline `{expr}` interpolation. The transpiler emits
// weasel.write_escaped_string for this node.
Expr_Node :: struct {
	expr: string,
	pos:  Position,
}

// Element_Node is a Weasel element tag — either a raw HTML element or a
// component template call. kind is set by resolve_tag.
Element_Node :: struct {
	tag:      string,
	kind:     Tag_Kind,
	attrs:    [dynamic]Attr,
	children: [dynamic]Node,
	pos:      Position,
}

// Odin_Block is a {…} code block whose body may contain nested Weasel elements.
//   head — Odin text before the first inner '{', e.g. "for x in items "
//   tail — "}" if an inner closing brace was found, or empty
Odin_Block :: struct {
	head:     string,
	children: [dynamic]Node,
	tail:     string,
	pos:      Position,
}

// Template_Proc is a top-level Weasel template function declaration.
// has_slot is true when the body (recursively) contains a <slot /> element.
//
// Position fields:
//   pos        — start of the enclosing Odin_Text token (unchanged legacy field)
//   name_pos   — start of the template name identifier in the .weasel source
//   params_pos — start of the parameter list (byte after the opening '(')
Template_Proc :: struct {
	name:       string,
	params:     string, // verbatim parameter list, without surrounding parens
	body:       [dynamic]Node,
	has_slot:   bool,
	pos:        Position,
	name_pos:   Position,
	params_pos: Position,
}

Node :: union {
	Odin_Span,
	Expr_Node,
	Element_Node,
	Odin_Block,
	Template_Proc,
}

Parse_Error :: struct {
	message: string,
	pos:     Position,
}

// ---------------------------------------------------------------------------
// Internal parser state
// ---------------------------------------------------------------------------

_Parser :: struct {
	tokens:      []Token,
	pos:         int,
	errs:        [dynamic]Parse_Error,
	// pending holds the remainder of an Odin_Text token that was split
	// at a template boundary. Checked before reading from tokens.
	pending:     string,
	pending_pos: Position,
	has_pending: bool,
}

@(private = "file")
_pcur :: #force_inline proc(p: ^_Parser) -> Token {
	if p.has_pending {
		return Token{kind = .Odin_Text, value = p.pending, pos = p.pending_pos}
	}
	if p.pos < len(p.tokens) {return p.tokens[p.pos]}
	return Token{kind = .EOF}
}

@(private = "file")
_padvance :: proc(p: ^_Parser) -> Token {
	if p.has_pending {
		t := Token{kind = .Odin_Text, value = p.pending, pos = p.pending_pos}
		p.has_pending = false
		return t
	}
	t := _pcur(p)
	if p.pos < len(p.tokens) {p.pos += 1}
	return t
}

@(private = "file")
_perror :: proc(p: ^_Parser, msg: string, pos: Position) {
	append(&p.errs, Parse_Error{msg, pos})
}

// _ppush_odin stores a remainder string to be returned as the next Odin_Text token.
@(private = "file")
_ppush_odin :: proc(p: ^_Parser, text: string, pos: Position) {
	if len(text) == 0 {return}
	p.pending = text
	p.pending_pos = pos
	p.has_pending = true
}

// ---------------------------------------------------------------------------
// Brace scanner
// ---------------------------------------------------------------------------

// _brace_scan counts net brace depth in text starting at initial_depth.
// Respects double-quoted strings, raw (backtick) strings, rune literals,
// and // / /* */ comments.
//
// If depth reaches 0, stores the byte offset of the triggering '}' in
// zero_at and returns 0. Otherwise zero_at is set to -1 and the final
// depth is returned.
@(private = "file")
_brace_scan :: proc(text: string, initial_depth: int, zero_at: ^int) -> int {
	depth := initial_depth
	i := 0
	for i < len(text) {
		ch := text[i]
		switch ch {
		case '{':
			depth += 1
			i += 1
		case '}':
			depth -= 1
			if depth == 0 {
				zero_at^ = i
				return 0
			}
			i += 1
		case '"':
			i += 1
			for i < len(text) {
				c := text[i]
				i += 1
				if c == '"' {break}
				if c == '\\' && i < len(text) {i += 1}
			}
		case '`':
			i += 1
			for i < len(text) {
				if text[i] == '`' {i += 1; break}
				i += 1
			}
		case '\'':
			i += 1
			for i < len(text) {
				c := text[i]
				i += 1
				if c == '\'' {break}
				if c == '\\' && i < len(text) {i += 1}
			}
		case '/':
			if i + 1 < len(text) {
				switch text[i + 1] {
				case '/':
					for i < len(text) && text[i] != '\n' {i += 1}
				case '*':
					i += 2
					for i + 1 < len(text) {
						if text[i] == '*' && text[i + 1] == '/' {
							i += 2
							break
						}
						i += 1
					}
				case:
					i += 1
				}
			} else {
				i += 1
			}
		case:
			i += 1
		}
	}
	zero_at^ = -1
	return depth
}

// ---------------------------------------------------------------------------
// Template declaration detection
// ---------------------------------------------------------------------------

_Template_Decl :: struct {
	name:       string,
	params:     string,
	prefix:     string, // Odin text before the declaration
	suffix:     string, // Odin text after the opening '{'
	// Byte offsets into the containing Odin_Text token's value, used by the
	// caller to compute precise .weasel positions via advance_position.
	name_off:   int,
	params_off: int,
	suffix_off: int, // byte offset of suffix within the Odin_Text token value
}

// _find_template_decl searches text for "name :: template(params) {" and
// returns its components. Handles nested parentheses in params.
@(private = "file")
_find_template_decl :: proc(text: string) -> (decl: _Template_Decl, found: bool) {
	marker := ":: template("
	idx := strings.index(text, marker)
	if idx < 0 {return {}, false}

	// Scan back from "::" to find the identifier name.
	name_end := idx
	for name_end > 0 && (text[name_end - 1] == ' ' || text[name_end - 1] == '\t') {
		name_end -= 1
	}
	name_start := name_end
	for name_start > 0 {
		c := text[name_start - 1]
		if (c >= 'a' && c <= 'z') ||
		   (c >= 'A' && c <= 'Z') ||
		   (c >= '0' && c <= '9') ||
		   c == '_' {
			name_start -= 1
		} else {
			break
		}
	}
	if name_start >= name_end {return {}, false}

	// Extract params: scan from after '(' to matching ')'.
	params_start := idx + len(marker)
	paren_depth := 1
	j := params_start
	for j < len(text) && paren_depth > 0 {
		switch text[j] {
		case '(':
			paren_depth += 1
		case ')':
			paren_depth -= 1
		}
		if paren_depth > 0 {j += 1}
	}
	if paren_depth != 0 || j >= len(text) {return {}, false}
	params := text[params_start:j]
	j += 1 // consume ')'

	// Skip whitespace, expect '{'.
	for j < len(text) && (text[j] == ' ' || text[j] == '\t' || text[j] == '\n' || text[j] == '\r') {
		j += 1
	}
	if j >= len(text) || text[j] != '{' {return {}, false}
	j += 1 // consume '{'

	return _Template_Decl{
		name       = text[name_start:name_end],
		params     = params,
		prefix     = text[:name_start],
		suffix     = text[j:],
		name_off   = name_start,
		params_off = params_start,
		suffix_off = j,
	}, true
}

// ---------------------------------------------------------------------------
// Control-flow detection
// ---------------------------------------------------------------------------

// _find_first_brace returns the offset of the first '{' not inside a string
// literal or comment. Returns -1 if not found.
@(private = "file")
_find_first_brace :: proc(text: string) -> int {
	i := 0
	for i < len(text) {
		ch := text[i]
		switch ch {
		case '{':
			return i
		case '"':
			i += 1
			for i < len(text) {
				c := text[i]
				i += 1
				if c == '"' {break}
				if c == '\\' && i < len(text) {i += 1}
			}
		case '`':
			i += 1
			for i < len(text) {
				if text[i] == '`' {i += 1; break}
				i += 1
			}
		case '\'':
			i += 1
			for i < len(text) {
				c := text[i]
				i += 1
				if c == '\'' {break}
				if c == '\\' && i < len(text) {i += 1}
			}
		case '/':
			if i + 1 < len(text) {
				switch text[i + 1] {
				case '/':
					for i < len(text) && text[i] != '\n' {i += 1}
				case '*':
					i += 2
					for i + 1 < len(text) {
						if text[i] == '*' && text[i + 1] == '/' {i += 2; break}
						i += 1
					}
				case:
					i += 1
				}
			} else {
				i += 1
			}
		case:
			i += 1
		}
	}
	return -1
}

// ---------------------------------------------------------------------------
// Slot detection
// ---------------------------------------------------------------------------

@(private = "file")
_has_slot :: proc(nodes: [dynamic]Node) -> bool {
	for node in nodes {
		switch n in node {
		case Element_Node:
			if n.tag == "slot" {return true}
			if _has_slot(n.children) {return true}
		case Odin_Block:
			if _has_slot(n.children) {return true}
		case Template_Proc:
			if _has_slot(n.body) {return true}
		case Odin_Span, Expr_Node:
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// parse converts a token stream (produced by scan) into a top-level AST.
// Caller owns all returned dynamic arrays and is responsible for deletion.
parse :: proc(tokens: []Token, allocator := context.allocator) -> ([dynamic]Node, [dynamic]Parse_Error) {
	p := _Parser{
		tokens = tokens,
		errs   = make([dynamic]Parse_Error, allocator),
	}
	nodes := _parse_file(&p, allocator)
	return nodes, p.errs
}

// ---------------------------------------------------------------------------
// File-level parsing
// ---------------------------------------------------------------------------

@(private = "file")
_parse_file :: proc(p: ^_Parser, allocator := context.allocator) -> [dynamic]Node {
	nodes := make([dynamic]Node, allocator)
	for {
		tok := _pcur(p)
		#partial switch tok.kind {
		case .EOF:
			return nodes

		case .Odin_Text:
			_padvance(p)
			decl, found := _find_template_decl(tok.value)
			if found {
				if len(decl.prefix) > 0 {
					append(&nodes, Odin_Span{text = decl.prefix, pos = tok.pos})
				}
				suffix_pos := advance_position(tok.pos, tok.value[:decl.suffix_off])
				tp := _parse_template(p, decl, tok.pos, suffix_pos, allocator)
				tp.name_pos   = advance_position(tok.pos, tok.value[:decl.name_off])
				tp.params_pos = advance_position(tok.pos, tok.value[:decl.params_off])
				append(&nodes, tp)
			} else {
				append(&nodes, Odin_Span{text = tok.value, pos = tok.pos})
			}

		case .Element_Open:
			elem := _parse_element(p, allocator)
			append(&nodes, elem)

		case .Element_Close:
			_perror(p, fmt.aprintf("unexpected closing tag </%s> at top level", tok.value), tok.pos)
			_padvance(p)

		case:
			_perror(p, fmt.aprintf("unexpected token %v at top level", tok.kind), tok.pos)
			_padvance(p)
		}
	}
}

// ---------------------------------------------------------------------------
// Template body parsing
// ---------------------------------------------------------------------------

@(private = "file")
_parse_template :: proc(
	p: ^_Parser,
	decl: _Template_Decl,
	pos: Position,
	suffix_pos: Position,
	allocator := context.allocator,
) -> Template_Proc {
	tp := Template_Proc{
		name   = decl.name,
		params = decl.params,
		body   = make([dynamic]Node, allocator),
		pos    = pos,
	}

	brace_depth := 1 // we consumed the opening '{'

	// Process suffix (text after '{' in the header Odin_Text token).
	if len(decl.suffix) > 0 {
		zero_at := -1
		final := _brace_scan(decl.suffix, brace_depth, &zero_at)
		if zero_at >= 0 {
			// Entire template body fits in the suffix (no element tokens).
			if zero_at > 0 {
				append(&tp.body, Odin_Span{text = decl.suffix[:zero_at], pos = suffix_pos})
			}
			rest_pos := advance_position(suffix_pos, decl.suffix[:zero_at + 1])
			_ppush_odin(p, decl.suffix[zero_at + 1:], rest_pos)
			tp.has_slot = _has_slot(tp.body)
			return tp
		}
		brace_depth = final
		if len(decl.suffix) > 0 {
			append(&tp.body, Odin_Span{text = decl.suffix, pos = suffix_pos})
		}
	}

	// Continue consuming tokens until the template's closing '}'.
	for {
		tok := _pcur(p)
		#partial switch tok.kind {
		case .EOF:
			_perror(p, fmt.aprintf("unterminated template proc '%s'", decl.name), pos)
			tp.has_slot = _has_slot(tp.body)
			return tp

		case .Odin_Text:
			_padvance(p)
			zero_at := -1
			final := _brace_scan(tok.value, brace_depth, &zero_at)
			if zero_at >= 0 {
				if zero_at > 0 {
					append(&tp.body, Odin_Span{text = tok.value[:zero_at], pos = tok.pos})
				}
				rest_pos := advance_position(tok.pos, tok.value[:zero_at + 1])
				_ppush_odin(p, tok.value[zero_at + 1:], rest_pos)
				tp.has_slot = _has_slot(tp.body)
				return tp
			}
			brace_depth = final
			append(&tp.body, Odin_Span{text = tok.value, pos = tok.pos})

		case .Element_Open:
			elem := _parse_element(p, allocator)
			append(&tp.body, elem)

		case .Expr_Open:
			_padvance(p)
			if _pcur(p).kind == .Expr_Close {_padvance(p)}
			append(&tp.body, Expr_Node{expr = tok.value, pos = tok.pos})

		case .Block_Open:
			_padvance(p)
			if _pcur(p).kind == .Block_Close {_padvance(p)}
			node := _parse_block_content(tok, allocator)
			append(&tp.body, node)

		case .Element_Close:
			_perror(
				p,
				fmt.aprintf("unexpected closing tag </%s> in template body", tok.value),
				tok.pos,
			)
			_padvance(p)

		case:
			_perror(p, fmt.aprintf("unexpected token %v in template body", tok.kind), tok.pos)
			_padvance(p)
		}
	}
}

// ---------------------------------------------------------------------------
// Element parsing
// ---------------------------------------------------------------------------

@(private = "file")
_parse_element :: proc(p: ^_Parser, allocator := context.allocator) -> Element_Node {
	open_tok := _padvance(p) // consume Element_Open
	elem := Element_Node{
		tag      = open_tok.value,
		kind     = resolve_tag(open_tok.value),
		attrs    = make([dynamic]Attr, allocator),
		children = make([dynamic]Node, allocator),
		pos      = open_tok.pos,
	}

	// Collect attributes until Self_Close or a non-attribute token.
	attr_loop: for {
		t := _pcur(p)
		#partial switch t.kind {
		case .Attr_Static:
			_padvance(p)
			append(&elem.attrs, Attr{name = t.value, value = t.extra, pos = t.pos})
		case .Attr_Dynamic:
			_padvance(p)
			append(&elem.attrs, Attr{name = t.value, expr = t.extra, is_dynamic = true, pos = t.pos})
		case .Self_Close:
			_padvance(p)
			return elem
		case:
			break attr_loop
		}
	}

	// Parse children until the matching close tag.
	_parse_children(p, open_tok.value, &elem.children, allocator)
	return elem
}

// _parse_children appends child nodes into out until it finds Element_Close
// matching close_tag, then consumes that token.
@(private = "file")
_parse_children :: proc(
	p: ^_Parser,
	close_tag: string,
	out: ^[dynamic]Node,
	allocator := context.allocator,
) {
	for {
		tok := _pcur(p)
		#partial switch tok.kind {
		case .EOF:
			_perror(p, fmt.aprintf("unexpected EOF: expected </%s>", close_tag), tok.pos)
			return

		case .Element_Close:
			if tok.value == close_tag {
				_padvance(p)
				return
			}
			_perror(
				p,
				fmt.aprintf("mismatched tag: expected </%s>, got </%s>", close_tag, tok.value),
				tok.pos,
			)
			_padvance(p)

		case .Odin_Text:
			_padvance(p)
			if len(tok.value) > 0 {
				append(out, Odin_Span{text = tok.value, pos = tok.pos})
			}

		case .Element_Open:
			elem := _parse_element(p, allocator)
			append(out, elem)

		case .Expr_Open:
			_padvance(p)
			if _pcur(p).kind == .Expr_Close {_padvance(p)}
			append(out, Expr_Node{expr = tok.value, pos = tok.pos})

		case .Block_Open:
			_padvance(p)
			if _pcur(p).kind == .Block_Close {_padvance(p)}
			node := _parse_block_content(tok, allocator)
			append(out, node)

		case:
			_perror(p, fmt.aprintf("unexpected token %v in element children", tok.kind), tok.pos)
			_padvance(p)
		}
	}
}

// ---------------------------------------------------------------------------
// Block content parsing
// ---------------------------------------------------------------------------

// _parse_block_content parses a Block_Open token's inner text into an Odin_Block.
// The content is always treated as a code block (never an expression) — the $()
// / {} distinction is now made at the lexer level.
@(private = "file")
_parse_block_content :: proc(tok: Token, allocator := context.allocator) -> Node {
	expr := tok.value

	// Split at the first unquoted '{' to separate head from inner body.
	brace_pos := _find_first_brace(expr)
	if brace_pos < 0 {
		// No inner brace — block contains only a head expression (e.g. a simple statement).
		return Odin_Block{head = expr, children = make([dynamic]Node, allocator), tail = "", pos = tok.pos}
	}

	head := expr[:brace_pos]
	rest := expr[brace_pos + 1:]

	zero_at := -1
	_brace_scan(rest, 1, &zero_at)

	body_text, tail: string
	if zero_at >= 0 {
		body_text = rest[:zero_at]
		tail = "}"
	} else {
		body_text = rest
		tail = ""
	}

	// Re-scan the body text to find nested elements, then parse it.
	body_tokens, _ := scan(body_text, allocator)
	defer delete(body_tokens)

	body_p := _Parser{
		tokens = body_tokens[:],
		errs   = make([dynamic]Parse_Error, allocator),
	}
	defer delete(body_p.errs)

	children := make([dynamic]Node, allocator)
	_parse_until_eof(&body_p, &children, allocator)

	return Odin_Block{
		head     = head,
		children = children,
		tail     = tail,
		pos      = tok.pos,
	}
}

// _parse_until_eof parses nodes into out until EOF (used for Odin_Block bodies).
@(private = "file")
_parse_until_eof :: proc(p: ^_Parser, out: ^[dynamic]Node, allocator := context.allocator) {
	for {
		tok := _pcur(p)
		#partial switch tok.kind {
		case .EOF:
			return

		case .Odin_Text:
			_padvance(p)
			if len(tok.value) > 0 {
				append(out, Odin_Span{text = tok.value, pos = tok.pos})
			}

		case .Element_Open:
			elem := _parse_element(p, allocator)
			append(out, elem)

		case .Expr_Open:
			_padvance(p)
			if _pcur(p).kind == .Expr_Close {_padvance(p)}
			append(out, Expr_Node{expr = tok.value, pos = tok.pos})

		case .Block_Open:
			_padvance(p)
			if _pcur(p).kind == .Block_Close {_padvance(p)}
			node := _parse_block_content(tok, allocator)
			append(out, node)

		case .Element_Close:
			_perror(p, fmt.aprintf("unexpected closing tag </%s>", tok.value), tok.pos)
			_padvance(p)

		case:
			_perror(p, fmt.aprintf("unexpected token %v", tok.kind), tok.pos)
			_padvance(p)
		}
	}
}
