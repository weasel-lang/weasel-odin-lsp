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

import "core:fmt"
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

	// Build a map of template proc names to their has_slot status so that
	// component call sites in the same file can be validated at transpile time.
	known := make(map[string]bool, allocator)
	defer delete(known)
	for node in nodes {
		if tp, ok := node.(Template_Proc); ok {
			known[tp.name] = tp.has_slot
		}
	}

	for node in nodes {
		_emit_node(&sb, node, &errs, false, known)
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
	sb:      ^strings.Builder,
	node:    Node,
	errs:    ^[dynamic]Transpile_Error,
	in_html: bool,
	known:   map[string]bool,
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
		_emit_element(sb, n, errs, known)
	case Odin_Block:
		_emit_odin_block(sb, n, errs, known)
	case Template_Proc:
		_emit_template_proc(sb, n, errs, known)
	}
}

@(private = "file")
_emit_template_proc :: proc(
	sb:    ^strings.Builder,
	n:     Template_Proc,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
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
		_emit_node(sb, node, errs, false, known)
	}

	strings.write_string(sb, "}\n")
}

@(private = "file")
_emit_element :: proc(
	sb:    ^strings.Builder,
	n:     Element_Node,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
) {
	// <slot /> invokes the caller-supplied children callback.
	if n.tag == "slot" {
		strings.write_string(sb, "children(w) or_return\n")
		return
	}
	switch n.kind {
	case .Raw:
		_emit_raw_element(sb, n, errs, known)
	case .Component:
		_emit_component(sb, n, errs, known)
	}
}

@(private = "file")
_emit_raw_element :: proc(
	sb:    ^strings.Builder,
	n:     Element_Node,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
) {
	// HTML5 void elements are self-closing: emit a single combined string.
	if _is_void_element(n.tag) {
		_emit_open_tag(sb, n.tag, n.attrs, true)
		return
	}

	// Open tag (with attributes).
	_emit_open_tag(sb, n.tag, n.attrs, false)

	// Children are HTML context: Odin_Span nodes are text content.
	for child in n.children {
		_emit_node(sb, child, errs, true, known)
	}

	// Close tag.
	strings.write_string(sb, `__weasel_write_raw_string(w, "</`)
	strings.write_string(sb, n.tag)
	strings.write_string(sb, `>") or_return`)
	strings.write_byte(sb, '\n')
}

// _emit_open_tag emits one or more write calls that together produce the element
// opening tag (or self-closing tag when self_close is true).  Static attributes
// are folded into the raw-string literal; each dynamic attribute splits the
// literal: the prefix up to and including the attribute name and opening quote
// is flushed, then the expression is emitted via fmt.wprint, then accumulation
// continues from the closing quote of the attribute value.
@(private = "file")
_emit_open_tag :: proc(
	sb:         ^strings.Builder,
	tag:        string,
	attrs:      [dynamic]Attr,
	self_close: bool,
) {
	// pending accumulates raw HTML text for the open tag.  It is flushed to sb
	// as a __weasel_write_raw_string call whenever a dynamic attribute is
	// encountered (or at the very end).
	pending := strings.builder_make()
	defer strings.builder_destroy(&pending)

	// Start with "<tag".
	strings.write_byte(&pending, '<')
	strings.write_string(&pending, tag)

	for attr in attrs {
		if attr.is_dynamic {
			// Append ` name="` to pending, flush, then emit the expression.
			strings.write_byte(&pending, ' ')
			strings.write_string(&pending, attr.name)
			strings.write_string(&pending, `="`)
			_flush_pending(sb, &pending)
			strings.write_string(sb, "fmt.wprint(w, ")
			strings.write_string(sb, attr.expr)
			strings.write_string(sb, ")\n")
			// Pending resumes from the closing quote of the attribute value.
			strings.write_byte(&pending, '"')
		} else {
			// Static attribute: ` name="value"` or boolean ` name`.
			strings.write_byte(&pending, ' ')
			strings.write_string(&pending, attr.name)
			if len(attr.value) > 0 {
				strings.write_string(&pending, `="`)
				strings.write_string(&pending, attr.value)
				strings.write_byte(&pending, '"')
			}
		}
	}

	// Append the closing `>` or `/>` and flush.
	if self_close {
		strings.write_string(&pending, "/>")
	} else {
		strings.write_byte(&pending, '>')
	}
	_flush_pending(sb, &pending)
}

// _flush_pending emits the current content of pending as a
// __weasel_write_raw_string call and resets the builder.  No-ops when pending
// is empty.
@(private = "file")
_flush_pending :: proc(sb: ^strings.Builder, pending: ^strings.Builder) {
	content := strings.to_string(pending^)
	if len(content) == 0 {return}
	strings.write_string(sb, `__weasel_write_raw_string(w, "`)
	_write_string_literal_content(sb, content)
	strings.write_string(sb, `") or_return`)
	strings.write_byte(sb, '\n')
	strings.builder_reset(pending)
}

// _write_props_name appends the component's Props struct name to sb.
// "card" → "Card_Props", "ui.card" → "Card_Props" (last segment, first letter uppercased).
@(private = "file")
_write_props_name :: proc(sb: ^strings.Builder, tag: string) {
	local := tag
	if dot := strings.last_index(tag, "."); dot >= 0 {
		local = tag[dot + 1:]
	}
	if len(local) > 0 {
		c := local[0]
		if c >= 'a' && c <= 'z' {
			strings.write_byte(sb, c - ('a' - 'A'))
		} else {
			strings.write_byte(sb, c)
		}
		strings.write_string(sb, local[1:])
	}
	strings.write_string(sb, "_Props")
}

// _emit_component emits a template proc call for a Component-kind Element_Node.
//
// Emission rules:
//   No attrs, no children:   tag(w) or_return
//   Has attrs, no children:  tag(w, &Tag_Props{field = val, ...}) or_return
//   No attrs, has children:  tag(w, proc(w: io.Writer) -> io.Error { ... return nil }) or_return
//   Has attrs, has children: tag(w, &Tag_Props{...}, proc(w: io.Writer) -> io.Error { ... return nil }) or_return
//
// Passing children to a template known (in the same file) to have no <slot /> is a transpile error.
@(private = "file")
_emit_component :: proc(
	sb:    ^strings.Builder,
	n:     Element_Node,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
) {
	has_children := len(n.children) > 0

	// Validate children against same-file template definitions.
	if has_children {
		if has_slot, is_known := known[n.tag]; is_known && !has_slot {
			append(
				errs,
				Transpile_Error{
					message = fmt.aprintf(
						"component '%s' has no <slot />, cannot pass children",
						n.tag,
					),
					pos = n.pos,
				},
			)
			return
		}
	}

	// Emit the call name (verbatim; may be dotted e.g. "ui.card").
	strings.write_string(sb, n.tag)
	strings.write_string(sb, "(w")

	// Props struct argument (only when attributes are present).
	if len(n.attrs) > 0 {
		strings.write_string(sb, ", &")
		_write_props_name(sb, n.tag)
		strings.write_byte(sb, '{')
		for i in 0 ..< len(n.attrs) {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			attr := n.attrs[i]
			strings.write_string(sb, attr.name)
			strings.write_string(sb, " = ")
			if attr.is_dynamic {
				strings.write_string(sb, attr.expr)
			} else {
				strings.write_byte(sb, '"')
				_write_string_literal_content(sb, attr.value)
				strings.write_byte(sb, '"')
			}
		}
		strings.write_byte(sb, '}')
	}

	// Anonymous proc callback (only when child nodes are present).
	if has_children {
		strings.write_string(sb, ", proc(w: io.Writer) -> io.Error {\n")
		for child in n.children {
			_emit_node(sb, child, errs, true, known)
		}
		strings.write_string(sb, "return nil\n}")
	}

	strings.write_string(sb, ") or_return\n")
}

@(private = "file")
_emit_odin_block :: proc(
	sb:    ^strings.Builder,
	n:     Odin_Block,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
) {
	strings.write_string(sb, n.head)
	strings.write_byte(sb, '{')
	strings.write_byte(sb, '\n')
	// Odin_Block children are in Odin context: Odin_Span nodes (e.g. case labels,
	// comments) are emitted verbatim.  Element_Node children emit their own HTML
	// write calls regardless of the in_html flag.
	for child in n.children {
		_emit_node(sb, child, errs, false, known)
	}
	if len(n.tail) > 0 {
		strings.write_string(sb, n.tail)
		strings.write_byte(sb, '\n')
	}
}
