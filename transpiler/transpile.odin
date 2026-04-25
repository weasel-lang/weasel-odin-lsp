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

	Source map:
	  While emitting, a cursor tracks (offset, line, col) in the output buffer.
	  Whenever a fragment of the generated Odin corresponds to a recognisable
	  byte range in the .weasel source (procedure names, component tag names,
	  Expr_Node expressions, Odin passthrough, etc.) a Span_Entry is appended
	  to the Source_Map so downstream tooling can translate coordinates both
	  ways between the two files.  See source_map.odin for the data model.
*/
package transpiler

import "core:fmt"
import "core:strings"

// Transpile_Error records a single problem encountered while emitting code.
Transpile_Error :: struct {
	message: string,
	pos:     Position,
}

// _Emitter bundles the mutable state threaded through emission: the output
// builder, the running cursor used to compute odin-side span endpoints, the
// source map being populated, the error sink, and the same-file template
// signature table used to validate component calls.
@(private = "file")
_Emitter :: struct {
	sb:    ^strings.Builder,
	pos:   Position,
	smap:  ^Source_Map,
	errs:  ^[dynamic]Transpile_Error,
	known: map[string]bool,
}

// transpile converts a parsed AST into Odin source code and an accompanying
// Source_Map.  Caller owns the returned string (free with
// delete(transmute([]u8)source)), the map's entries
// (source_map_destroy(&smap)), and the error slice.
transpile :: proc(
	nodes: []Node,
	allocator := context.allocator,
) -> (source: string, smap: Source_Map, errs: [dynamic]Transpile_Error) {
	errs         = make([dynamic]Transpile_Error, allocator)
	smap.entries = make([dynamic]Span_Entry, allocator)
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

	e := _Emitter{
		sb    = &sb,
		pos   = Position{offset = 0, line = 1, col = 1},
		smap  = &smap,
		errs  = &errs,
		known = known,
	}

	for node in nodes {
		_emit_node(&e, node, false)
	}

	_sort_entries(&smap)
	source = strings.to_string(sb)

	// If any Template_Proc was emitted, the output references io.Writer and
	// io.Error. Inject `import "core:io"` automatically unless the Weasel
	// source already contains it (so the developer never has to add it).
	needs_io_import := false
	has_io_import   := false
	for node in nodes {
		switch n in node {
		case Template_Proc:
			needs_io_import = true
		case Odin_Span:
			if strings.contains(n.text, "core:io") {
				has_io_import = true
			}
		case Expr_Node, Element_Node, Odin_Block:
			// These cannot carry import declarations.
		}
	}
	if needs_io_import && !has_io_import {
		inject     := "import \"core:io\"\n"
		inject_len := len(inject)
		inject_at  := 0
		if strings.has_prefix(source, "package ") {
			if nl := strings.index(source, "\n"); nl >= 0 {
				inject_at = nl + 1
			}
		}

		// Adjust source map entries displaced by the injected line.
		for &entry in smap.entries {
			if entry.odin_start.offset >= inject_at {
				entry.odin_start.offset += inject_len
				entry.odin_start.line   += 1
				entry.odin_end.offset   += inject_len
				entry.odin_end.line     += 1
			} else if entry.odin_end.offset > inject_at {
				entry.odin_end.offset += inject_len
				entry.odin_end.line   += 1
			}
		}

		sb2 := strings.builder_make(allocator)
		strings.write_string(&sb2, source[:inject_at])
		strings.write_string(&sb2, inject)
		strings.write_string(&sb2, source[inject_at:])
		delete(sb.buf)
		source = strings.to_string(sb2)
	}

	return
}

// ---------------------------------------------------------------------------
// Emitter helpers
// ---------------------------------------------------------------------------

// _write appends s to the output and advances the cursor.
@(private = "file")
_write :: proc(e: ^_Emitter, s: string) {
	strings.write_string(e.sb, s)
	e.pos = advance_position(e.pos, s)
}

// _write_byte appends one byte to the output and advances the cursor.
@(private = "file")
_write_byte :: proc(e: ^_Emitter, b: byte) {
	strings.write_byte(e.sb, b)
	e.pos.offset += 1
	if b == '\n' {
		e.pos.line += 1
		e.pos.col = 1
	} else {
		e.pos.col += 1
	}
}

// _write_tracked appends s to the output and records a Span_Entry that maps
// the emitted range back to [weasel_start, weasel_start + len(s_weasel)) in
// the Weasel source.  s_weasel is usually equal to s (the fragment is
// preserved verbatim), but callers may pass a different string when the
// Weasel source bytes differ from the emitted bytes (e.g. a tag name emitted
// as an identifier call).
@(private = "file")
_write_tracked :: proc(e: ^_Emitter, s: string, weasel_start: Position, s_weasel: string = "") {
	start := e.pos
	_write(e, s)
	wstr := s_weasel if len(s_weasel) > 0 else s
	append(
		&e.smap.entries,
		Span_Entry{
			odin_start   = start,
			odin_end     = e.pos,
			weasel_start = weasel_start,
			weasel_end   = advance_position(weasel_start, wstr),
		},
	)
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

// _write_string_literal_content writes s into the emitter with the minimal
// escaping needed for it to be valid inside an Odin double-quoted string
// literal.  No span entries are recorded: the content lives inside a
// synthetic string literal in the generated Odin and is not a hoverable
// identifier from the LSP's perspective.
@(private = "file")
_write_string_literal_content :: proc(e: ^_Emitter, s: string) {
	for i := 0; i < len(s); i += 1 {
		switch s[i] {
		case '\\':
			_write(e, `\\`)
		case '"':
			_write(e, `\"`)
		case '\n':
			_write(e, `\n`)
		case '\r':
			_write(e, `\r`)
		case '\t':
			_write(e, `\t`)
		case:
			_write_byte(e, s[i])
		}
	}
}

// ---------------------------------------------------------------------------
// Node emitters
// ---------------------------------------------------------------------------

// _emit_node dispatches on node type. in_html controls how Odin_Span nodes
// are emitted: verbatim when false, as a raw-string write call when true.
@(private = "file")
_emit_node :: proc(e: ^_Emitter, node: Node, in_html: bool) {
	switch n in node {
	case Odin_Span:
		if in_html {
			// Text content inside an element: emit as a raw-string write call.
			// The text itself lives inside the emitted string literal, so no
			// identifier-level span is recorded.
			_write(e, `__weasel_write_raw_string(w, "`)
			_write_string_literal_content(e, n.text)
			_write(e, `") or_return`)
			_write_byte(e, '\n')
		} else {
			// Verbatim Odin passthrough: the whole span maps back to the
			// originating .weasel byte range.
			_write_tracked(e, n.text, n.pos)
		}
	case Expr_Node:
		_write(e, "__weasel_write_escaped_string(w, ")
		// Expr_Node.pos is at the '$' of the $(…) delimiter; the expression
		// bytes start two bytes later (after '$(').
		_write_tracked(e, n.expr, advance_position(n.pos, "$("))
		_write(e, ") or_return\n")
	case Element_Node:
		_emit_element(e, n)
	case Odin_Block:
		_emit_odin_block(e, n)
	case Template_Proc:
		_emit_template_proc(e, n)
	}
}

// _position_after_byte returns p advanced by a single non-newline byte.
// Used to step past single-character sigils ({ or <) to reach the payload.
@(private = "file")
_position_after_byte :: proc(p: Position) -> Position {
	return Position{offset = p.offset + 1, line = p.line, col = p.col + 1}
}

@(private = "file")
_emit_template_proc :: proc(e: ^_Emitter, n: Template_Proc) {
	// name :: proc(w: io.Writer[, user-params][, children callback]) -> io.Error {
	_write_tracked(e, n.name, n.name_pos)
	_write(e, " :: proc(w: io.Writer")
	if len(n.params) > 0 {
		_write(e, ", ")
		_write_tracked(e, n.params, n.params_pos)
	}
	if n.has_slot {
		_write(e, ", children: proc(w: io.Writer) -> io.Error")
	}
	_write(e, ") -> io.Error {")

	// Template body is Odin context: Odin_Span nodes are verbatim source.
	for node in n.body {
		_emit_node(e, node, false)
	}

	_write(e, "}\n")
}

@(private = "file")
_emit_element :: proc(e: ^_Emitter, n: Element_Node) {
	// <slot /> invokes the caller-supplied children callback.
	if n.tag == "slot" {
		_write(e, "children(w) or_return\n")
		return
	}
	switch n.kind {
	case .Raw:
		_emit_raw_element(e, n)
	case .Component:
		_emit_component(e, n)
	}
}

@(private = "file")
_emit_raw_element :: proc(e: ^_Emitter, n: Element_Node) {
	// HTML5 void elements are self-closing: emit a single combined string.
	if _is_void_element(n.tag) {
		_emit_open_tag(e, n.tag, n.attrs, true)
		return
	}

	// Open tag (with attributes).
	_emit_open_tag(e, n.tag, n.attrs, false)

	// Children are HTML context: Odin_Span nodes are text content.
	for child in n.children {
		_emit_node(e, child, true)
	}

	// Close tag.
	_write(e, `__weasel_write_raw_string(w, "</`)
	_write(e, n.tag)
	_write(e, `>") or_return`)
	_write_byte(e, '\n')
}

// _emit_open_tag emits one or more write calls that together produce the element
// opening tag (or self-closing tag when self_close is true).  Static attributes
// are folded into the raw-string literal; each dynamic attribute splits the
// literal: the prefix up to and including the attribute name and opening quote
// is flushed, then the expression is emitted via fmt.wprint, then accumulation
// continues from the closing quote of the attribute value.
@(private = "file")
_emit_open_tag :: proc(e: ^_Emitter, tag: string, attrs: [dynamic]Attr, self_close: bool) {
	// pending accumulates raw HTML text for the open tag.  It is flushed to
	// the emitter as a __weasel_write_raw_string call whenever a dynamic
	// attribute is encountered (or at the very end).
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
			_flush_pending(e, &pending)
			_write(e, "fmt.wprint(w, ")
			// attr.pos points at the attribute name; the expression is an
			// Odin identifier emitted verbatim, so we track it with the
			// best-available Weasel origin (the attribute as a whole).
			_write_tracked(e, attr.expr, attr.pos)
			_write(e, ")\n")
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
	_flush_pending(e, &pending)
}

// _flush_pending emits the current content of pending as a
// __weasel_write_raw_string call and resets the builder.  No-ops when pending
// is empty.
@(private = "file")
_flush_pending :: proc(e: ^_Emitter, pending: ^strings.Builder) {
	content := strings.to_string(pending^)
	if len(content) == 0 {return}
	_write(e, `__weasel_write_raw_string(w, "`)
	_write_string_literal_content(e, content)
	_write(e, `") or_return`)
	_write_byte(e, '\n')
	strings.builder_reset(pending)
}

// _write_props_name appends the component's Props struct name to the emitter
// and records a span covering it that maps back to the original tag.
// "card" → "Card_Props", "ui.card" → "Card_Props" (last segment, first letter uppercased).
@(private = "file")
_write_props_name :: proc(e: ^_Emitter, tag: string, tag_pos: Position) {
	// Derive "<Local>_Props" from the last dotted segment of the tag.
	local := tag
	local_pos := tag_pos
	if dot := strings.last_index(tag, "."); dot >= 0 {
		local = tag[dot + 1:]
		local_pos = advance_position(tag_pos, tag[:dot + 1])
	}

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	if len(local) > 0 {
		c := local[0]
		if c >= 'a' && c <= 'z' {
			strings.write_byte(&sb, c - ('a' - 'A'))
		} else {
			strings.write_byte(&sb, c)
		}
		strings.write_string(&sb, local[1:])
	}
	strings.write_string(&sb, "_Props")
	_write_tracked(e, strings.to_string(sb), local_pos, local)
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
_emit_component :: proc(e: ^_Emitter, n: Element_Node) {
	has_children := len(n.children) > 0

	// Validate children against same-file template definitions.
	if has_children {
		if has_slot, is_known := e.known[n.tag]; is_known && !has_slot {
			append(
				e.errs,
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

	// Emit the call name verbatim.  n.pos points at the '<'; the tag name
	// bytes start one column later in the .weasel source.
	tag_pos := _position_after_byte(n.pos)
	_write_tracked(e, n.tag, tag_pos)
	_write(e, "(w")

	// Props struct argument (only when attributes are present).
	if len(n.attrs) > 0 {
		_write(e, ", ")
		_write_props_name(e, n.tag, tag_pos)
		_write_byte(e, '{')
		for i in 0 ..< len(n.attrs) {
			if i > 0 {
				_write(e, ", ")
			}
			attr := n.attrs[i]
			_write_tracked(e, attr.name, attr.pos)
			_write(e, " = ")
			if attr.is_dynamic {
				_write_tracked(e, attr.expr, attr.pos)
			} else {
				_write_byte(e, '"')
				_write_string_literal_content(e, attr.value)
				_write_byte(e, '"')
			}
		}
		_write_byte(e, '}')
	}

	// Anonymous proc callback (only when child nodes are present).
	if has_children {
		_write(e, ", proc(w: io.Writer) -> io.Error {\n")
		for child in n.children {
			_emit_node(e, child, true)
		}
		_write(e, "return nil\n}")
	}

	_write(e, ") or_return\n")
}

@(private = "file")
_emit_odin_block :: proc(e: ^_Emitter, n: Odin_Block) {
	// Odin_Block.pos is at the opening '{' of the block; the head bytes
	// (e.g. "for x in items ") begin one byte later.
	_write_tracked(e, n.head, _position_after_byte(n.pos))
	_write_byte(e, '{')
	_write_byte(e, '\n')
	// Odin_Block children are in Odin context: Odin_Span nodes (e.g. case labels,
	// comments) are emitted verbatim.  Element_Node children emit their own HTML
	// write calls regardless of the in_html flag.
	for child in n.children {
		_emit_node(e, child, false)
	}
	if len(n.tail) > 0 {
		_write(e, n.tail)
		_write_byte(e, '\n')
	}
}
