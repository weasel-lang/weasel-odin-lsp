/*
	C3 host driver.

	Implements Host_Driver for the C3 language (https://c3-lang.org).

	Key differences from the Odin driver:
	  - Module declaration uses `module name;` (preamble_marker = "module ")
	  - Functions declared as `fn void! name(OutStream* w, ...) { ... }`
	  - Error propagation uses `!` suffix instead of `or_return`
	  - Children callbacks are anonymous fn literals: `fn void!(OutStream* w) { ... }`
	  - Raw string writes: `io::fwrite_str(w, "content")!`
	  - Escaped expression writes: `weasel::write_escaped(w, expr)!`
*/
package transpiler

import "core:strings"

c3_driver :: proc() -> Host_Driver {
	return Host_Driver{
		is_template_start           = _c3_is_template_start,
		emit_signature              = _c3_emit_signature,
		emit_dynamic_attr           = _c3_emit_dynamic_attr,
		emit_raw_string             = _c3_emit_raw_string,
		emit_escaped_string         = _c3_emit_escaped_string,
		emit_children_open          = _c3_emit_children_open,
		emit_children_close         = _c3_emit_children_close,
		emit_component_call_close   = _c3_emit_component_call_close,
		emit_epilogue               = _c3_emit_epilogue,
		emit_spread                 = _c3_emit_spread,
		preamble_marker             = "module ",
	}
}

// Default preamble for C3 host output.
@(private = "package")
_c3_default_preamble := [2]string{
	`import std::io;`,
	`import weasel;`,
}

// c3_transpile_options returns Transpile_Options pre-populated with the C3
// default driver and preamble.
c3_transpile_options :: proc() -> Transpile_Options {
	return {
		driver   = c3_driver(),
		preamble = _c3_default_preamble[:],
	}
}

// c3_default_weasel_config returns Weasel_Config for C3 defaults.
c3_default_weasel_config :: proc(allocator := context.allocator) -> Weasel_Config {
	preamble := make([]string, len(_c3_default_preamble), allocator)
	for line, i in _c3_default_preamble {
		preamble[i] = strings.clone(line, allocator)
	}
	return Weasel_Config{
		host       = strings.clone("c3", allocator),
		preamble   = preamble,
		lsp_binary = strings.clone("c3-lsp", allocator),
		lsp_args   = nil,
	}
}

// ---------------------------------------------------------------------------
// C3 driver implementations
// ---------------------------------------------------------------------------

@(private = "package")
_c3_is_template_start :: proc(text: string) -> bool {
	// C3 Weasel sources use the same `name :: template(...)` syntax as Odin.
	_, found := _find_template_decl(text)
	return found
}

@(private = "package")
_c3_emit_signature :: proc(t: ^Template_Proc, e: ^_Emitter) {
	// fn void! name(OutStream* w[, user-params][, children]) {
	_write(e, "fn void! ")
	_write_tracked(e, t.name, t.name_pos)
	_write(e, "(OutStream* w")
	if len(t.params) > 0 {
		_write(e, ", ")
		_write_tracked(e, t.params, t.params_pos)
	}
	if t.has_slot {
		_write(e, ", fn void!(OutStream*) children")
	}
	_write(e, ") {")
}

@(private = "package")
_c3_emit_dynamic_attr :: proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter) {
	_write(e, "io::fprint(")
	_write(e, w_param)
	_write(e, ", ")
	_write_tracked(e, expr, weasel_pos)
	_write(e, ")!\n")
}

@(private = "package")
_c3_emit_raw_string :: proc(w_param, content: string, e: ^_Emitter) {
	_write(e, `io::fwrite_str(`)
	_write(e, w_param)
	_write(e, `, "`)
	_write_string_literal_content(e, content)
	_write(e, `")!`)
	_write_byte(e, '\n')
}

@(private = "package")
_c3_emit_escaped_string :: proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter) {
	_write(e, "weasel::write_escaped(")
	_write(e, w_param)
	_write(e, ", ")
	_write_tracked(e, expr, advance_position(weasel_pos, "$("))
	_write(e, ")!\n")
}

@(private = "package")
_c3_emit_children_open :: proc(w_param: string, e: ^_Emitter) {
	_write(e, ", fn void!(OutStream* ")
	_write(e, w_param)
	_write(e, ") {\n")
}

@(private = "package")
_c3_emit_children_close :: proc(e: ^_Emitter) {
	_write(e, "}")
}

@(private = "package")
_c3_emit_component_call_close :: proc(e: ^_Emitter) {
	_write(e, ")!\n")
}

@(private = "package")
_c3_emit_epilogue :: proc(e: ^_Emitter) {
	_write(e, "}\n")
}

@(private = "package")
_c3_emit_spread :: proc(w_param, expr: string, e: ^_Emitter) {
	_write(e, "weasel::write_spread(")
	_write(e, w_param)
	_write(e, ", ")
	_write(e, expr)
	_write(e, ")!\n")
}
