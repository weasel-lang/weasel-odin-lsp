/*
	LSP position & URI rewriting.

	For LSP methods that carry positions, this file walks the decoded JSON
	payload and translates every Range / Position / Location between the
	editor's Weasel coordinate space and ols's generated-Odin coordinate
	space.  URIs belonging to known documents are likewise swapped between
	the original `.weasel` URI and its `.weasel.odin` shadow.

	The walker is driven by LSP *field names* (`range`, `selectionRange`,
	`targetRange`, …) rather than by method-specific shape matching.  That
	means the proxy handles vendor extensions automatically as long as they
	reuse the standard key names.  Unknown fields are recursed into so
	positions nested anywhere in the payload are still rewritten.

	When a Position / Range fails to translate (an Odin-only location with
	no Weasel origin, or a Weasel location that never emitted an Odin
	span) the field is replaced with `null`.  Array containers
	(Location[], Diagnostic[], DocumentHighlight[], TextEdit[]) are then
	post-filtered: any element whose "required" position field
	(`range`/`targetRange`) went null is dropped.  This matches the task's
	"positions that don't map back are dropped from the result" rule
	without encoding per-method shape knowledge.

	URIs that don't belong to a known document pass through unchanged —
	the proxy deliberately never rewrites references to unrelated files.
*/
package lsp

import "core:encoding/json"
import "core:strings"

import "../transpiler"

// _Rewrite_Direction picks which side of the translator to query.
_Rewrite_Direction :: enum {
	Weasel_To_Odin, // editor -> ols (request params)
	Odin_To_Weasel, // ols -> editor (response results, diagnostics)
}

// _Rewrite_Ctx bundles the per-message walker state.  `default_doc` is
// consulted for Position / Range fields that don't sit inside a
// URI-bearing container (e.g. Hover.range, DocumentHighlight.range).
// URI-bearing items temporarily override the document selection to
// whichever doc the URI resolves to, if any.
_Rewrite_Ctx :: struct {
	proxy:       ^Proxy,
	default_doc: ^Document,
	dir:         _Rewrite_Direction,
}

// _RANGE_FIELD_NAMES lists every LSP key whose value is a Range object.
// Adding a new key here covers both directions of rewriting.
@(private = "file")
_RANGE_FIELD_NAMES := []string{
	"range",
	"selectionRange",
	"targetRange",
	"targetSelectionRange",
	"originSelectionRange",
	"editRange",
	"fullRange",
	"insertRange",
	"replaceRange",
}

// _DROP_FIELD_NAMES are the Range fields whose failure to translate
// should drop the enclosing Array element.  These are the "the item is
// meaningless without this range" positions: Location.range,
// LocationLink.targetRange, DocumentHighlight.range, Diagnostic.range,
// TextEdit.range.  Array elements whose failure is in a non-drop field
// (e.g. an optional hover range embedded in some vendor array) survive
// with that field nulled.
@(private = "file")
_DROP_FIELD_NAMES := []string{
	"range",
	"targetRange",
}

@(private = "file")
_is_range_field :: proc(key: string) -> bool {
	for f in _RANGE_FIELD_NAMES {if key == f {return true}}
	return false
}

@(private = "file")
_is_drop_field :: proc(key: string) -> bool {
	for f in _DROP_FIELD_NAMES {if key == f {return true}}
	return false
}

// _rewrite_lsp_value walks v recursively and mutates it in place.  Top
// level callers (request params, response result, notification params)
// should wrap their value here; the walker handles nested objects and
// arrays autonomously.
_rewrite_lsp_value :: proc(v: ^json.Value, ctx: ^_Rewrite_Ctx) {
	#partial switch &vv in v^ {
	case json.Object:
		_rewrite_object(&vv, ctx)
	case json.Array:
		for i in 0 ..< len(vv) {
			_rewrite_lsp_value(&vv[i], ctx)
		}
		_filter_dropped(&vv)
	}
}

// _filter_dropped removes Array elements whose "required" range field
// was nulled by the walker.  Removed elements are destroyed so they
// don't leak; the Array's length is tightened to just the survivors.
@(private = "file")
_filter_dropped :: proc(arr: ^json.Array) {
	write := 0
	for i in 0 ..< len(arr) {
		if _is_dropped_item(arr[i]) {
			json.destroy_value(arr[i])
			continue
		}
		if write != i {arr[write] = arr[i]}
		write += 1
	}
	// `resize` is defined on ^[dynamic]T; transmute through the distinct
	// Array type to reuse it without duplicating the implementation.
	resize(cast(^[dynamic]json.Value)arr, write)
}

// _is_dropped_item returns true when v is an Object whose
// range/targetRange key exists and is json.Null — the sentinel left
// behind by a failed Range translation.
@(private = "file")
_is_dropped_item :: proc(v: json.Value) -> bool {
	obj, is_obj := v.(json.Object)
	if !is_obj {return false}
	for f in _DROP_FIELD_NAMES {
		if val, present := obj[f]; present {
			if _, is_null := val.(json.Null); is_null {return true}
		}
	}
	return false
}

@(private = "file")
_rewrite_object :: proc(obj: ^json.Object, ctx: ^_Rewrite_Ctx) {
	// If the object carries a URI, resolve it to a Document first so
	// nested Position / Range fields use the matching source map.  URI
	// rewriting itself happens below.
	saved_doc := ctx.default_doc
	defer ctx.default_doc = saved_doc

	if uri_val, has := obj["uri"]; has {
		if str, ok := uri_val.(json.String); ok {
			if doc, found := _resolve_uri_doc(ctx.proxy, string(str), ctx.dir); found {
				ctx.default_doc = doc
			}
		}
	}
	if uri_val, has := obj["targetUri"]; has {
		if str, ok := uri_val.(json.String); ok {
			if doc, found := _resolve_uri_doc(ctx.proxy, string(str), ctx.dir); found {
				ctx.default_doc = doc
			}
		}
	}

	// Capture keys up front so a destructive rewrite (e.g. replacing a
	// Range with null) doesn't invalidate map-iteration order across
	// implementations.
	keys := make([dynamic]string, 0, len(obj), context.temp_allocator)
	for k in obj {append(&keys, k)}

	for key in keys {
		val := obj[key]
		switch {
		case key == "uri" || key == "targetUri":
			_rewrite_uri_field(&val, ctx)
		case key == "position":
			_rewrite_position_field(&val, ctx)
		case key == "positions":
			_rewrite_positions_array_field(&val, ctx)
		case _is_range_field(key):
			_rewrite_range_field(&val, ctx)
		case:
			_rewrite_lsp_value(&val, ctx)
		}
		obj[key] = val
	}
}

// _resolve_uri_doc maps a URI to the corresponding Document for the
// given direction.  Returns (nil, false) for URIs the proxy doesn't
// own.
@(private = "file")
_resolve_uri_doc :: proc(
	p: ^Proxy,
	uri: string,
	dir: _Rewrite_Direction,
) -> (^Document, bool) {
	switch dir {
	case .Weasel_To_Odin:
		doc, ok := p.documents[uri]
		return doc, ok
	case .Odin_To_Weasel:
		weasel_uri, has_shadow := _odin_uri_to_weasel_uri(uri)
		if !has_shadow {return nil, false}
		doc, ok := p.documents[weasel_uri]
		return doc, ok
	}
	return nil, false
}

// _odin_uri_to_weasel_uri is the inverse of weasel_uri_to_odin_uri.  It
// strips the trailing `.odin` from a shadow URI and returns the
// underlying `.weasel` URI.  Non-shadow URIs return ("", false) and
// should be passed through untouched.
@(private = "file")
_odin_uri_to_weasel_uri :: proc(odin_uri: string) -> (string, bool) {
	if !strings.has_suffix(odin_uri, ".weasel.odin") {return "", false}
	return odin_uri[:len(odin_uri) - len(".odin")], true
}

// _rewrite_uri_field swaps a URI between its Weasel and Odin forms for
// URIs that belong to a known document.  Unknown URIs pass through
// unchanged (e.g. references to third-party Odin files).
@(private = "file")
_rewrite_uri_field :: proc(v: ^json.Value, ctx: ^_Rewrite_Ctx) {
	str, is_str := v.(json.String)
	if !is_str {return}
	switch ctx.dir {
	case .Weasel_To_Odin:
		doc, ok := ctx.proxy.documents[string(str)]
		if !ok {return}
		cloned := strings.clone(doc.odin_uri)
		delete(string(str))
		v^ = json.String(cloned)
	case .Odin_To_Weasel:
		weasel_uri, has_shadow := _odin_uri_to_weasel_uri(string(str))
		if !has_shadow {return}
		if _, known := ctx.proxy.documents[weasel_uri]; !known {return}
		cloned := strings.clone(weasel_uri)
		delete(string(str))
		v^ = json.String(cloned)
	}
}

// _rewrite_position_field translates a Position object.  On failure,
// replaces v with json.Null so the caller's filter logic can react.
@(private = "file")
_rewrite_position_field :: proc(v: ^json.Value, ctx: ^_Rewrite_Ctx) {
	if ctx.default_doc == nil {return}
	obj, ok := v.(json.Object)
	if !ok {return}
	lsp_line := _json_integer(obj["line"])
	lsp_char := _json_integer(obj["character"])

	got, mapped := _translate_position(ctx, lsp_line, lsp_char)
	if !mapped {
		json.destroy_value(v^)
		v^ = json.Null{}
		return
	}
	obj["line"] = json.Integer(i64(got.line - 1))
	obj["character"] = json.Integer(i64(got.col - 1))
}

@(private = "file")
_rewrite_positions_array_field :: proc(v: ^json.Value, ctx: ^_Rewrite_Ctx) {
	arr, ok := v.(json.Array)
	if !ok {return}
	for i in 0 ..< len(arr) {
		_rewrite_position_field(&arr[i], ctx)
	}
	// Prune nulls produced by failed translations.
	write := 0
	for i in 0 ..< len(arr) {
		if _, is_null := arr[i].(json.Null); is_null {
			continue
		}
		if write != i {arr[write] = arr[i]}
		write += 1
	}
	resize(cast(^[dynamic]json.Value)&arr, write)
	v^ = arr
}

// _rewrite_range_field translates a Range object's start and end
// Position fields together.  If either side fails to translate the
// whole Range is replaced with json.Null — a Range with a usable start
// but broken end (or vice versa) is worse than no range at all because
// it would display a misleading highlight.
@(private = "file")
_rewrite_range_field :: proc(v: ^json.Value, ctx: ^_Rewrite_Ctx) {
	if ctx.default_doc == nil {return}
	obj, ok := v.(json.Object)
	if !ok {return}
	start, has_start := obj["start"].(json.Object)
	end,   has_end   := obj["end"].(json.Object)
	if !has_start || !has_end {return}

	s_line := _json_integer(start["line"])
	s_char := _json_integer(start["character"])
	e_line := _json_integer(end["line"])
	e_char := _json_integer(end["character"])

	s_got, s_ok := _translate_position(ctx, s_line, s_char)
	e_got, e_ok := _translate_range_end(ctx, e_line, e_char)
	if !s_ok || !e_ok {
		json.destroy_value(v^)
		v^ = json.Null{}
		return
	}
	start["line"] = json.Integer(i64(s_got.line - 1))
	start["character"] = json.Integer(i64(s_got.col - 1))
	end["line"] = json.Integer(i64(e_got.line - 1))
	end["character"] = json.Integer(i64(e_got.col - 1))
}

// _translate_position maps an LSP `{line, character}` into a
// transpiler.Position in the destination coordinate space.  It converts
// LSP line/char to a byte offset against the source text, runs the
// translator, and returns the result in transpiler coordinates (1-based
// line/col).  The caller is responsible for subtracting 1 to get LSP
// 0-based output.
@(private = "file")
_translate_position :: proc(
	ctx: ^_Rewrite_Ctx,
	lsp_line, lsp_char: int,
) -> (transpiler.Position, bool) {
	pos := _lsp_to_transpiler_pos(_source_text(ctx.default_doc, ctx.dir), lsp_line, lsp_char)
	switch ctx.dir {
	case .Weasel_To_Odin:
		return weasel_to_odin(&ctx.default_doc.translator, pos)
	case .Odin_To_Weasel:
		return odin_to_weasel(&ctx.default_doc.translator, pos)
	}
	return {}, false
}

// _translate_range_end is the Range.end-specific translator.  LSP
// ranges are half-open so the end coincides with a span's exclusive
// end; the `_range_end` translator variants succeed in that boundary
// case where the regular interior-only `odin_to_weasel` /
// `weasel_to_odin` would return false.
@(private = "file")
_translate_range_end :: proc(
	ctx: ^_Rewrite_Ctx,
	lsp_line, lsp_char: int,
) -> (transpiler.Position, bool) {
	pos := _lsp_to_transpiler_pos(_source_text(ctx.default_doc, ctx.dir), lsp_line, lsp_char)
	switch ctx.dir {
	case .Weasel_To_Odin:
		return weasel_to_odin_range_end(&ctx.default_doc.translator, pos)
	case .Odin_To_Weasel:
		return odin_to_weasel_range_end(&ctx.default_doc.translator, pos)
	}
	return {}, false
}

// _source_text returns the source text associated with the *input*
// coordinate space of the current direction — the Weasel source for
// request rewriting, the generated Odin source for response rewriting.
// It's used to convert LSP line/character (which is UTF-16 code units
// per spec but bytes in our simplification) into a byte offset.
@(private = "file")
_source_text :: proc(doc: ^Document, dir: _Rewrite_Direction) -> string {
	if doc == nil {return ""}
	switch dir {
	case .Weasel_To_Odin: return doc.weasel_text
	case .Odin_To_Weasel: return doc.odin_text
	}
	return ""
}

// _json_integer is a permissive variant of the shape the LSP spec
// pins down as integer.  Odin's JSON parser may hand back Integer or
// Float depending on the input form; treat both uniformly rather than
// trusting the parser's spec choice.  Missing / non-numeric values
// return 0, which is the correct default for LSP line / character.
@(private = "file")
_json_integer :: proc(v: json.Value) -> int {
	#partial switch x in v {
	case json.Integer: return int(x)
	case json.Float:   return int(x)
	}
	return 0
}

// _lsp_to_transpiler_pos walks text byte-by-byte to convert an LSP
// `{line, character}` pair to a transpiler.Position (offset +
// 1-based line/col).  The transpiler's internal model is 1-based so
// every consumer adds 1 to LSP's 0-based inputs on the way in and
// subtracts 1 on the way out.  Lines past EOF clamp to len(text);
// characters past EOL clamp to that line's end.
_lsp_to_transpiler_pos :: proc(text: string, lsp_line, lsp_char: int) -> transpiler.Position {
	off := 0
	for cur_line := 0; cur_line < lsp_line && off < len(text); off += 1 {
		if text[off] == '\n' {cur_line += 1}
	}
	line_end := off
	for line_end < len(text) && text[line_end] != '\n' {line_end += 1}
	col_off := min(lsp_char, line_end - off)
	return transpiler.Position{
		offset = off + col_off,
		line = lsp_line + 1,
		col = lsp_char + 1,
	}
}
