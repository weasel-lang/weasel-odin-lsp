package transpiler

import "core:testing"

// _sp scans and parses src, returning nodes and errors.
// Caller must delete both returned slices.
@(private = "file")
_sp :: proc(src: string) -> ([dynamic]Node, [dynamic]Parse_Error) {
	tokens, scan_errs := scan(src)
	defer delete(scan_errs)
	defer delete(tokens)
	return parse(tokens[:])
}

// ---------------------------------------------------------------------------
// Host_Span passthrough
// ---------------------------------------------------------------------------

@(test)
test_parse_pure_odin :: proc(t: ^testing.T) {
	nodes, errs := _sp("x := 42\n")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)
	span, ok := nodes[0].(Host_Span)
	testing.expect(t, ok, "expected Host_Span")
	testing.expect_value(t, span.text, "x := 42\n")
}

// ---------------------------------------------------------------------------
// Self-closing elements
// ---------------------------------------------------------------------------

@(test)
test_parse_self_close_raw :: proc(t: ^testing.T) {
	nodes, errs := _sp("<br />")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)
	elem, ok := nodes[0].(Element_Node)
	testing.expect(t, ok, "expected Element_Node")
	testing.expect_value(t, elem.tag, "br")
	testing.expect_value(t, elem.kind, Tag_Kind.Raw)
	testing.expect_value(t, len(elem.attrs), 0)
	testing.expect_value(t, len(elem.children), 0)
}

@(test)
test_parse_self_close_component :: proc(t: ^testing.T) {
	nodes, errs := _sp(`<task_item task={t} />`)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)
	elem, ok := nodes[0].(Element_Node)
	testing.expect(t, ok, "expected Element_Node")
	testing.expect_value(t, elem.tag, "task_item")
	testing.expect_value(t, elem.kind, Tag_Kind.Component)
	testing.expect_value(t, len(elem.attrs), 1)
	attr0 := elem.attrs[0].(Attr)
	testing.expect_value(t, attr0.name, "task")
	testing.expect_value(t, attr0.expr, "t")
	testing.expect_value(t, attr0.is_dynamic, true)
}

@(test)
test_parse_self_close_no_attrs :: proc(t: ^testing.T) {
	nodes, errs := _sp("<slot />")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem, ok := nodes[0].(Element_Node)
	testing.expect(t, ok)
	testing.expect_value(t, elem.tag, "slot")
	testing.expect_value(t, len(elem.children), 0)
}

// ---------------------------------------------------------------------------
// Static and dynamic attributes
// ---------------------------------------------------------------------------

@(test)
test_parse_static_attr :: proc(t: ^testing.T) {
	nodes, errs := _sp(`<div class="card"></div>`)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem := nodes[0].(Element_Node)
	testing.expect_value(t, len(elem.attrs), 1)
	static0 := elem.attrs[0].(Attr)
	testing.expect_value(t, static0.name, "class")
	testing.expect_value(t, static0.value, "card")
	testing.expect_value(t, static0.is_dynamic, false)
}

@(test)
test_parse_dynamic_attr :: proc(t: ^testing.T) {
	nodes, errs := _sp("<div class={cls}></div>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem := nodes[0].(Element_Node)
	testing.expect_value(t, len(elem.attrs), 1)
	dyn0 := elem.attrs[0].(Attr)
	testing.expect_value(t, dyn0.name, "class")
	testing.expect_value(t, dyn0.expr, "cls")
	testing.expect_value(t, dyn0.is_dynamic, true)
}

@(test)
test_parse_boolean_attr :: proc(t: ^testing.T) {
	nodes, errs := _sp("<input disabled />")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem := nodes[0].(Element_Node)
	testing.expect_value(t, len(elem.attrs), 1)
	bool0 := elem.attrs[0].(Attr)
	testing.expect_value(t, bool0.name, "disabled")
	testing.expect_value(t, bool0.value, "")
	testing.expect_value(t, bool0.expr, "")
	testing.expect_value(t, bool0.is_dynamic, false)
}

// ---------------------------------------------------------------------------
// Inline expressions
// ---------------------------------------------------------------------------

@(test)
test_parse_inline_expr :: proc(t: ^testing.T) {
	nodes, errs := _sp("<h2>$(p.title)</h2>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem := nodes[0].(Element_Node)
	testing.expect_value(t, len(elem.children), 1)
	expr, ok := elem.children[0].(Expr_Node)
	testing.expect(t, ok, "expected Expr_Node")
	testing.expect_value(t, expr.expr, "p.title")
}

// ---------------------------------------------------------------------------
// Nested elements
// ---------------------------------------------------------------------------

@(test)
test_parse_nested_elements :: proc(t: ^testing.T) {
	nodes, errs := _sp("<div><p>$(text)</p></div>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)

	div := nodes[0].(Element_Node)
	testing.expect_value(t, div.tag, "div")
	testing.expect_value(t, len(div.children), 1)

	p := div.children[0].(Element_Node)
	testing.expect_value(t, p.tag, "p")
	testing.expect_value(t, len(p.children), 1)

	expr := p.children[0].(Expr_Node)
	testing.expect_value(t, expr.expr, "text")
}

@(test)
test_parse_deeply_nested :: proc(t: ^testing.T) {
	nodes, errs := _sp("<a><b><c><d /></c></b></a>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	a := nodes[0].(Element_Node)
	b := a.children[0].(Element_Node)
	c := b.children[0].(Element_Node)
	d := c.children[0].(Element_Node)
	testing.expect_value(t, d.tag, "d")
	testing.expect_value(t, len(d.children), 0)
}

// ---------------------------------------------------------------------------
// Host_Block (control-flow with nested elements)
// ---------------------------------------------------------------------------

@(test)
test_parse_odin_block_for :: proc(t: ^testing.T) {
	nodes, errs := _sp("<ul>{for x in items { <li />\n}}</ul>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	ul := nodes[0].(Element_Node)
	testing.expect_value(t, len(ul.children), 1)

	blk, ok := ul.children[0].(Host_Block)
	testing.expect(t, ok, "expected Host_Block")
	testing.expect_value(t, blk.head, "for x in items ")
	testing.expect_value(t, blk.tail, "}")

	// Body may include whitespace Host_Spans around the element.
	li_found := false
	for child in blk.children {
		if elem, is_elem := child.(Element_Node); is_elem && elem.tag == "li" {
			li_found = true
		}
	}
	testing.expect(t, li_found, "expected <li> in Host_Block children")
}

@(test)
test_parse_odin_block_if :: proc(t: ^testing.T) {
	nodes, errs := _sp("<div>{if show { <span>yes</span> }}</div>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	div := nodes[0].(Element_Node)
	blk, ok := div.children[0].(Host_Block)
	testing.expect(t, ok, "expected Host_Block")
	testing.expect_value(t, blk.head, "if show ")

	span_found := false
	for child in blk.children {
		if elem, is_elem := child.(Element_Node); is_elem && elem.tag == "span" {
			span_found = true
		}
	}
	testing.expect(t, span_found, "expected <span> in Host_Block children")
}

@(test)
test_parse_odin_block_leading_whitespace :: proc(t: ^testing.T) {
	// Control-flow keywords do not have to immediately follow the opening brace —
	// leading whitespace (newlines, indentation) must not defeat detection for
	// any supported keyword.
	cases := []struct {
		src:  string,
		head: string,
	}{
		{"<ul>{\n    for x in items {\n        <li />\n    }\n}</ul>", "\n    for x in items "},
		{"<div>{\n    if show {\n        <span />\n    }\n}</div>", "\n    if show "},
		{"<div>{\n    switch k {\n    case: <span />\n    }\n}</div>", "\n    switch k "},
		{"<div>{\n    when ODIN_DEBUG {\n        <span />\n    }\n}</div>", "\n    when ODIN_DEBUG "},
	}

	for c in cases {
		nodes, errs := _sp(c.src)
		defer delete(nodes)
		defer delete(errs)

		testing.expect_value(t, len(errs), 0)
		parent := nodes[0].(Element_Node)
		testing.expect_value(t, len(parent.children), 1)

		blk, ok := parent.children[0].(Host_Block)
		testing.expect(t, ok, "expected Host_Block, got Expr_Node")
		testing.expect_value(t, blk.head, c.head)
		testing.expect_value(t, blk.tail, "}")
	}
}

@(test)
test_parse_expr_delimiter :: proc(t: ^testing.T) {
	// $() always produces Expr_Node; {} always produces Host_Block.
	nodes, errs := _sp("<p>$(form.name)</p>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	p := nodes[0].(Element_Node)
	expr, is_expr := p.children[0].(Expr_Node)
	testing.expect(t, is_expr, "expected Expr_Node from $()")
	testing.expect_value(t, expr.expr, "form.name")
}

@(test)
test_parse_block_delimiter :: proc(t: ^testing.T) {
	// {} always produces Host_Block regardless of content.
	nodes, errs := _sp("<p>{form.name}</p>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	p := nodes[0].(Element_Node)
	_, is_block := p.children[0].(Host_Block)
	testing.expect(t, is_block, "expected Host_Block from {}")
}

// ---------------------------------------------------------------------------
// Template_Proc
// ---------------------------------------------------------------------------

@(test)
test_parse_template_proc_simple :: proc(t: ^testing.T) {
	src := "card :: template(p: ^Card_Props) {\n    <div></div>\n}"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)

	tp, ok := nodes[0].(Template_Proc)
	testing.expect(t, ok, "expected Template_Proc")
	testing.expect_value(t, tp.name, "card")
	testing.expect_value(t, tp.params, "p: ^Card_Props")
	testing.expect_value(t, tp.has_slot, false)
}

@(test)
test_parse_template_proc_with_slot :: proc(t: ^testing.T) {
	src := "card :: template(p: ^Card_Props) {\n    <div><slot /></div>\n}"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	tp := nodes[0].(Template_Proc)
	testing.expect_value(t, tp.has_slot, true)
}

@(test)
test_parse_template_proc_pure_odin_body :: proc(t: ^testing.T) {
	// A template with no element tokens — entire body in one Host_Text.
	src := "noop :: template() {\n    x := 42\n}\n"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	tp, ok := nodes[0].(Template_Proc)
	testing.expect(t, ok, "expected Template_Proc")
	testing.expect_value(t, tp.name, "noop")
	testing.expect_value(t, tp.params, "")
}

@(test)
test_parse_template_proc_with_prefix :: proc(t: ^testing.T) {
	// Odin code before the template declaration becomes an Host_Span prefix.
	src := "Foo :: struct { x: int }\n\nfoo :: template() {\n    <br />\n}"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 2)
	_, is_span := nodes[0].(Host_Span)
	testing.expect(t, is_span, "expected Host_Span prefix")
	_, is_tp := nodes[1].(Template_Proc)
	testing.expect(t, is_tp, "expected Template_Proc")
}

@(test)
test_parse_multiple_templates :: proc(t: ^testing.T) {
	src :=
		"a :: template() {\n    <div />\n}\n\nb :: template() {\n    <span />\n}\n"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Two Template_Procs; there may be Host_Span nodes between them.
	tp_count := 0
	for node in nodes {
		if _, ok := node.(Template_Proc); ok {
			tp_count += 1
		}
	}
	testing.expect_value(t, tp_count, 2)
}

@(test)
test_parse_template_body_element_kinds :: proc(t: ^testing.T) {
	src := "row :: template(p: ^Props) {\n    <ui.card title={p.t}><slot /></ui.card>\n}"
	nodes, errs := _sp(src)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	tp := nodes[0].(Template_Proc)
	testing.expect_value(t, tp.has_slot, true)

	// Find the ui.card Element_Node in the body.
	card_found := false
	for node in tp.body {
		if elem, ok := node.(Element_Node); ok {
			if elem.tag == "ui.card" {
				testing.expect_value(t, elem.kind, Tag_Kind.Component)
				testing.expect_value(t, len(elem.attrs), 1)
				testing.expect_value(t, elem.attrs[0].(Attr).is_dynamic, true)
				card_found = true
			}
		}
	}
	testing.expect(t, card_found, "ui.card element not found in body")
}

// ---------------------------------------------------------------------------
// Package-qualified tags (e.g. <ui.card />)
// ---------------------------------------------------------------------------

@(test)
test_parse_package_qualified_self_close :: proc(t: ^testing.T) {
	nodes, errs := _sp(`<ui.card />`)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 1)
	elem, ok := nodes[0].(Element_Node)
	testing.expect(t, ok, "expected Element_Node")
	testing.expect_value(t, elem.tag, "ui.card")
	testing.expect_value(t, elem.kind, Tag_Kind.Component)
	testing.expect_value(t, len(elem.attrs), 0)
	testing.expect_value(t, len(elem.children), 0)
}

@(test)
test_parse_package_qualified_with_attrs :: proc(t: ^testing.T) {
	nodes, errs := _sp(`<ui.card title="Hello" active={is_active} />`)
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem := nodes[0].(Element_Node)
	testing.expect_value(t, elem.tag, "ui.card")
	testing.expect_value(t, elem.kind, Tag_Kind.Component)
	testing.expect_value(t, len(elem.attrs), 2)
	pqa0 := elem.attrs[0].(Attr)
	testing.expect_value(t, pqa0.name, "title")
	testing.expect_value(t, pqa0.value, "Hello")
	testing.expect_value(t, pqa0.is_dynamic, false)
	pqa1 := elem.attrs[1].(Attr)
	testing.expect_value(t, pqa1.name, "active")
	testing.expect_value(t, pqa1.expr, "is_active")
	testing.expect_value(t, pqa1.is_dynamic, true)
}

@(test)
test_parse_package_qualified_with_children :: proc(t: ^testing.T) {
	nodes, errs := _sp("<ui.card><p>content</p></ui.card>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	elem, ok := nodes[0].(Element_Node)
	testing.expect(t, ok, "expected Element_Node")
	testing.expect_value(t, elem.tag, "ui.card")
	testing.expect_value(t, elem.kind, Tag_Kind.Component)
	testing.expect_value(t, len(elem.children), 1)
	child := elem.children[0].(Element_Node)
	testing.expect_value(t, child.tag, "p")
}

@(test)
test_parse_package_qualified_close_tag_matches :: proc(t: ^testing.T) {
	// Mismatched package-qualified close tag should produce an error.
	nodes, errs := _sp("<ui.card></ui.button>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect(t, len(errs) > 0, "expected parse error for mismatched package-qualified tags")
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

@(test)
test_parse_mismatched_tags :: proc(t: ^testing.T) {
	nodes, errs := _sp("<div></span>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect(t, len(errs) > 0, "expected at least one parse error")
}

@(test)
test_parse_tag_resolve_raw_vs_component :: proc(t: ^testing.T) {
	nodes, errs := _sp("<div></div><card></card>")
	defer delete(nodes)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(nodes), 2)

	div := nodes[0].(Element_Node)
	testing.expect_value(t, div.kind, Tag_Kind.Raw)

	card := nodes[1].(Element_Node)
	testing.expect_value(t, card.kind, Tag_Kind.Component)
}
