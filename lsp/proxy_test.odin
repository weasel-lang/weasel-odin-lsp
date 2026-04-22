package lsp

import "core:bytes"
import "core:encoding/json"
import "core:io"
import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

// _Test_Proxy wires a Proxy to two in-memory bytes.Buffers so tests can
// inspect what the proxy wrote toward ols / toward the editor.  Buffers
// expose an io.Writer via bytes.buffer_to_stream which is what the Proxy
// ultimately calls through write_message.
@(private = "file")
_Test_Proxy :: struct {
	proxy:      Proxy,
	ols_buf:    bytes.Buffer,
	editor_buf: bytes.Buffer,
}

@(private = "file")
_test_proxy_init :: proc(tp: ^_Test_Proxy) {
	bytes.buffer_init_allocator(&tp.ols_buf, 0, 256)
	bytes.buffer_init_allocator(&tp.editor_buf, 0, 256)
	proxy_init(
		&tp.proxy,
		bytes.buffer_to_stream(&tp.ols_buf),
		bytes.buffer_to_stream(&tp.editor_buf),
	)
}

@(private = "file")
_test_proxy_destroy :: proc(tp: ^_Test_Proxy) {
	proxy_destroy(&tp.proxy)
	bytes.buffer_destroy(&tp.ols_buf)
	bytes.buffer_destroy(&tp.editor_buf)
}

// _drain reads every framed message out of a bytes.Buffer and returns the
// bodies as cloned byte slices, then resets the buffer.  Without the reset
// the next write would leave old frames in place and subsequent drains
// would replay them — tests that split "everything from didOpen" vs "just
// this didChange" depend on the consume-and-clear semantics.
@(private = "file")
_drain :: proc(buf: ^bytes.Buffer) -> [dynamic][]u8 {
	out := make([dynamic][]u8)
	contents := bytes.buffer_to_bytes(buf)
	r: bytes.Reader
	stream := bytes.reader_init(&r, contents)
	reader := io.to_reader(stream)
	for {
		body, err := read_message(reader)
		if err == .EOF {break}
		if err != .None {
			if body != nil {delete(body)}
			break
		}
		append(&out, body)
	}
	bytes.buffer_reset(buf)
	return out
}

// _freed returns each element of a dynamic slice of byte slices to the
// allocator in a single helper to keep test bodies terse.
@(private = "file")
_free_bodies :: proc(bodies: [dynamic][]u8) {
	for b in bodies {delete(b)}
	delete(bodies)
}

// _decode parses one JSON body into an Object and returns it along with the
// backing Value (for subsequent destroy_value).  On failure the returned
// Object is empty and ok is false.
@(private = "file")
_decode :: proc(body: []u8) -> (v: json.Value, obj: json.Object, ok: bool) {
	parsed, err := json.parse(body, parse_integers = true)
	if err != .None {return parsed, {}, false}
	o, is_obj := parsed.(json.Object)
	if !is_obj {
		json.destroy_value(parsed)
		return {}, {}, false
	}
	return parsed, o, true
}

// _get_method / _get_text_document are small helpers that walk the
// { method, params: { textDocument: {...} } } shape common to every LSP
// notification we synthesize.
@(private = "file")
_get_method :: proc(obj: json.Object) -> string {
	m, _ := obj["method"].(json.String)
	return string(m)
}

@(private = "file")
_get_text_document :: proc(obj: json.Object) -> json.Object {
	params, _ := obj["params"].(json.Object)
	td,     _ := params["textDocument"].(json.Object)
	return td
}

// _send_editor sends one framed body into the proxy's editor-direction
// input and returns the Frame_Error.  The body is a literal JSON string.
@(private = "file")
_send_editor :: proc(tp: ^_Test_Proxy, body: string) -> Frame_Error {
	return proxy_process_editor_message(&tp.proxy, transmute([]u8)body)
}

// ---------------------------------------------------------------------------
// URI mapping
// ---------------------------------------------------------------------------

@(test)
test_proxy_uri_mapping_weasel :: proc(t: ^testing.T) {
	mapped, ok := weasel_uri_to_odin_uri("file:///tmp/foo.weasel")
	defer delete(mapped)
	testing.expect(t, ok, "weasel URI should map")
	testing.expect_value(t, mapped, "file:///tmp/foo.weasel.odin")
}

@(test)
test_proxy_uri_mapping_non_weasel :: proc(t: ^testing.T) {
	_, ok := weasel_uri_to_odin_uri("file:///tmp/foo.odin")
	testing.expect(t, !ok, ".odin URI must not map")
}

// ---------------------------------------------------------------------------
// didOpen
// ---------------------------------------------------------------------------

// A .weasel didOpen must: (a) register the document in the proxy, (b)
// synthesize a didOpen toward ols carrying the generated Odin text at the
// shadow .odin URI, and (c) publish a (possibly empty) diagnostics frame
// back to the editor.
@(test)
test_proxy_did_open_weasel :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	body := `{
		"jsonrpc": "2.0",
		"method": "textDocument/didOpen",
		"params": {
			"textDocument": {
				"uri": "file:///tmp/a.weasel",
				"languageId": "weasel",
				"version": 1,
				"text": "greet :: template() {\n}"
			}
		}
	}`
	testing.expect_value(t, _send_editor(&tp, body), Frame_Error.None)

	// One document in proxy state.
	testing.expect_value(t, len(tp.proxy.documents), 1)
	doc, found := tp.proxy.documents["file:///tmp/a.weasel"]
	testing.expect(t, found, "document must be registered")
	testing.expect(t, doc.last_good, "transpile should succeed on valid source")

	// Exactly one frame to ols: synthesized didOpen.
	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)

	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	testing.expect_value(t, _get_method(obj), "textDocument/didOpen")

	td := _get_text_document(obj)
	uri, _         := td["uri"].(json.String)
	language_id, _ := td["languageId"].(json.String)
	text, _        := td["text"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/a.weasel.odin")
	testing.expect_value(t, string(language_id), "odin")
	testing.expect(t, strings.contains(string(text), "greet"), "generated text should include template name")
	testing.expect(t, strings.contains(string(text), ":: proc"), "generated text should be Odin proc")

	// Editor direction: one publishDiagnostics frame with zero diagnostics.
	ed_bodies := _drain(&tp.editor_buf)
	defer _free_bodies(ed_bodies)
	testing.expect_value(t, len(ed_bodies), 1)

	ev, eobj, eok := _decode(ed_bodies[0])
	defer json.destroy_value(ev)
	testing.expect(t, eok, "editor body should parse")
	testing.expect_value(t, _get_method(eobj), "textDocument/publishDiagnostics")
	params, _ := eobj["params"].(json.Object)
	diags, _  := params["diagnostics"].(json.Array)
	testing.expect_value(t, len(diags), 0)
}

// Non-.weasel didOpens flow through untouched — the proxy must never steal
// messages for files it doesn't own.
@(test)
test_proxy_did_open_non_weasel_passthrough :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	body := `{
		"jsonrpc": "2.0",
		"method": "textDocument/didOpen",
		"params": {
			"textDocument": {
				"uri": "file:///tmp/a.odin",
				"languageId": "odin",
				"version": 1,
				"text": "package a"
			}
		}
	}`
	testing.expect_value(t, _send_editor(&tp, body), Frame_Error.None)

	// Document map unchanged.
	testing.expect_value(t, len(tp.proxy.documents), 0)

	// ols sees the original body verbatim.
	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)

	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	td := _get_text_document(obj)
	uri, _ := td["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/a.odin")

	// No editor-side traffic for a non-.weasel open.
	ed_bodies := _drain(&tp.editor_buf)
	defer _free_bodies(ed_bodies)
	testing.expect_value(t, len(ed_bodies), 0)
}

// ---------------------------------------------------------------------------
// didChange
// ---------------------------------------------------------------------------

// Full-document-sync didChange must re-transpile and resend the full new
// Odin text to ols.  The stored weasel_text must reflect the change.
@(test)
test_proxy_did_change_full_sync :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	open := `{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/a.weasel","languageId":"weasel","version":1,"text":"greet :: template() {\n}"}}}`
	testing.expect_value(t, _send_editor(&tp, open), Frame_Error.None)
	// Discard didOpen traffic so the didChange frames are the only ones left.
	_free_bodies(_drain(&tp.ols_buf))
	_free_bodies(_drain(&tp.editor_buf))

	change := `{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/a.weasel","version":2},"contentChanges":[{"text":"bye :: template() {\n}"}]}}`
	testing.expect_value(t, _send_editor(&tp, change), Frame_Error.None)

	doc := tp.proxy.documents["file:///tmp/a.weasel"]
	testing.expect_value(t, doc.version, 2)
	testing.expect_value(t, doc.weasel_text, "bye :: template() {\n}")
	testing.expect(t, strings.contains(doc.odin_text, "bye"), "odin_text should be regenerated")

	// ols sees a didChange with Full sync: contentChanges is a single
	// element with no `range` and text equal to the new Odin source.
	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)

	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	testing.expect_value(t, _get_method(obj), "textDocument/didChange")

	params, _ := obj["params"].(json.Object)
	td,     _ := params["textDocument"].(json.Object)
	uri,    _ := td["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/a.weasel.odin")

	changes, _ := params["contentChanges"].(json.Array)
	testing.expect_value(t, len(changes), 1)
	first, _ := changes[0].(json.Object)
	_, has_range := first["range"]
	testing.expect(t, !has_range, "proxy must send Full sync (no range)")
	ntext, _ := first["text"].(json.String)
	testing.expect(t, strings.contains(string(ntext), "bye"), "new text should include new template name")
}

// Incremental edits (range + text) must be applied to the stored weasel
// source before re-transpile.  Exercises the position→offset math on a
// multi-line buffer.
@(test)
test_proxy_did_change_incremental :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	open := `{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/a.weasel","languageId":"weasel","version":1,"text":"greet :: template() {\n}"}}}`
	testing.expect_value(t, _send_editor(&tp, open), Frame_Error.None)
	_free_bodies(_drain(&tp.ols_buf))
	_free_bodies(_drain(&tp.editor_buf))

	// Replace the five characters "greet" at line 0, columns 0..5 with "hello".
	change := `{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/a.weasel","version":2},"contentChanges":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"text":"hello"}]}}`
	testing.expect_value(t, _send_editor(&tp, change), Frame_Error.None)

	doc := tp.proxy.documents["file:///tmp/a.weasel"]
	testing.expect_value(t, doc.weasel_text, "hello :: template() {\n}")
	testing.expect(t, strings.contains(doc.odin_text, "hello"), "odin_text should reflect incremental edit")
	testing.expect(t, !strings.contains(doc.odin_text, "greet"), "old identifier must be gone")
}

// ---------------------------------------------------------------------------
// Transpile errors: last-good preservation
// ---------------------------------------------------------------------------

// A didChange that breaks the source must keep the previously-good
// odin_text around, forward that text to ols (so its session stays alive),
// and publish diagnostics to the editor.
@(test)
test_proxy_did_change_transpile_error_keeps_last_good :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	open := `{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/a.weasel","languageId":"weasel","version":1,"text":"greet :: template() {\n}"}}}`
	testing.expect_value(t, _send_editor(&tp, open), Frame_Error.None)
	_free_bodies(_drain(&tp.ols_buf))
	_free_bodies(_drain(&tp.editor_buf))

	doc := tp.proxy.documents["file:///tmp/a.weasel"]
	last_good_text := strings.clone(doc.odin_text)
	defer delete(last_good_text)

	// Break it: unterminated string inside an inline expression.  The
	// lexer flags `{"…` as an unterminated string literal.
	change := `{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/a.weasel","version":2},"contentChanges":[{"text":"greet :: template() {\n  <p>{\"oops</p>\n}"}]}}`
	testing.expect_value(t, _send_editor(&tp, change), Frame_Error.None)

	// odin_text is unchanged (still last-good).
	doc = tp.proxy.documents["file:///tmp/a.weasel"]
	testing.expect_value(t, doc.odin_text, last_good_text)
	testing.expect(t, doc.last_good, "last_good flag must remain true")

	// ols still received a didChange carrying the last-good text.
	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)
	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	params, _  := obj["params"].(json.Object)
	changes, _ := params["contentChanges"].(json.Array)
	first, _   := changes[0].(json.Object)
	ntext, _   := first["text"].(json.String)
	testing.expect_value(t, string(ntext), last_good_text)

	// Editor received a publishDiagnostics with at least one error.
	ed_bodies := _drain(&tp.editor_buf)
	defer _free_bodies(ed_bodies)
	testing.expect_value(t, len(ed_bodies), 1)
	ev, eobj, eok := _decode(ed_bodies[0])
	defer json.destroy_value(ev)
	testing.expect(t, eok, "editor body should parse")
	testing.expect_value(t, _get_method(eobj), "textDocument/publishDiagnostics")
	eparams, _ := eobj["params"].(json.Object)
	euri, _    := eparams["uri"].(json.String)
	testing.expect_value(t, string(euri), "file:///tmp/a.weasel")
	diags, _   := eparams["diagnostics"].(json.Array)
	testing.expect(t, len(diags) > 0, "diagnostics should be non-empty")
}

// ---------------------------------------------------------------------------
// didClose
// ---------------------------------------------------------------------------

// didClose must synthesize a matching didClose toward ols (with the shadow
// .odin URI) and drop all per-document state so a subsequent didOpen
// starts fresh.
@(test)
test_proxy_did_close :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	open := `{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/a.weasel","languageId":"weasel","version":1,"text":"greet :: template() {\n}"}}}`
	testing.expect_value(t, _send_editor(&tp, open), Frame_Error.None)
	_free_bodies(_drain(&tp.ols_buf))
	_free_bodies(_drain(&tp.editor_buf))

	close := `{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"file:///tmp/a.weasel"}}}`
	testing.expect_value(t, _send_editor(&tp, close), Frame_Error.None)

	testing.expect_value(t, len(tp.proxy.documents), 0)

	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)
	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	testing.expect_value(t, _get_method(obj), "textDocument/didClose")
	td := _get_text_document(obj)
	uri, _ := td["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/a.weasel.odin")
}

// ---------------------------------------------------------------------------
// Non-textDocument methods pass through
// ---------------------------------------------------------------------------

// A request like `initialize` has no textDocument semantics; the proxy must
// forward it verbatim rather than swallow or rewrite it.
@(test)
test_proxy_request_passthrough :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	body := `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`
	testing.expect_value(t, _send_editor(&tp, body), Frame_Error.None)

	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)
	v, obj, ok := _decode(ols_bodies[0])
	defer json.destroy_value(v)
	testing.expect(t, ok, "ols body should parse")
	testing.expect_value(t, _get_method(obj), "initialize")
}

// Bodies that don't parse as JSON still reach ols untouched — the proxy
// must not turn an unparseable message into a silent drop.
@(test)
test_proxy_unparseable_body_passthrough :: proc(t: ^testing.T) {
	tp: _Test_Proxy
	_test_proxy_init(&tp)
	defer _test_proxy_destroy(&tp)

	body := `not valid json at all`
	testing.expect_value(t, _send_editor(&tp, body), Frame_Error.None)

	ols_bodies := _drain(&tp.ols_buf)
	defer _free_bodies(ols_bodies)
	testing.expect_value(t, len(ols_bodies), 1)
	testing.expect_value(t, string(ols_bodies[0]), body)
}
