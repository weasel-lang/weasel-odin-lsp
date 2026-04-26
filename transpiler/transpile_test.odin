package transpiler

import "core:testing"
import "core:strings"

// _spt scans, parses, and transpiles src in one call. Caller owns both
// returned values: free the string with delete(transmute([]u8)src).
// The source map is discarded by this helper; tests that need it use
// _spt_with_map in source_map_test.odin.
@(private = "file")
_spt :: proc(src: string) -> (string, [dynamic]Transpile_Error) {
	tokens, scan_errs := scan(src)
	defer delete(scan_errs)
	defer delete(tokens)
	nodes, parse_errs := parse(tokens[:])
	defer delete(parse_errs)
	defer delete(nodes)
	source, smap, errs := transpile(nodes[:])
	source_map_destroy(&smap)
	return source, errs
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
	testing.expect_value(t, src, "import \"core:io\"\nnoop :: proc(w: io.Writer) -> io.Error {\nreturn nil\n}\n")
}

@(test)
test_transpile_template_proc_with_params :: proc(t: ^testing.T) {
	src, errs := _spt("card :: template(p: ^Props) {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "import \"core:io\"\ncard :: proc(w: io.Writer, p: ^Props) -> io.Error {\nreturn nil\n}\n")
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
// Automatic core:io import injection
// ---------------------------------------------------------------------------

@(test)
test_transpile_template_injects_io_import :: proc(t: ^testing.T) {
	// A template proc without an existing core:io import must have one injected.
	src, errs := _spt("foo :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "import \"core:io\""),
		"expected injected import \"core:io\"",
	)
}

@(test)
test_transpile_no_template_no_io_import :: proc(t: ^testing.T) {
	// Plain Odin passthrough with no template must NOT inject the import.
	src, errs := _spt("x := 42\n")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		!strings.contains(src, "core:io"),
		"must not inject import when there are no template procs",
	)
}

@(test)
test_transpile_existing_io_import_not_duplicated :: proc(t: ^testing.T) {
	// If the Weasel source already imports core:io, the transpiler must not add
	// a second one.
	src, errs := _spt("import \"core:io\"\nfoo :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	count := 0
	rest  := src
	for {
		idx := strings.index(rest, "import \"core:io\"")
		if idx < 0 { break }
		count += 1
		rest   = rest[idx + len("import \"core:io\""):]
	}
	testing.expect(t, count == 1, "import \"core:io\" must appear exactly once")
}

@(test)
test_transpile_io_import_placed_after_package :: proc(t: ^testing.T) {
	// When there is a package declaration, the import must follow it.
	src, errs := _spt("package views\nfoo :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	pkg_pos    := strings.index(src, "package views")
	import_pos := strings.index(src, "import \"core:io\"")
	testing.expect(t, pkg_pos >= 0,    "expected package declaration in output")
	testing.expect(t, import_pos >= 0, "expected import \"core:io\" in output")
	testing.expect(t, pkg_pos < import_pos, "import must follow package declaration")
}

@(test)
test_transpile_io_import_precedes_proc_when_no_package :: proc(t: ^testing.T) {
	// Without a package declaration, the import is prepended before the proc.
	src, errs := _spt("foo :: template() {\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	import_pos := strings.index(src, "import \"core:io\"")
	proc_pos   := strings.index(src, "foo :: proc(")
	testing.expect(t, import_pos >= 0, "expected import \"core:io\"")
	testing.expect(t, proc_pos >= 0,   "expected proc declaration")
	testing.expect(t, import_pos < proc_pos, "import must precede the proc declaration")
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
	// $(expr) emits __weasel_write_escaped_string(w, expr) or_return.
	src, errs := _spt("<p>$(title)</p>")
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
	src, errs := _spt("<span>$(p.name)</span>")
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
		strings.contains(src, "foo :: proc("),
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
	// Static text fragments adjacent to $(expr) interpolation.
	// <div>Hello $(p.user.name)!</div> should emit three write calls between
	// the open/close tags: static "Hello ", escaped expr, static "!".
	src, errs := _spt("<div>Hello $(p.user.name)!</div>")
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
	src, errs := _spt("<div>Hello $(p.user.name)!</div>")
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

// ---------------------------------------------------------------------------
// Attribute handling
// ---------------------------------------------------------------------------

@(test)
test_transpile_static_attr_folded_into_open_tag :: proc(t: ^testing.T) {
	// Static attribute must be folded into the opening tag string literal.
	src, errs := _spt(`<div class="card"></div>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<div class=\"card\">") or_return`),
		`expected static attr folded into open-tag string`,
	)
}

@(test)
test_transpile_multiple_static_attrs :: proc(t: ^testing.T) {
	src, errs := _spt(`<a href="/home" class="nav">link</a>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<a href=\"/home\" class=\"nav\">") or_return`),
		`expected both static attrs in single open-tag string`,
	)
}

@(test)
test_transpile_dynamic_attr_splits_string :: proc(t: ^testing.T) {
	// Dynamic attr must split: prefix raw_string, fmt.wprint, suffix raw_string.
	src, errs := _spt(`<div class={cls}></div>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<div class=\"") or_return`),
		`expected open-tag prefix before dynamic attr`,
	)
	testing.expect(
		t,
		strings.contains(src, "fmt.wprint(w, cls)"),
		`expected fmt.wprint call for dynamic attr value`,
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "\">") or_return`),
		`expected closing quote + > after dynamic attr`,
	)
}

@(test)
test_transpile_dynamic_attr_ordering :: proc(t: ^testing.T) {
	// Prefix must appear before fmt.wprint which must appear before suffix.
	src, errs := _spt(`<div class={cls}></div>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	prefix_pos := strings.index(src, `"<div class=\""`)
	wprint_pos := strings.index(src, "fmt.wprint(w, cls)")
	suffix_pos := strings.index(src, `"\">`)

	testing.expect(t, prefix_pos >= 0, "prefix not found")
	testing.expect(t, wprint_pos >= 0, "fmt.wprint not found")
	testing.expect(t, suffix_pos >= 0, "suffix not found")
	testing.expect(t, prefix_pos < wprint_pos, "prefix must precede fmt.wprint")
	testing.expect(t, wprint_pos < suffix_pos, "fmt.wprint must precede suffix")
}

@(test)
test_transpile_mixed_static_and_dynamic_attrs :: proc(t: ^testing.T) {
	// Static attrs before the dynamic one must be folded into the prefix string.
	src, errs := _spt(`<input type="text" value={val} />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<input type=\"text\" value=\"") or_return`),
		`expected static attr included in prefix`,
	)
	testing.expect(
		t,
		strings.contains(src, "fmt.wprint(w, val)"),
		`expected fmt.wprint for dynamic attr`,
	)
}

@(test)
test_transpile_static_after_dynamic_attr :: proc(t: ^testing.T) {
	// Static attr after a dynamic one must be in the suffix string.
	src, errs := _spt(`<div id={eid} class="box"></div>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "fmt.wprint(w, eid)"),
		`expected fmt.wprint for dynamic attr`,
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "\" class=\"box\">") or_return`),
		`expected static attr and closing > in suffix`,
	)
}

@(test)
test_transpile_void_element_with_static_attr :: proc(t: ^testing.T) {
	src, errs := _spt(`<img src="logo.png" />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<img src=\"logo.png\"/>") or_return`),
		`expected static attr in void element`,
	)
}

@(test)
test_transpile_void_element_with_dynamic_attr :: proc(t: ^testing.T) {
	src, errs := _spt(`<input value={v} />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<input value=\"") or_return`),
		`expected prefix for void element with dynamic attr`,
	)
	testing.expect(
		t,
		strings.contains(src, "fmt.wprint(w, v)"),
		`expected fmt.wprint for void element dynamic attr`,
	)
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "\"/>") or_return`),
		`expected self-close suffix for void element`,
	)
}

@(test)
test_transpile_dynamic_attr_expr_verbatim :: proc(t: ^testing.T) {
	// Complex expressions must be emitted verbatim without transformation.
	src, errs := _spt(`<div id={p.user.id}></div>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "fmt.wprint(w, p.user.id)"),
		`expected complex expr emitted verbatim`,
	)
}

// ---------------------------------------------------------------------------
// Odin_Block (control-flow with nested elements)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Component call emission
// ---------------------------------------------------------------------------

@(test)
test_transpile_component_self_close_no_attrs :: proc(t: ^testing.T) {
	// <card /> with no attributes → card(w) or_return
	src, errs := _spt("<card />")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "card(w) or_return\n")
}

@(test)
test_transpile_component_self_close_with_static_attr :: proc(t: ^testing.T) {
	// <card title="Task" /> → card(w, Card_Props{title = "Task"}) or_return
	src, errs := _spt(`<card title="Task" />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, `card(w, Card_Props{title = "Task"}) or_return` + "\n")
}

@(test)
test_transpile_component_self_close_with_dynamic_attr :: proc(t: ^testing.T) {
	// <card title={t} /> → card(w, Card_Props{title = t}) or_return
	src, errs := _spt("<card title={t} />")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "card(w, Card_Props{title = t}) or_return\n")
}

@(test)
test_transpile_component_with_children_no_attrs :: proc(t: ^testing.T) {
	// <card><p></p></card> → card(w, proc(w: io.Writer) -> io.Error { ... return nil }) or_return
	src, errs := _spt("<card><p></p></card>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.has_prefix(src, "card(w, proc(w: io.Writer) -> io.Error {"),
		"expected component call with anonymous proc",
	)
	testing.expect(t, strings.contains(src, "return nil\n}") , "expected return nil in proc")
	testing.expect(t, strings.contains(src, ") or_return"), "expected or_return after call")
	testing.expect(
		t,
		strings.contains(src, `__weasel_write_raw_string(w, "<p>") or_return`),
		"expected p open inside callback",
	)
}

@(test)
test_transpile_component_with_attrs_and_children :: proc(t: ^testing.T) {
	// <card title="x"><p></p></card> → card(w, Card_Props{title = "x"}, proc(...) { ... }) or_return
	src, errs := _spt(`<card title="x"><p></p></card>`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `card(w, Card_Props{title = "x"}, proc(w: io.Writer) -> io.Error {`),
		"expected card call with props and children callback",
	)
	testing.expect(t, strings.contains(src, "return nil\n}") , "expected return nil in proc")
	testing.expect(t, strings.contains(src, ") or_return"), "expected or_return after call")
}

@(test)
test_transpile_component_dotted_name :: proc(t: ^testing.T) {
	// <ui.card title="x" /> → ui.card(w, Card_Props{title = "x"}) or_return
	src, errs := _spt(`<ui.card title="x" />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, `ui.card(w, Card_Props{title = "x"}) or_return` + "\n")
}

@(test)
test_transpile_component_dotted_name_no_attrs :: proc(t: ^testing.T) {
	// <ui.card /> → ui.card(w) or_return
	src, errs := _spt("<ui.card />")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, src, "ui.card(w) or_return\n")
}

@(test)
test_transpile_component_multiple_attrs :: proc(t: ^testing.T) {
	// Multiple attrs folded into the struct literal.
	src, errs := _spt(`<card title="Hello" size={n} />`)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `Card_Props{title = "Hello", size = n}`),
		"expected both attrs in composite literal",
	)
}

@(test)
test_transpile_component_children_slotless_error :: proc(t: ^testing.T) {
	// Passing children to a template without <slot /> is a transpile error.
	// Define a slotless template in the same source, then call it with children.
	src, errs := _spt("plain :: template() {\n<div></div>\n}\n<plain><p></p></plain>")
	defer delete(errs)

	testing.expect(t, len(errs) > 0, "expected a transpile error for children on slotless component")
	_ = src
}

@(test)
test_transpile_component_children_recursive :: proc(t: ^testing.T) {
	// Children inside the callback are themselves transpiled recursively.
	src, errs := _spt("<card><span>$(msg)</span></card>")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, "__weasel_write_escaped_string(w, msg) or_return"),
		"expected recursive transpilation of inline expr inside callback",
	)
}

@(test)
test_transpile_component_in_template :: proc(t: ^testing.T) {
	// Component calls inside a template body are also transpiled.
	src, errs := _spt("page :: template() {\n<card title=\"hi\" />\n}")
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect(
		t,
		strings.contains(src, `card(w, Card_Props{title = "hi"}) or_return`),
		"expected component call inside template body",
	)
}

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
