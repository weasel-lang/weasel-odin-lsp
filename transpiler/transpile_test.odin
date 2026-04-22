package transpiler

import "core:testing"
import "core:strings"

// _spt scans, parses, and transpiles src in one call. Caller owns both
// returned values: free the string with delete(transmute([]u8)src).
@(private = "file")
_spt :: proc(src: string) -> (string, [dynamic]Transpile_Error) {
	tokens, scan_errs := scan(src)
	defer delete(scan_errs)
	defer delete(tokens)
	nodes, parse_errs := parse(tokens[:])
	defer delete(parse_errs)
	defer delete(nodes)
	return transpile(nodes[:])
}

// ---------------------------------------------------------------------------
// Odin_Span passthrough
// ---------------------------------------------------------------------------

@(test)
test_transpile_odin_span_passthrough :: proc(t: ^testing.T) {
	src, errs := _spt("x := 42\n")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "x := 42\n")
}

// ---------------------------------------------------------------------------
// Template proc signature
// ---------------------------------------------------------------------------

@(test)
test_transpile_template_proc_no_params :: proc(t: ^testing.T) {
	src, errs := _spt("noop :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "noop :: proc(w: io.Writer) -> io.Error {\n}\n")
}

@(test)
test_transpile_template_proc_with_params :: proc(t: ^testing.T) {
	src, errs := _spt("card :: template(p: ^Props) {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "card :: proc(w: io.Writer, p: ^Props) -> io.Error {\n}\n")
}

@(test)
test_transpile_template_proc_return_type :: proc(t: ^testing.T) {
	// Every generated template proc must have -> io.Error as its return type.
	src, errs := _spt("render :: template(n: int) {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, ") -> io.Error {"),
		"expected '-> io.Error' in proc signature",
	)
}

// ---------------------------------------------------------------------------
// Slot: signature extension and body emission
// ---------------------------------------------------------------------------

@(test)
test_transpile_template_with_slot_adds_children_param :: proc(t: ^testing.T) {
	// <slot /> in the template body → children callback appended to signature.
	src, errs := _spt("layout :: template() {\n<slot />\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, ", children: proc(w: io.Writer) -> io.Error"),
		"expected children callback parameter in signature",
	)
}

@(test)
test_transpile_slot_emits_children_call :: proc(t: ^testing.T) {
	// <slot /> in the body emits children(w) or_return.
	src, errs := _spt("layout :: template() {\n<slot />\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "children(w) or_return"),
		"expected 'children(w) or_return' in emitted body",
	)
}

@(test)
test_transpile_template_no_slot_no_children_param :: proc(t: ^testing.T) {
	// Template without <slot /> must NOT have a children parameter.
	src, errs := _spt("plain :: template() {\n<div></div>\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		!strings.contains(src, "children"),
		"unexpected 'children' parameter in template without slot",
	)
}

// ---------------------------------------------------------------------------
// Raw HTML element emission
// ---------------------------------------------------------------------------

@(test)
test_transpile_void_element_self_close :: proc(t: ^testing.T) {
	// <br /> is a void element — emitted as a single self-closing string.
	src, errs := _spt("<br />")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, `__weasel_write_raw_string(w, "<br/>") or_return` + "\n")
}

@(test)
test_transpile_void_element_hr :: proc(t: ^testing.T) {
	src, errs := _spt("<hr />")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, `__weasel_write_raw_string(w, "<hr/>") or_return` + "\n")
}

@(test)
test_transpile_raw_element_open_and_close :: proc(t: ^testing.T) {
	// <div></div> — non-void element with no children: open + close calls.
	src, errs := _spt("<div></div>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	expected :=
		`__weasel_write_raw_string(w, "<div>") or_return` +
		"\n" +
		`__weasel_write_raw_string(w, "</div>") or_return` +
		"\n"
	testing.expect_value(t, src, expected)
}

@(test)
test_transpile_raw_element_with_children :: proc(t: ^testing.T) {
	src, errs := _spt("<ul><li></li></ul>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, strings.contains(src, `__weasel_write_raw_string(w, "<ul>") or_return`), "expected ul open")
	testing.expect(t, strings.contains(src, `__weasel_write_raw_string(w, "<li>") or_return`), "expected li open")
	testing.expect(t, strings.contains(src, `__weasel_write_raw_string(w, "</li>") or_return`), "expected li close")
	testing.expect(t, strings.contains(src, `__weasel_write_raw_string(w, "</ul>") or_return`), "expected ul close")
}

// ---------------------------------------------------------------------------
// Inline expression emission
// ---------------------------------------------------------------------------

@(test)
test_transpile_inline_expr :: proc(t: ^testing.T) {
	// {expr} emits __weasel_write_escaped_string(w, expr) or_return.
	src, errs := _spt("<p>{title}</p>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "__weasel_write_escaped_string(w, title) or_return"),
		"expected escaped write call for inline expr",
	)
}

@(test)
test_transpile_inline_expr_field_access :: proc(t: ^testing.T) {
	src, errs := _spt("<span>{p.name}</span>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "__weasel_write_escaped_string(w, p.name) or_return"),
		"expected escaped write call for field access expr",
	)
}

// ---------------------------------------------------------------------------
// Full template round-trip
// ---------------------------------------------------------------------------

@(test)
test_transpile_full_template_with_raw_element :: proc(t: ^testing.T) {
	// Full template: rewritten signature + raw element open/close calls.
	src, errs := _spt("page :: template(p: ^Props) {\n<div></div>\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "page :: proc(w: io.Writer, p: ^Props) -> io.Error {"),
		"expected rewritten proc signature",
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<div>") or_return`),
		"expected div open call",
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "</div>") or_return`),
		"expected div close call",
	)
}

@(test)
test_transpile_template_keyword_replaced_with_proc :: proc(t: ^testing.T) {
	// 'template' keyword must not appear in the output.
	src, errs := _spt("foo :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		!strings.contains(src, "template"),
		"'template' keyword must not appear in emitted output",
	)
	testing.expect(
		t,
		strings.has_prefix(src, "foo :: proc("),
		"expected 'proc' keyword in emitted output",
	)
}

// ---------------------------------------------------------------------------
// Static text content inside elements
// ---------------------------------------------------------------------------

@(test)
test_transpile_static_text_in_element :: proc(t: ^testing.T) {
	// Text content inside an element is HTML, not Odin — must be emitted as a
	// raw-string write call, not passed through verbatim.
	src, errs := _spt("<div>Hello</div>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	expected :=
		`__weasel_write_raw_string(w, "<div>") or_return` +
		"\n" +
		`__weasel_write_raw_string(w, "Hello") or_return` +
		"\n" +
		`__weasel_write_raw_string(w, "</div>") or_return` +
		"\n"
	testing.expect_value(t, src, expected)
}

@(test)
test_transpile_static_text_mixed_with_expr :: proc(t: ^testing.T) {
	// Static text fragments adjacent to {expr} interpolation.
	// <div>Hello {p.user.name}!</div> should emit three write calls between
	// the open/close tags: static "Hello ", escaped expr, static "!".
	src, errs := _spt("<div>Hello {p.user.name}!</div>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "Hello ") or_return`),
		`expected write call for "Hello " text fragment`,
	)
	testing.expect(
		t,
		strings.contains(src, "__weasel_write_escaped_string(w, p.user.name) or_return"),
		"expected escaped write call for p.user.name",
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "!") or_return`),
		`expected write call for "!" text fragment`,
	)
}

@(test)
test_transpile_static_text_ordering :: proc(t: ^testing.T) {
	// Verify "Hello " appears before p.user.name and "!" appears after.
	src, errs := _spt("<div>Hello {p.user.name}!</div>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)

	hello_pos := strings.index(src, `"Hello "`)
	name_pos := strings.index(src, "p.user.name")
	bang_pos := strings.index(src, `"!"`)

	testing.expect(t, hello_pos >= 0, `"Hello " not found`)
	testing.expect(t, name_pos >= 0, "p.user.name not found")
	testing.expect(t, bang_pos >= 0, `"!" not found`)
	testing.expect(t, hello_pos < name_pos, `"Hello " must come before p.user.name`)
	testing.expect(t, name_pos < bang_pos, `p.user.name must come before "!"`)
}

@(test)
test_transpile_static_text_escaping :: proc(t: ^testing.T) {
	// Double quotes in text content must be escaped in the string literal.
	src, errs := _spt(`<p>Say "hi"</p>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `"Say \"hi\""`),
		`expected escaped quotes in string literal`,
	)
}

// ---------------------------------------------------------------------------
// Odin_Block (control-flow with nested elements)
// ---------------------------------------------------------------------------

@(test)
test_transpile_odin_block_for :: proc(t: ^testing.T) {
	src, errs := _spt("<ul>{for item in items { <li></li>\n}}</ul>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "for item in items {"),
		"expected for-loop head in emitted output",
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<li>") or_return`),
		"expected li open inside for loop",
	)
}
