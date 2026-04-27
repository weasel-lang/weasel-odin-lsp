package transpiler

import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// C3 driver unit tests
// ---------------------------------------------------------------------------

@(private = "file")
_spt_c3 :: proc(source: string) -> (string, [dynamic]Transpile_Error) {
	tokens, scan_errs := scan(source)
	defer delete(scan_errs)
	defer delete(tokens)
	nodes, parse_errs := parse(tokens[:])
	defer delete(parse_errs)
	defer delete(nodes)
	source_out, smap, errs := transpile(nodes[:], c3_transpile_options())
	source_map_destroy(&smap)
	return source_out, errs
}

@(test)
test_c3_template_no_params :: proc(t: ^testing.T) {
	src, errs := _spt_c3("module views;\n\ngreet :: template() {\n    <p>Hello</p>\n}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, strings.contains(src, "module views;"), "module declaration preserved")
	testing.expect(t, strings.contains(src, "import std::io;"), "preamble injected after module")
	testing.expect(t, strings.contains(src, "import weasel;"), "weasel import injected")
	testing.expect(t, strings.contains(src, "fn void! greet(OutStream* w)"), "C3 function signature emitted")
	testing.expect(t, strings.contains(src, `io::fwrite_str(w, "<p>")!`), "C3 open tag emitted")
	testing.expect(t, strings.contains(src, `io::fwrite_str(w, "Hello")!`), "C3 text content emitted")
	testing.expect(t, strings.contains(src, `io::fwrite_str(w, "</p>")!`), "C3 close tag emitted")
	// Epilogue: just closing brace, no return statement
	testing.expect(t, strings.contains(src, "}\n"), "function closed")
}

@(test)
test_c3_template_preamble_after_module :: proc(t: ^testing.T) {
	src, errs := _spt_c3("module myapp;\n\nhello :: template() {\n    <span>hi</span>\n}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	module_pos := strings.index(src, "module myapp;")
	import_pos := strings.index(src, "import std::io;")
	fn_pos     := strings.index(src, "fn void! hello")

	testing.expect(t, module_pos >= 0, "module declaration present")
	testing.expect(t, import_pos >= 0, "preamble present")
	testing.expect(t, fn_pos >= 0, "function signature present")
	testing.expect(t, module_pos < import_pos, "preamble comes after module declaration")
	testing.expect(t, import_pos < fn_pos, "imports come before function")
}

@(test)
test_c3_template_with_params :: proc(t: ^testing.T) {
	src, errs := _spt_c3("module views;\n\ncard :: template(p: Card*) {\n    <div></div>\n}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, strings.contains(src, "fn void! card(OutStream* w, p: Card*)"), "params included in C3 signature")
}

@(test)
test_c3_escaped_expression :: proc(t: ^testing.T) {
	src, errs := _spt_c3("module views;\n\nshow :: template(name: char*) {\n    <p>$(name)</p>\n}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, strings.contains(src, "weasel::write_escaped(w, name)!"), "C3 escaped write emitted")
}

@(test)
test_c3_component_call :: proc(t: ^testing.T) {
	src, errs := _spt_c3("module views;\n\nouter :: template() {\n    <inner />\n}\n\ninner :: template() {\n    <span>x</span>\n}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, strings.contains(src, "inner(w)!\n"), "C3 component call uses ! suffix")
}

@(test)
test_c3_no_template_no_preamble :: proc(t: ^testing.T) {
	// Plain C3 passthrough without any template proc must NOT inject preamble.
	src, errs := _spt_c3("module views;\n\nfn void hello() {}\n")
	defer delete(errs)
	defer delete(transmute([]u8)src)

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, !strings.contains(src, "import std::io;"), "no preamble without template")
}

@(test)
test_c3_driver_config_from_json :: proc(t: ^testing.T) {
	json := `{"host":"c3"}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, cfg.host, "c3")
	testing.expect_value(t, cfg.lsp_binary, "c3-lsp")
	testing.expect(t, len(cfg.preamble) == 2, "C3 default preamble has 2 lines")
	testing.expect(t, strings.contains(cfg.preamble[0], "std::io"), "C3 preamble line 0 contains io")
	testing.expect(t, strings.contains(cfg.preamble[1], "weasel"), "C3 preamble line 1 contains weasel")
}
