/*
	Host driver interface.

	Host_Driver encapsulates everything that varies between host languages
	(Odin, C3, C++, …): how to emit template signatures, write calls, error
	propagation, children callbacks, and the preamble injection point.

	Each built-in driver is a plain function returning a Host_Driver value.
	The transpiler calls the driver procs directly instead of having host-
	language specifics hardcoded.

	Per-host default config values (write symbols, preamble lines, LSP binary)
	are constants in each driver file and are not part of the Host_Driver
	interface; they are consulted by the config loader separately.
*/
package transpiler

// Host_Driver encapsulates all host-language-specific emission logic.
//
// Proc fields are called by the transpiler wherever a host-language choice
// would otherwise be hardcoded.  String fields are simple per-host values
// used verbatim by the emitter.
//
// Proc field semantics:
//
//   is_template_start       — true when the given token slice (rooted at a
//                             Host_Text token's value) begins a template
//                             declaration for this host.  Wraps the marker
//                             search so different hosts can use different
//                             declaration syntax (e.g. C3 "fn" vs Odin "::").
//
//   emit_signature          — emits the complete function header for a
//                             Template_Proc, from the name through the opening
//                             '{'.  Owns the writer param, user params,
//                             optional children param, and return type.
//
//   emit_dynamic_attr       — emits the call that writes a dynamic attribute
//                             value.  Odin: `fmt.wprint(w, expr)`.
//
//   emit_raw_string         — emits a raw (un-escaped) string write call,
//                             including the error-propagation suffix and
//                             trailing newline.  `content` is the raw HTML
//                             text that will appear inside the string literal.
//                             Odin: `weasel.write_raw_string(w, "content") or_return\n`
//
//   emit_escaped_string     — emits an HTML-escaped expression write call.
//                             `expr` is the raw host expression string.
//                             Odin: `weasel.write_escaped_string(w, expr) or_return\n`
//
//   emit_children_open      — emits the start of the anonymous children
//                             callback at a component call site.
//                             Odin: `, proc(w: io.Writer) -> io.Error {\n`
//
//   emit_children_close     — emits the end of the anonymous children
//                             callback.  Odin: `return nil\n}`
//
//   emit_epilogue           — emits the template function epilogue (return
//                             statement and closing brace).
//                             Odin: `return nil\n}\n`
//
//   emit_spread             — emits a call that writes a spread attribute bag
//                             to the writer.  expr is the raw host expression
//                             of type weasel.Attributes (or host equivalent).
//                             Odin: `weasel.write_spread(w, expr) or_return\n`
//
//   preamble_marker         — prefix of the module/package declaration line
//                             after which the preamble is injected.
//                             Odin: `"package "`.
Host_Driver :: struct {
	is_template_start:          proc(text: string) -> bool,
	emit_signature:             proc(t: ^Template_Proc, e: ^_Emitter),
	emit_dynamic_attr:          proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter),
	emit_raw_string:            proc(w_param, content: string, e: ^_Emitter),
	emit_escaped_string:        proc(w_param, expr: string, weasel_pos: Position, e: ^_Emitter),
	emit_children_open:         proc(w_param: string, e: ^_Emitter),
	emit_children_close:        proc(e: ^_Emitter),
	emit_component_call_close:  proc(e: ^_Emitter), // emits `) <error-suffix>\n`
	emit_epilogue:              proc(e: ^_Emitter),
	emit_spread:                proc(w_param, expr: string, e: ^_Emitter),
	preamble_marker:            string, // prefix of the module/package declaration line
}

// Transpile_Options parameterises a transpile() call with a host driver and
// preamble lines.  The driver owns all host-language-specific emission logic.
// The preamble is injected unconditionally after the module/package declaration
// line; pass a nil or empty slice to suppress injection.
Transpile_Options :: struct {
	driver:   Host_Driver,
	preamble: []string, // lines injected after the module/package declaration
}
