/*
	Odin host driver.

	Implements Host_Driver for the Odin language.

	This is the default driver used when no .weasel.json is present or when
	"host" is set to "odin".
*/
package transpiler

odin_driver :: proc() -> Host_Driver {
	return Host_Driver{
		is_template_start         = _odin_is_template_start,
		emit_signature            = _odin_emit_signature,
		emit_dynamic_attr         = _odin_emit_dynamic_attr,
		emit_raw_string           = _odin_emit_raw_string,
		emit_escaped_string       = _odin_emit_escaped_string,
		emit_children_open        = _odin_emit_children_open,
		emit_children_close       = _odin_emit_children_close,
		emit_component_call_close = _odin_emit_component_call_close,
		emit_epilogue             = _odin_emit_epilogue,
		emit_spread               = _odin_emit_spread,
		preamble_marker           = "package ",
	}
}

// Default preamble for Odin host output.
@(private = "package")
_odin_default_preamble := [2]string{
	`import "core:io"`,
	`import "lib:weasel"`,
}

// odin_transpile_options returns Transpile_Options pre-populated with the Odin
// default driver and preamble.  Use this for CLI and LSP when no .weasel.json
// is present (or when the host is explicitly "odin").
odin_transpile_options :: proc() -> Transpile_Options {
	return {
		driver   = odin_driver(),
		preamble = _odin_default_preamble[:],
	}
}

// ---------------------------------------------------------------------------
// Odin driver implementations
// ---------------------------------------------------------------------------

@(private = "package")
_odin_is_template_start :: proc(text: string) -> bool {
	_, found := _find_template_decl(text)
	return found
}

@(private = "package")
_odin_emit_signature :: proc(t: ^Template_Proc, e: ^_Emitter) {
	// name :: proc(w: io.Writer[, user-params][, children callback]) -> io.Error {
	_write_tracked(e, t.name, t.name_pos)
	_write(e, " :: proc(w: io.Writer")
	if len(t.params) > 0 {
		_write(e, ", ")
		_write_tracked(e, t.params, t.params_pos)
	}
	if t.has_slot {
		_write(e, ", children: proc(w: io.Writer) -> io.Error")
	}
	_write(e, ") -> io.Error {")
}

@(private = "package")
_odin_emit_dynamic_attr :: proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter) {
	_write(e, "fmt.wprint(")
	_write(e, w_param)
	_write(e, ", ")
	_write_tracked(e, expr, weasel_pos)
	_write(e, ")\n")
}

@(private = "package")
_odin_emit_raw_string :: proc(w_param, content: string, e: ^_Emitter) {
	_write(e, `weasel.write_raw_string(`)
	_write(e, w_param)
	_write(e, `, "`)
	_write_string_literal_content(e, content)
	_write(e, `") or_return`)
	_write_byte(e, '\n')
}

@(private = "package")
_odin_emit_escaped_string :: proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter) {
	_write(e, "weasel.write_escaped_string(")
	_write(e, w_param)
	_write(e, ", ")
	// weasel_pos is at the '$' of the $(…) delimiter; the expression
	// bytes start two bytes later (after '$(').
	_write_tracked(e, expr, advance_position(weasel_pos, "$("))
	_write(e, ") or_return\n")
}

@(private = "package")
_odin_emit_children_open :: proc(w_param: string, e: ^_Emitter) {
	_write(e, ", proc(")
	_write(e, w_param)
	_write(e, ": io.Writer) -> io.Error {\n")
}

@(private = "package")
_odin_emit_children_close :: proc(e: ^_Emitter) {
	_write(e, "return nil\n}")
}

@(private = "package")
_odin_emit_component_call_close :: proc(e: ^_Emitter) {
	_write(e, ") or_return\n")
}

@(private = "package")
_odin_emit_epilogue :: proc(e: ^_Emitter) {
	_write(e, "return nil\n}\n")
}

@(private = "package")
_odin_emit_spread :: proc(w_param, expr: string, e: ^_Emitter) {
	_write(e, "weasel.write_spread(")
	_write(e, w_param)
	_write(e, ", ")
	_write(e, expr)
	_write(e, ") or_return\n")
}
