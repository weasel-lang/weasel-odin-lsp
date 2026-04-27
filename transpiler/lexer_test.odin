package transpiler

import "core:testing"

@(test)
test_pure_odin_passthrough :: proc(t: ^testing.T) {
	tokens, errs := scan("x := 42\n")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 2) // OdinText + EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Host_Text)
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
test_expr_simple :: proc(t: ^testing.T) {
	// $(expr) emits Expr_Open (value=inner) + Expr_Close
	tokens, errs := scan("<h2>$(p.title)</h2>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open Expr_Open Expr_Close Element_Close EOF
	testing.expect_value(t, len(tokens), 5)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "h2")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Expr_Open)
	testing.expect_value(t, tokens[1].value, "p.title")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Expr_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[3].value, "h2")
	testing.expect_value(t, tokens[4].kind, Token_Kind.EOF)
}

@(test)
test_expr_nested_parens :: proc(t: ^testing.T) {
	// Nested parentheses inside $() must not close the expression early.
	tokens, errs := scan("<p>$(fmt.tprintf(\"%v\", x))</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Expr_Open)
	testing.expect_value(t, tokens[1].value, `fmt.tprintf("%v", x)`)
	testing.expect_value(t, tokens[2].kind, Token_Kind.Expr_Close)
}

@(test)
test_expr_paren_inside_string :: proc(t: ^testing.T) {
	// ')' inside a string literal must not close the expression.
	tokens, errs := scan("<p>$(f(\")\"))</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Expr_Open)
	testing.expect_value(t, tokens[1].value, `f(")")`)
	testing.expect_value(t, tokens[2].kind, Token_Kind.Expr_Close)
}

@(test)
test_expr_close_position :: proc(t: ^testing.T) {
	// Expr_Close.pos must point at the ')' character.
	tokens, errs := scan("<p>$(x)</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// <p> is 3 chars, $( is 2 chars, x is 1 char → ')' is at offset 6, col 7
	testing.expect_value(t, tokens[2].kind, Token_Kind.Expr_Close)
	testing.expect_value(t, tokens[2].pos.offset, 6)
}

@(test)
test_block_simple :: proc(t: ^testing.T) {
	// {block} emits Block_Open (value=inner) + Block_Close
	tokens, errs := scan("<h2>{p.title}</h2>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open Block_Open Block_Close Element_Close EOF
	testing.expect_value(t, len(tokens), 5)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "h2")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, "p.title")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[3].value, "h2")
	testing.expect_value(t, tokens[4].kind, Token_Kind.EOF)
}

@(test)
test_block_with_nested_braces :: proc(t: ^testing.T) {
	// Nested braces inside {} must not close the block early.
	tokens, errs := scan("<p>{fmt.tprintf(\"%v\", x)}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, `fmt.tprintf("%v", x)`)
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
}

@(test)
test_block_brace_inside_string :: proc(t: ^testing.T) {
	// `{` and `}` inside a string literal must not affect brace depth.
	tokens, errs := scan("<p>{f(\"{}\")}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, `f("{}")`)
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
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
	testing.expect_value(t, tokens[0].kind, Token_Kind.Host_Text)
	testing.expect_value(t, tokens[0].value, "before := 1\n")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[1].value, "div")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[2].value, "div")
	testing.expect_value(t, tokens[3].kind, Token_Kind.Host_Text)
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
test_block_captures_nested_elements_verbatim :: proc(t: ^testing.T) {
	// Nested elements inside a {…} block are captured verbatim; the parser recurses into them.
	src := "<ul>{for x in items {\n<li/>\n}}</ul>"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open Block_Open Block_Close Element_Close EOF
	testing.expect_value(t, len(tokens), 5)
	testing.expect_value(t, tokens[0].kind, Token_Kind.Element_Open)
	testing.expect_value(t, tokens[0].value, "ul")
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, "for x in items {\n<li/>\n}")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.Element_Close)
	testing.expect_value(t, tokens[3].value, "ul")
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
test_block_backtick_string :: proc(t: ^testing.T) {
	// Raw string literals with embedded braces must not affect block depth.
	tokens, errs := scan("<p>{f(`{hello}`)}</p>")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, "f(`{hello}`)")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
}

@(test)
test_block_line_comment :: proc(t: ^testing.T) {
	// Brace after // comment should not affect block depth.
	src := "<p>{x // }\n+ y}</p>"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[1].value, "x // }\n+ y")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Block_Close)
}

@(test)
test_dollar_sign_in_odin_passthrough :: proc(t: ^testing.T) {
	// '$' at depth 0 (outside element bodies) is plain Odin text.
	tokens, errs := scan("x := $(foo)\n")
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	testing.expect_value(t, len(tokens), 2) // OdinText + EOF
	testing.expect_value(t, tokens[0].kind, Token_Kind.Host_Text)
}

@(test)
test_expr_and_block_mixed :: proc(t: ^testing.T) {
	// A single element body can contain both $() expressions and {} blocks.
	src := "<p>$(name){if true { <span /> }}</p>"
	tokens, errs := scan(src)
	defer delete(tokens)
	defer delete(errs)

	testing.expect_value(t, len(errs), 0)
	// Element_Open Expr_Open Expr_Close Block_Open Block_Close Element_Close EOF
	testing.expect_value(t, len(tokens), 7)
	testing.expect_value(t, tokens[1].kind, Token_Kind.Expr_Open)
	testing.expect_value(t, tokens[1].value, "name")
	testing.expect_value(t, tokens[2].kind, Token_Kind.Expr_Close)
	testing.expect_value(t, tokens[3].kind, Token_Kind.Block_Open)
	testing.expect_value(t, tokens[3].value, "if true { <span /> }")
	testing.expect_value(t, tokens[4].kind, Token_Kind.Block_Close)
}
