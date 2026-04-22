package lsp

import "core:bytes"
import "core:encoding/json"
import "core:io"
import "core:slice"
import "core:strings"
import "core:testing"

import "../transpiler"

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

// _TR_Test bundles a test proxy and the helpers we need to drive
// ols→editor rewriting directly.  _Test_Proxy and the _send_editor /
// _drain helpers live in proxy_test.odin; we can reuse them through the
// package-level symbols here.
@(private = "file")
_TR_Test :: struct {
	proxy:      Proxy,
	ols_buf:    bytes.Buffer,
	editor_buf: bytes.Buffer,
}

@(private = "file")
_init :: proc(tp: ^_TR_Test) {
	bytes.buffer_init_allocator(&tp.ols_buf, 0, 256)
	bytes.buffer_init_allocator(&tp.editor_buf, 0, 256)
	proxy_init(
		&tp.proxy,
		bytes.buffer_to_stream(&tp.ols_buf),
		bytes.buffer_to_stream(&tp.editor_buf),
	)
}

@(private = "file")
_destroy :: proc(tp: ^_TR_Test) {
	proxy_destroy(&tp.proxy)
	bytes.buffer_destroy(&tp.ols_buf)
	bytes.buffer_destroy(&tp.editor_buf)
}

@(private = "file")
_send_editor_raw :: proc(tp: ^_TR_Test, body: string) -> Frame_Error {
	return proxy_process_editor_message(&tp.proxy, transmute([]u8)body)
}

@(private = "file")
_send_ols_raw :: proc(tp: ^_TR_Test, body: string) -> Frame_Error {
	return proxy_process_ols_message(&tp.proxy, transmute([]u8)body)
}

@(private = "file")
_drain_one :: proc(buf: ^bytes.Buffer) -> ([]u8, bool) {
	contents := bytes.buffer_to_bytes(buf)
	r: bytes.Reader
	stream := bytes.reader_init(&r, contents)
	reader := io.to_reader(stream)
	body, err := read_message(reader)
	if err != .None {
		if body != nil {delete(body)}
		bytes.buffer_reset(buf)
		return nil, false
	}
	bytes.buffer_reset(buf)
	return body, true
}

// _open_greet initialises the proxy with a didOpen for the canonical
// "greet" template used by the rewrite tests.  The template is small
// enough that its single span (the proc name) is predictable: Weasel
// offset 0 — line 0, char 0 — maps to Odin offset 0 at the start of
// the generated proc.
@(private = "file")
_open_greet :: proc(tp: ^_TR_Test) {
	body := `{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/g.weasel","languageId":"weasel","version":1,"text":"greet :: template() {\n}"}}}`
	proxy_process_editor_message(&tp.proxy, transmute([]u8)body)
	// Clear the synthesised ols frames and the publishDiagnostics echo
	// so subsequent tests see only their own traffic.
	bytes.buffer_reset(&tp.ols_buf)
	bytes.buffer_reset(&tp.editor_buf)
}

// _doc fetches the document under the standard test URI, failing the
// test if it's not there so later code can assume a non-nil doc.
@(private = "file")
_doc :: proc(t: ^testing.T, tp: ^_TR_Test) -> ^Document {
	doc, ok := tp.proxy.documents["file:///tmp/g.weasel"]
	testing.expect(t, ok, "greet document should be registered")
	return doc
}

// ---------------------------------------------------------------------------
// editor→ols request rewriting
// ---------------------------------------------------------------------------

// A hover request on a .weasel URI must forward to ols with the shadow
// .odin URI and a record of the pending request keyed by id.  Position
// translation for the "greet" proc name is identity (offset 0 on both
// sides) so the coordinates are preserved byte-for-byte.
@(test)
test_rewrite_hover_request_records_pending :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	req := `{"jsonrpc":"2.0","id":42,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/g.weasel"},"position":{"line":0,"character":0}}}`
	testing.expect_value(t, _send_editor_raw(&tp, req), Frame_Error.None)

	// Exactly one frame to ols.
	ol, ok := _drain_one(&tp.ols_buf)
	defer delete(ol)
	testing.expect(t, ok, "proxy should have forwarded a single frame")

	v, perr := json.parse(ol, parse_integers = true)
	defer json.destroy_value(v)
	testing.expect_value(t, perr, json.Error.None)
	obj, _ := v.(json.Object)
	method, _ := obj["method"].(json.String)
	testing.expect_value(t, string(method), "textDocument/hover")

	params, _ := obj["params"].(json.Object)
	td, _     := params["textDocument"].(json.Object)
	uri, _    := td["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/g.weasel.odin")

	pos, _ := params["position"].(json.Object)
	line, _ := pos["line"].(json.Integer)
	char, _ := pos["character"].(json.Integer)
	testing.expect_value(t, int(line), 0)
	testing.expect_value(t, int(char), 0)

	// Pending entry was recorded under "i:42".
	testing.expect_value(t, len(tp.proxy.pending), 1)
	entry, present := tp.proxy.pending["i:42"]
	testing.expect(t, present, "pending entry must exist for id 42")
	testing.expect_value(t, entry.method, "textDocument/hover")
	testing.expect_value(t, entry.weasel_uri, "file:///tmp/g.weasel")
}

// A request that targets a non-weasel URI must flow through untouched
// and not create a pending entry — the proxy has nothing to say about
// coordinates in someone else's file.
@(test)
test_rewrite_request_unrelated_uri_passthrough :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	req := `{"jsonrpc":"2.0","id":7,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/other.odin"},"position":{"line":3,"character":4}}}`
	testing.expect_value(t, _send_editor_raw(&tp, req), Frame_Error.None)

	ol, ok := _drain_one(&tp.ols_buf)
	defer delete(ol)
	testing.expect(t, ok, "proxy should have forwarded")
	testing.expect_value(t, string(ol), req)

	testing.expect_value(t, len(tp.proxy.pending), 0)
}

// ---------------------------------------------------------------------------
// ols→editor response rewriting
// ---------------------------------------------------------------------------

// A hover response from ols carries a range in Odin coordinates.  The
// proxy must rewrite it back to Weasel coordinates for the editor.
@(test)
test_rewrite_hover_response_translates_range :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	// Issue the request so the response has a pending entry to match.
	req := `{"jsonrpc":"2.0","id":9,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/g.weasel"},"position":{"line":0,"character":0}}}`
	testing.expect_value(t, _send_editor_raw(&tp, req), Frame_Error.None)
	bytes.buffer_reset(&tp.ols_buf)

	// ols sends back a Hover pointing at the "greet" token (Odin
	// offset 0..5).
	rsp := `{"jsonrpc":"2.0","id":9,"result":{"contents":"proc","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}}}}`
	testing.expect_value(t, _send_ols_raw(&tp, rsp), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the rewritten response")

	v, perr := json.parse(ed, parse_integers = true)
	defer json.destroy_value(v)
	testing.expect_value(t, perr, json.Error.None)
	obj, _ := v.(json.Object)
	id, _  := obj["id"].(json.Integer)
	testing.expect_value(t, int(id), 9)

	result, _ := obj["result"].(json.Object)
	rng, _    := result["range"].(json.Object)
	start, _  := rng["start"].(json.Object)
	end, _    := rng["end"].(json.Object)
	sl, _     := start["line"].(json.Integer)
	sc, _     := start["character"].(json.Integer)
	el, _     := end["line"].(json.Integer)
	ec, _     := end["character"].(json.Integer)
	testing.expect_value(t, int(sl), 0)
	testing.expect_value(t, int(sc), 0)
	testing.expect_value(t, int(el), 0)
	testing.expect_value(t, int(ec), 5)

	// Pending entry was consumed.
	testing.expect_value(t, len(tp.proxy.pending), 0)
}

// A go-to-definition response is a Location carrying both a URI and a
// range.  The URI is a shadow .odin; the proxy must translate it back
// to the .weasel URI and the range to Weasel coordinates.
@(test)
test_rewrite_definition_response_location :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	req := `{"jsonrpc":"2.0","id":11,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/g.weasel"},"position":{"line":0,"character":2}}}`
	testing.expect_value(t, _send_editor_raw(&tp, req), Frame_Error.None)
	bytes.buffer_reset(&tp.ols_buf)

	rsp := `{"jsonrpc":"2.0","id":11,"result":{"uri":"file:///tmp/g.weasel.odin","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}}}}`
	testing.expect_value(t, _send_ols_raw(&tp, rsp), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the rewritten definition")

	v, perr := json.parse(ed, parse_integers = true)
	defer json.destroy_value(v)
	testing.expect_value(t, perr, json.Error.None)
	obj, _    := v.(json.Object)
	result, _ := obj["result"].(json.Object)
	uri, _    := result["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/g.weasel")
}

// An Odin-only range in a response (scaffolding with no Weasel origin)
// must be dropped.  For a Location[] result that means filtering the
// entry out; for a single Location result we expect `null` in its
// place so the editor sees "no definition".
@(test)
test_rewrite_response_drops_unmappable_location :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	req := `{"jsonrpc":"2.0","id":12,"method":"textDocument/references","params":{"textDocument":{"uri":"file:///tmp/g.weasel"},"position":{"line":0,"character":0}}}`
	testing.expect_value(t, _send_editor_raw(&tp, req), Frame_Error.None)
	bytes.buffer_reset(&tp.ols_buf)

	// Two Locations: one inside the "greet" span (odin 0..5) and one
	// far past the end of the generated text (unmappable).
	rsp := `{"jsonrpc":"2.0","id":12,"result":[
		{"uri":"file:///tmp/g.weasel.odin","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}}},
		{"uri":"file:///tmp/g.weasel.odin","range":{"start":{"line":99,"character":0},"end":{"line":99,"character":3}}}
	]}`
	testing.expect_value(t, _send_ols_raw(&tp, rsp), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the filtered references")

	v, perr := json.parse(ed, parse_integers = true)
	defer json.destroy_value(v)
	testing.expect_value(t, perr, json.Error.None)
	obj, _    := v.(json.Object)
	result, _ := obj["result"].(json.Array)
	testing.expect_value(t, len(result), 1)

	loc, _ := result[0].(json.Object)
	uri, _ := loc["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/g.weasel")
}

// A response whose id we never tracked (either because the request
// wasn't a position-bearing one, or because it wasn't ours at all)
// must flow through unchanged.
@(test)
test_rewrite_response_unknown_id_passthrough :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	rsp := `{"jsonrpc":"2.0","id":1234,"result":{"capabilities":{}}}`
	testing.expect_value(t, _send_ols_raw(&tp, rsp), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the passthrough")
	testing.expect_value(t, string(ed), rsp)
}

// ---------------------------------------------------------------------------
// publishDiagnostics rewriting
// ---------------------------------------------------------------------------

// publishDiagnostics from ols targets the shadow .odin URI.  The proxy
// must rewrite the URI to the .weasel form and translate every
// diagnostic's range; diagnostics whose range doesn't map back are
// filtered out so the editor doesn't place squigglies on phantom lines.
@(test)
test_rewrite_publish_diagnostics_rewrites_uri_and_filters :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	notif := `{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///tmp/g.weasel.odin","diagnostics":[
		{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"severity":1,"message":"good one"},
		{"range":{"start":{"line":99,"character":0},"end":{"line":99,"character":3}},"severity":1,"message":"phantom"}
	]}}`
	testing.expect_value(t, _send_ols_raw(&tp, notif), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the rewritten diagnostics")

	v, perr := json.parse(ed, parse_integers = true)
	defer json.destroy_value(v)
	testing.expect_value(t, perr, json.Error.None)
	obj, _    := v.(json.Object)
	params, _ := obj["params"].(json.Object)
	uri, _    := params["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/g.weasel")

	diags, _ := params["diagnostics"].(json.Array)
	testing.expect_value(t, len(diags), 1)
	d0, _    := diags[0].(json.Object)
	msg, _   := d0["message"].(json.String)
	testing.expect_value(t, string(msg), "good one")
}

// publishDiagnostics for a URI we don't own is forwarded byte-for-byte.
@(test)
test_rewrite_publish_diagnostics_passthrough :: proc(t: ^testing.T) {
	tp: _TR_Test
	_init(&tp)
	defer _destroy(&tp)
	_open_greet(&tp)

	notif := `{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///tmp/other.odin","diagnostics":[]}}`
	testing.expect_value(t, _send_ols_raw(&tp, notif), Frame_Error.None)

	ed, ok := _drain_one(&tp.editor_buf)
	defer delete(ed)
	testing.expect(t, ok, "editor should receive the passthrough notification")
	testing.expect_value(t, string(ed), notif)
}

// ---------------------------------------------------------------------------
// Walker unit tests on a hand-built Source_Map
// ---------------------------------------------------------------------------

// Exercises the core walker fields: an Object with `range`, nested
// `position`, and a URI-like `uri` entry with a recognised shadow.  The
// hand-built Source_Map has one span so the translation math is easy
// to verify by hand.
@(test)
test_rewriter_walks_position_range_and_uri :: proc(t: ^testing.T) {
	// Stand up a Proxy with a single Document whose Translator is
	// built from one span: Weasel offset 0..5 ("greet") → Odin
	// offset 0..5 at line 1, col 1..6 on both sides.
	p: Proxy
	p.documents = make(map[string]^Document)
	defer delete(p.documents)

	sm := transpiler.Source_Map{
		entries = make([dynamic]transpiler.Span_Entry, 0, 1),
	}
	defer transpiler.source_map_destroy(&sm)
	append(&sm.entries, transpiler.Span_Entry{
		odin_start   = {offset = 0, line = 1, col = 1},
		odin_end     = {offset = 5, line = 1, col = 6},
		weasel_start = {offset = 0, line = 1, col = 1},
		weasel_end   = {offset = 5, line = 1, col = 6},
	})
	slice.sort_by(sm.entries[:], proc(a, b: transpiler.Span_Entry) -> bool {
		return a.odin_start.offset < b.odin_start.offset
	})
	tr := translator_make(&sm)
	defer translator_destroy(&tr)

	doc := new(Document)
	defer free(doc)
	defer delete(doc.weasel_uri)
	defer delete(doc.odin_uri)
	doc.weasel_uri = strings.clone("file:///tmp/x.weasel")
	doc.odin_uri   = strings.clone("file:///tmp/x.weasel.odin")
	doc.weasel_text = "greet"
	doc.odin_text   = "greet"
	doc.translator  = tr
	p.documents[doc.weasel_uri] = doc

	// Build a Location value to rewrite: shadow URI + exact range
	// around the "greet" span.
	body := `{"uri":"file:///tmp/x.weasel.odin","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}}}`
	v, _ := json.parse(transmute([]u8)body, parse_integers = true)
	defer json.destroy_value(v)

	ctx := _Rewrite_Ctx{
		proxy       = &p,
		default_doc = doc,
		dir         = .Odin_To_Weasel,
	}
	_rewrite_lsp_value(&v, &ctx)

	obj, _ := v.(json.Object)
	uri, _ := obj["uri"].(json.String)
	testing.expect_value(t, string(uri), "file:///tmp/x.weasel")

	// Range was a full-span match — coordinates survive unchanged but
	// having passed the translator proves the round-trip works.
	rng, _    := obj["range"].(json.Object)
	start, _  := rng["start"].(json.Object)
	sl, _     := start["line"].(json.Integer)
	sc, _     := start["character"].(json.Integer)
	testing.expect_value(t, int(sl), 0)
	testing.expect_value(t, int(sc), 0)
}

// A Position object whose coordinates don't land in any span becomes
// json.Null after walking.  The object around it is untouched by the
// walker itself; higher-level filters decide whether to drop it.
@(test)
test_rewriter_nulls_unmappable_position :: proc(t: ^testing.T) {
	p: Proxy
	p.documents = make(map[string]^Document)
	defer delete(p.documents)

	sm := transpiler.Source_Map{entries = make([dynamic]transpiler.Span_Entry, 0, 1)}
	defer transpiler.source_map_destroy(&sm)
	append(&sm.entries, transpiler.Span_Entry{
		odin_start   = {offset = 0, line = 1, col = 1},
		odin_end     = {offset = 5, line = 1, col = 6},
		weasel_start = {offset = 0, line = 1, col = 1},
		weasel_end   = {offset = 5, line = 1, col = 6},
	})
	tr := translator_make(&sm)
	defer translator_destroy(&tr)

	doc := new(Document)
	defer free(doc)
	doc.weasel_text = "greet"
	doc.odin_text   = "greet"
	doc.translator  = tr

	body := `{"position":{"line":99,"character":0}}`
	v, _ := json.parse(transmute([]u8)body, parse_integers = true)
	defer json.destroy_value(v)

	ctx := _Rewrite_Ctx{proxy = &p, default_doc = doc, dir = .Odin_To_Weasel}
	_rewrite_lsp_value(&v, &ctx)

	obj, _  := v.(json.Object)
	pos_val := obj["position"]
	_, is_null := pos_val.(json.Null)
	testing.expect(t, is_null, "unmappable position must be nulled")
}
