/*
	Weasel transpiler.

	Walks the AST produced by parse() and emits valid Odin source code.
	Template_Proc nodes are rewritten to standard Odin proc declarations.
	Raw HTML elements become __weasel_write_raw_string calls; inline
	expressions become __weasel_write_escaped_string calls.

	Emission rules:
	  Template_Proc  →  name :: proc(w: io.Writer[, params][, children]) -> io.Error { body }
	  Odin_Span      →  verbatim (Odin context) OR raw-string write call (HTML context)
	  Expr_Node      →  __weasel_write_escaped_string(w, expr) or_return
	  Element_Node   →  raw: open/close write calls  |  slot: children(w) or_return
	  Odin_Block     →  head { children }

	Context flag (in_html):
	  false  — inside a template body or top-level: Odin_Span is verbatim Odin source
	  true   — inside element children or Odin_Block children: Odin_Span is HTML text
	           content and must be emitted as a __weasel_write_raw_string call
*/
package transpiler

import "core:strings"

// Transpile_Error records a single problem encountered while emitting code.
Transpile_Error :: struct {
	message: string,
	pos:     Position,
}

// transpile converts a parsed AST into Odin source code. Caller owns the
// returned string (free with delete(transmute([]u8)source)) and error slice.
transpile :: proc(
	nodes: []Node,
	allocator := context.allocator,
) -> (source: string, errs: [dynamic]Transpile_Error) {
	errs = make([dynamic]Transpile_Error, allocator)
	sb := strings.builder_make(allocator)
	for node in nodes {
		_emit_node(&sb, node, &errs, false)
	}
	source = strings.to_string(sb)
	return
}

// ---------------------------------------------------------------------------
// Void element table
// ---------------------------------------------------------------------------

// _is_void_element returns true for HTML5 void elements (those that cannot
// have children and are always emitted as a self-closing string, e.g. <br/>).
@(private = "file")
_is_void_element :: proc(tag: string) -> bool {
	switch tag {
	case "area", "base", "br", "col", "embed", "hr", "img", "input",
	     "link", "meta", "param", "source", "track", "wbr":
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// String literal content helper
// ---------------------------------------------------------------------------

// _write_string_literal_content writes s into sb with the minimal escaping
// needed for it to be valid inside an Odin double-quoted string literal.
@(private = "file")
_write_string_literal_content :: proc(sb: ^strings.Builder, s: string) {
	for i := 0; i < len(s); i += 1 {
		switch s[i] {
		case '\\':
			strings.write_string(sb, `\\`)
		case '"':
			strings.write_string(sb, `\"`)
		case '\n':
			strings.write_string(sb, `\n`)
		case '\r':
			strings.write_string(sb, `\r`)
		case '\t':
			strings.write_string(sb, `\t`)
		case:
			strings.write_byte(sb, s[i])
		}
	}
}

// ---------------------------------------------------------------------------
// Node emitters
// ---------------------------------------------------------------------------

// _emit_node dispatches on node type. in_html controls how Odin_Span nodes
// are emitted: verbatim when false, as a raw-string write call when true.
@(private = "file")
_emit_node :: proc(
	sb: ^strings.Builder,
	node: Node,
	errs: ^[dynamic]Transpile_Error,
	in_html: bool,
) {
	switch n in node {
	case Odin_Span:
		if in_html {
			// Text content inside an element: emit as a raw-string write call.
			strings.write_string(sb, `__weasel_write_raw_string(w, "`)
			_write_string_literal_content(sb, n.text)
			strings.write_string(sb, `") or_return`)
			strings.write_byte(sb, '\n')
		} else {
			strings.write_string(sb, n.text)
		}
	case Expr_Node:
		strings.write_string(sb, "__weasel_write_escaped_string(w, ")
		strings.write_string(sb, n.expr)
		strings.write_string(sb, ") or_return\n")
	case Element_Node:
		_emit_element(sb, n, errs)
	case Odin_Block:
		_emit_odin_block(sb, n, errs)
	case Template_Proc:
		_emit_template_proc(sb, n, errs)
	}
}

@(private = "file")
_emit_template_proc :: proc(
	sb: ^strings.Builder,
	n: Template_Proc,
	errs: ^[dynamic]Transpile_Error,
) {
	// name :: proc(w: io.Writer[, user-params][, children callback]) -> io.Error {
	strings.write_string(sb, n.name)
	strings.write_string(sb, " :: proc(w: io.Writer")
	if len(n.params) > 0 {
		strings.write_string(sb, ", ")
		strings.write_string(sb, n.params)
	}
	if n.has_slot {
		strings.write_string(sb, ", children: proc(w: io.Writer) -> io.Error")
	}
	strings.write_string(sb, ") -> io.Error {")

	// Template body is Odin context: Odin_Span nodes are verbatim source.
	for node in n.body {
		_emit_node(sb, node, errs, false)
	}

	strings.write_string(sb, "}\n")
}

@(private = "file")
_emit_element :: proc(sb: ^strings.Builder, n: Element_Node, errs: ^[dynamic]Transpile_Error) {
	// <slot /> invokes the caller-supplied children callback.
	if n.tag == "slot" {
		strings.write_string(sb, "children(w) or_return\n")
		return
	}
	switch n.kind {
	case .Raw:
		_emit_raw_element(sb, n, errs)
	case .Component:
		// Component call emission is deferred to T-0006.
		append(
			errs,
			Transpile_Error{message = "component call emission not yet implemented", pos = n.pos},
		)
	}
}

@(private = "file")
_emit_raw_element :: proc(sb: ^strings.Builder, n: Element_Node, errs: ^[dynamic]Transpile_Error) {
	// HTML5 void elements are self-closing: emit a single combined string.
	if _is_void_element(n.tag) {
		strings.write_string(sb, `__weasel_write_raw_string(w, "<`)
		strings.write_string(sb, n.tag)
		strings.write_string(sb, `/>") or_return`)
		strings.write_byte(sb, '\n')
		return
	}

	// Open tag.
	strings.write_string(sb, `__weasel_write_raw_string(w, "<`)
	strings.write_string(sb, n.tag)
	strings.write_string(sb, `>") or_return`)
	strings.write_byte(sb, '\n')

	// Children are HTML context: Odin_Span nodes are text content.
	for child in n.children {
		_emit_node(sb, child, errs, true)
	}

	// Close tag.
	strings.write_string(sb, `__weasel_write_raw_string(w, "</`)
	strings.write_string(sb, n.tag)
	strings.write_string(sb, `>") or_return`)
	strings.write_byte(sb, '\n')
}

@(private = "file")
_emit_odin_block :: proc(sb: ^strings.Builder, n: Odin_Block, errs: ^[dynamic]Transpile_Error) {
	strings.write_string(sb, n.head)
	strings.write_byte(sb, '{')
	strings.write_byte(sb, '\n')
	// Children of an Odin_Block are HTML context (the block wraps element output).
	for child in n.children {
		_emit_node(sb, child, errs, true)
	}
	if len(n.tail) > 0 {
		strings.write_string(sb, n.tail)
		strings.write_byte(sb, '\n')
	}
}
