package transpiler

import "core:testing"

@(test)
test_pure_odin_passthrough :: proc(t: ^testing.T) {
	tokens, errs := scan("x := 42\n")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 2) // OdinText + EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Odin_Text)
	testing.expect_value(t, tokens[0].value, "x := 42\n")
	testing.expect_value(t, tokens[1].kind, Token_Kind.EOF)
}

@(test)
test_self_close_no_attrs :: proc(t: ^testing.T) {
	tokens, errs := scan("<br />")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 3) // Element_Open SelfClose EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "br")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Self_Close)
	testing.expect_value(t, tokens[2].kind, Token_Kind.EOF)
}

@(test)
test_self_close_static_attr :: proc(t: ^testing.T) {
	tokens, errs := scan(`<input type="text" />`)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 4) // Element_Open AttrStatic SelfClose EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "input")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Attr_Static)
	testing.expect_value(t, tokens[1].value, "type")
	testing.expect_value(t, tokens[1].extra, "text")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Self_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.EOF)
}

@(test)
test_self_close_dynamic_attr :: proc(t: ^testing.T) {
	tokens, errs := scan(`<task_item task={task} />`)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 4) // Element_Open AttrDynamic SelfClose EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "task_item")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Attr_Dynamic)
	testing.expect_value(t, tokens[1].value, "task")
	testing.expect_value(t, tokens[1].extra, "task")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Self_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.EOF)
}

@(test)
test_open_inline_expr_close :: proc(t: ^testing.T) {
	tokens, errs := scan("<h2>{p.title}</h2>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 4) // Element_Open InlineExpr Element_Close EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "h2")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, "p.title")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[2].value, "h2")
	testing.expect_value(t, tokens[3].kind, Token_Kind.EOF)
}

@(test)
test_nested_braces_in_inline_expr :: proc(t: ^testing.T) {
	// Brace inside a call argument: closing arg brace must NOT end the InlineExpr.
	tokens, errs := scan("<p>{fmt.tprintf(\"%v\", x)}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, `fmt.tprintf("%v", x)`)
}

@(test)
test_brace_inside_string_in_inline_expr :: proc(t: ^testing.T) {
	// `{` and `}` inside a string literal must not affect brace depth.
	tokens, errs := scan("<p>{f(\"{}\")}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, `f("{}")`)
}

@(test)
test_odin_text_before_and_after :: proc(t: ^testing.T) {
	src := "before := 1\n<div></div>\nafter := 2\n"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// OdinText Element_Open Element_Close OdinText EOF
	testing.expect_value(t, len(tokens), 5)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Odin_Text)
	testing.expect_value(t, tokens[0].value, "before := 1\n")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[1].value, "div")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[2].value, "div")
	testing.expect_value(t, tokens[3].kind, Token_Kind.Odin_Text)
	testing.expect_value(t, tokens[3].value, "\nafter := 2\n")
}

@(test)
test_package_qualified_tag :: proc(t: ^testing.T) {
	tokens, errs := scan(`<ui.card title="Hello" />`)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "ui.card")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Attr_Static)
	testing.expect_value(t, tokens[1].extra, "Hello")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Self_Close)
}

@(test)
test_inline_expr_captures_nested_elements_verbatim :: proc(t: ^testing.T) {
	// Nested elements inside {…} are captured verbatim; the parser recurses into them.
	src := "<ul>{for x in items {\n<li/>\n}}</ul>"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open InlineExpr Element_Close EOF
	testing.expect_value(t, len(tokens), 4)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "ul")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, "for x in items {\n<li/>\n}")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[2].value, "ul")
}

@(test)
test_boolean_attribute :: proc(t: ^testing.T) {
	tokens, errs := scan("<input disabled />")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Attr_Static)
	testing.expect_value(t, tokens[1].value, "disabled")
	testing.expect_value(t, tokens[1].extra, "")
}

@(test)
test_multiple_attributes :: proc(t: ^testing.T) {
	tokens, errs := scan(`<a href="/" class={cls} hx-boost />`)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "a")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Attr_Static)
	testing.expect_value(t, tokens[1].value, "href")
	testing.expect_value(t, tokens[1].extra, "/")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Attr_Dynamic)
	testing.expect_value(t, tokens[2].value, "class")
	testing.expect_value(t, tokens[2].extra, "cls")
	testing.expect_value(t, tokens[3].kind, Token_Kind.Attr_Static)
	testing.expect_value(t, tokens[3].value, "hx-boost")
	testing.expect_value(t, tokens[3].extra, "")
	testing.expect_value(t, tokens[4].kind, Token_Kind.Self_Close)
}

@(test)
test_position_tracking :: proc(t: ^testing.T) {
	src := "line1\nline2\n<div />"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open starts on line 3, col 1
	testing.expect_value(t, tokens[1].pos.line, 3)
	testing.expect_value(t, tokens[1].pos.col, 1)
}

@(test)
test_backtick_string_in_inline_expr :: proc(t: ^testing.T) {
	// Raw string literals with embedded braces must not affect brace depth.
	tokens, errs := scan("<p>{f(`{hello}`)}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, "f(`{hello}`)")
}

@(test)
test_line_comment_in_inline_expr :: proc(t: ^testing.T) {
	// Brace after // comment should not affect depth.
	src := "<p>{x // }\n+ y}</p>"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Inline_Expr)
	testing.expect_value(t, tokens[1].value, "x // }\n+ y")
}
