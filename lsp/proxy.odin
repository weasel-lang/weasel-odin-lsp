/*
	Proxy-side document lifecycle for the Weasel LSP.

	The editor talks to the proxy about `.weasel` files; the proxy keeps `ols`
	fed with the corresponding generated Odin text via synthesized
	`textDocument/didOpen` / `didChange` / `didSave` / `didClose` notifications.
	All transpilation is in-memory — `ols` never reads the `.odin` file from
	disk during normal editing.  `didSave` is the only path that writes the
	generated Odin to disk, and that is purely so the developer can open and
	inspect the shadow file; `ols`'s understanding of the document still comes
	from the live notification stream.

	State model:
	  - `Document` holds the per-URI state: Weasel source (owned), generated
	    Odin (last-good, owned), Source_Map and Translator, plus the LSP
	    version counter and language id the editor passed.
	  - `Proxy` is a dictionary of Documents keyed by the `.weasel` URI plus
	    the two io.Writers it funnels output through (toward `ols` and back
	    to the editor).

	Concurrency:
	  The proxy is touched from two threads: the editor→ols forwarder (which
	  calls `proxy_process_editor_message`) and the ols→editor forwarder
	  (which funnels every `ols` response through `proxy_write_to_editor`).
	  The editor-direction writer is serialised by `editor_write_mu` so
	  proxy-initiated diagnostics never interleave frames with forwarded
	  responses.  `ols_writer` has a single writer (the editor→ols thread),
	  so no mutex is needed there yet — T-0014 will revisit this when
	  position rewriting on the ols→editor direction is introduced.

	URI mapping:
	  `file:///…/foo.weasel` ↔ `file:///…/foo.weasel.odin`.  Appending the
	  suffix rather than replacing it keeps the original extension visible in
	  error messages and makes disk-side `.odin` files easy to identify as
	  generated artefacts.
*/
package lsp

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"

import "../transpiler"

// ---------------------------------------------------------------------------
// Per-document state
// ---------------------------------------------------------------------------

// Document is the proxy-side mirror of one open `.weasel` file.
//
// `weasel_text` is the authoritative source the proxy maintains: it is
// updated on every `didChange` (applying incremental edits when needed) and
// is what the transpiler consumes.  `odin_text`, `source_map`, and
// `translator` together are the most recent *successful* transpile result
// — we keep them around even after a broken keystroke so that `ols` keeps
// seeing a parseable document while the user types.  `last_good` flips to
// true the first time a transpile succeeds, which is how we distinguish
// "never parsed" (send an empty Odin document to `ols`) from "was good a
// moment ago" (send the last-good document).
Document :: struct {
	weasel_uri:  string,
	odin_uri:    string,
	language_id: string,
	version:     int,

	weasel_text: string,

	odin_text:   string,
	source_map:  transpiler.Source_Map,
	translator:  Translator,
	last_good:   bool,
}

// ---------------------------------------------------------------------------
// Proxy
// ---------------------------------------------------------------------------

// Proxy bundles the per-document state dictionary with the writers that
// carry framed messages to `ols` and back to the editor.  A single Proxy
// instance is shared between the two forwarder threads in the `weasel-lsp`
// binary.
//
// Thread model:
//   `state_mu` serialises access to `documents` and `pending` between
//   the editor→ols and ols→editor threads.  The editor-direction writer
//   is separately guarded by `editor_write_mu` so proxy-initiated
//   diagnostics never interleave frames with forwarded responses.
//   `ols_writer` has a single writer (the editor→ols thread), so no
//   mutex is needed there.
Proxy :: struct {
	documents: map[string]^Document,
	// pending correlates request id (stringified via _pending_key) with
	// the `.weasel` URI the editor addressed.  Populated when the
	// editor sends a position-bearing request, consumed when ols
	// responds.  Keeps the ols→editor direction able to look up the
	// right document's source map for a result.
	pending: map[string]Pending_Request,

	ols_writer:    io.Writer,
	editor_writer: io.Writer,

	state_mu:        sync.Mutex,
	editor_write_mu: sync.Mutex,
}

// Pending_Request captures the subset of editor-side context a
// response needs to be rewritten: which Weasel document the result
// positions are against (for position-only items that inherit the
// URI) and which method was invoked (for error logging and future
// method-specific nudges).  Both strings are owned by the Proxy.
Pending_Request :: struct {
	method:     string,
	weasel_uri: string,
}

// proxy_init prepares p.  The two writers must outlive the proxy.
proxy_init :: proc(p: ^Proxy, ols_writer, editor_writer: io.Writer) {
	p.documents = make(map[string]^Document)
	p.pending = make(map[string]Pending_Request)
	p.ols_writer = ols_writer
	p.editor_writer = editor_writer
}

// proxy_destroy releases every Document still tracked by p.  Call after
// both forwarder threads have stopped.
proxy_destroy :: proc(p: ^Proxy) {
	for _, doc in p.documents {
		_document_destroy(doc)
		free(doc)
	}
	delete(p.documents)
	p.documents = nil
	for k, pr in p.pending {
		delete(k)
		delete(pr.method)
		delete(pr.weasel_uri)
	}
	delete(p.pending)
	p.pending = nil
}

// proxy_write_to_editor serialises a framed write back to the editor.  Used
// both by the ols→editor forwarder (for responses from `ols`) and by the
// proxy itself (for `textDocument/publishDiagnostics` after a failed
// transpile) so frames never interleave on stdout.
proxy_write_to_editor :: proc(p: ^Proxy, body: []u8) -> Frame_Error {
	sync.mutex_lock(&p.editor_write_mu)
	defer sync.mutex_unlock(&p.editor_write_mu)
	return write_message(p.editor_writer, body)
}

// proxy_process_editor_message handles one framed JSON-RPC body coming from
// the editor.  For `.weasel` textDocument lifecycle notifications it
// synthesizes replacement messages toward `ols`; for requests addressed
// to a known `.weasel` document it rewrites Weasel coordinates to Odin
// before forwarding.  Everything else is forwarded verbatim.  A parse
// failure falls back to verbatim forwarding — we must never swallow a
// message we don't understand.
proxy_process_editor_message :: proc(p: ^Proxy, body: []u8) -> Frame_Error {
	sync.mutex_lock(&p.state_mu)
	defer sync.mutex_unlock(&p.state_mu)

	// Parse and hand off to the dispatcher.  The entire JSON tree is
	// allocated in a scratch arena-style block and freed via destroy_value
	// so we don't leak per-message state on the hot path.
	v, perr := json.parse(body, parse_integers = true)
	if perr != .None {
		// Unparseable message — preserve byte-for-byte passthrough so we
		// don't hide bugs from the editor.
		return write_message(p.ols_writer, body)
	}
	defer json.destroy_value(v)

	obj, ok := v.(json.Object)
	if !ok {
		return write_message(p.ols_writer, body)
	}

	method_val, has_method := obj["method"]
	if !has_method {
		// Responses (no `method` field) always go to `ols`.
		return write_message(p.ols_writer, body)
	}
	method, is_str := method_val.(json.String)
	if !is_str {
		return write_message(p.ols_writer, body)
	}

	params, _ := obj["params"].(json.Object)

	switch method {
	case "textDocument/didOpen":
		return _handle_did_open(p, body, params)
	case "textDocument/didChange":
		return _handle_did_change(p, body, params)
	case "textDocument/didSave":
		return _handle_did_save(p, body, params)
	case "textDocument/didClose":
		return _handle_did_close(p, body, params)
	}

	// If this message targets a known `.weasel` document, rewrite its
	// params (coordinates and URIs) before forwarding to ols.  If it's a
	// request (has an id) we also remember the target URI so the
	// matching response can be rewritten back on the ols→editor side.
	return _handle_generic_editor_message(p, body, obj, string(method))
}

// ---------------------------------------------------------------------------
// ols → editor message processing (response / notification rewriting)
// ---------------------------------------------------------------------------

// proxy_process_ols_message handles one framed body coming back from
// `ols`.  For responses to requests we recorded on the editor→ols side
// it rewrites Odin coordinates back to Weasel coordinates in the
// `result` field.  For `textDocument/publishDiagnostics` notifications
// addressed to one of our shadow `.odin` URIs it rewrites both the URI
// and each diagnostic's range, dropping diagnostics whose range fails to
// map.  Everything else forwards verbatim.
//
// A parse failure or shape mismatch also forwards verbatim — under no
// circumstances do we want to swallow an ols message the proxy
// didn't understand.
proxy_process_ols_message :: proc(p: ^Proxy, body: []u8) -> Frame_Error {
	sync.mutex_lock(&p.state_mu)
	defer sync.mutex_unlock(&p.state_mu)

	v, perr := json.parse(body, parse_integers = true)
	if perr != .None {
		return proxy_write_to_editor(p, body)
	}
	defer json.destroy_value(v)

	obj, ok := v.(json.Object)
	if !ok {
		return proxy_write_to_editor(p, body)
	}

	// Notifications from ols: dispatch on method name.
	if method_val, has_method := obj["method"]; has_method {
		method, is_str := method_val.(json.String)
		if !is_str {return proxy_write_to_editor(p, body)}
		switch string(method) {
		case "textDocument/publishDiagnostics":
			return _handle_publish_diagnostics_from_ols(p, body, obj)
		}
		// Other notifications (e.g. server→client requests with a
		// method — technically requests, but follow the same shape)
		// pass through unchanged.
		return proxy_write_to_editor(p, body)
	}

	// Response to a request we may have originated.  Look up the
	// pending entry to find the document whose source map should
	// interpret the result.
	id_val, has_id := obj["id"]
	if !has_id {return proxy_write_to_editor(p, body)}

	key, keyed := _pending_key_owned(id_val)
	defer if keyed {delete(key)}
	if !keyed {return proxy_write_to_editor(p, body)}

	pending, found := p.pending[key]
	if !found {
		// Response to a request we didn't track (passthrough request)
		// or to a server-originated request — forward as-is.
		return proxy_write_to_editor(p, body)
	}

	// Remove the pending entry and free its owned strings.  The
	// `key` we used for lookup is a transient copy; the stored key
	// is freed via delete_key's return.
	stored_key, stored_val := delete_key(&p.pending, key)
	defer {
		delete(stored_key)
		delete(stored_val.method)
		delete(stored_val.weasel_uri)
	}

	doc, have_doc := p.documents[pending.weasel_uri]
	if !have_doc {
		// Document was closed between request and response.  Forward
		// the raw body and let the editor handle stale coordinates —
		// it's about to see a didClose confirmation anyway.
		return proxy_write_to_editor(p, body)
	}

	ctx := _Rewrite_Ctx{
		proxy       = p,
		default_doc = doc,
		dir         = .Odin_To_Weasel,
	}
	if result_val, has_result := obj["result"]; has_result {
		rv := result_val
		_rewrite_lsp_value(&rv, &ctx)
		obj["result"] = rv
	}
	// Errors don't carry positions; they're forwarded as-is via the
	// re-marshal below.
	return _marshal_and_send_to_editor(p, json.Value(obj))
}

// _handle_publish_diagnostics_from_ols rewrites an incoming
// publishDiagnostics notification whose URI is one of our shadow
// `.odin` documents.  Notifications for unrelated URIs pass through.
@(private = "file")
_handle_publish_diagnostics_from_ols :: proc(
	p: ^Proxy,
	body: []u8,
	obj: json.Object,
) -> Frame_Error {
	params, has_params := obj["params"].(json.Object)
	if !has_params {return proxy_write_to_editor(p, body)}
	uri_val, has_uri := params["uri"].(json.String)
	if !has_uri {return proxy_write_to_editor(p, body)}

	weasel_uri, is_shadow := _odin_uri_to_weasel_uri(string(uri_val))
	if !is_shadow {return proxy_write_to_editor(p, body)}
	doc, have_doc := p.documents[weasel_uri]
	if !have_doc {return proxy_write_to_editor(p, body)}

	ctx := _Rewrite_Ctx{
		proxy       = p,
		default_doc = doc,
		dir         = .Odin_To_Weasel,
	}
	pv := obj["params"]
	_rewrite_lsp_value(&pv, &ctx)
	return _marshal_and_send_to_editor(p, json.Value(obj))
}

// _marshal_and_send_to_editor serializes v and writes it to the editor
// through the mutex-guarded path shared by all editor-bound frames.
@(private = "file")
_marshal_and_send_to_editor :: proc(p: ^Proxy, v: any) -> Frame_Error {
	data, err := json.marshal(v)
	if err != nil {
		fmt.eprintfln("weasel-lsp: json marshal failed (ols→editor): %v", err)
		return .IO
	}
	defer delete(data)
	return proxy_write_to_editor(p, data)
}

// _odin_uri_to_weasel_uri converts a shadow URI back to its Weasel
// origin.  Mirrors weasel_uri_to_odin_uri in the opposite direction.
// Returns ("", false) for URIs that aren't shadow names so the caller
// can pass them through untouched.
@(private = "file")
_odin_uri_to_weasel_uri :: proc(odin_uri: string) -> (string, bool) {
	if !strings.has_suffix(odin_uri, ".weasel.odin") {return "", false}
	return odin_uri[:len(odin_uri) - len(".odin")], true
}

// ---------------------------------------------------------------------------
// Generic editor→ols rewriting for position-bearing requests
// ---------------------------------------------------------------------------

// _handle_generic_editor_message handles any editor→ols message that
// isn't a document lifecycle notification.  When `params.textDocument.uri`
// names a known `.weasel` document, the walker rewrites Weasel
// coordinates to Odin inside the params tree and the body is re-marshaled
// for forwarding.  When an `id` field is present (request, not
// notification) we also record a pending entry keyed by that id so the
// matching response can be rewritten back to Weasel coordinates.
//
// If the message isn't tied to a known document the original body is
// forwarded byte-for-byte — we deliberately avoid touching messages
// that reference unrelated files.
@(private = "file")
_handle_generic_editor_message :: proc(
	p: ^Proxy,
	body: []u8,
	obj: json.Object,
	method: string,
) -> Frame_Error {
	target_uri, has_target := _extract_text_document_uri(obj["params"])
	doc: ^Document
	if has_target {
		doc = p.documents[target_uri]
	}
	if doc == nil {
		// Not addressed to one of our documents — pass through unchanged.
		return write_message(p.ols_writer, body)
	}

	// Record pending only for requests (those that expect a response).
	if id_val, has_id := obj["id"]; has_id {
		owned_key, keyed := _pending_key_owned(id_val)
		if keyed {
			// If the id was already in-flight (shouldn't normally
			// happen) evict and free its entry before replacing so the
			// stored strings don't leak.
			old_k, old_v := delete_key(&p.pending, owned_key)
			if len(old_k) > 0 {
				delete(old_k)
				delete(old_v.method)
				delete(old_v.weasel_uri)
			}
			p.pending[owned_key] = Pending_Request{
				method     = strings.clone(method),
				weasel_uri = strings.clone(doc.weasel_uri),
			}
		}
	}

	// Rewrite the params tree in place.  The walker mutates nested
	// objects/arrays through shared handles, so reassignment into `obj`
	// isn't necessary — marshaling `obj` below sees the rewritten tree.
	ctx := _Rewrite_Ctx{
		proxy       = p,
		default_doc = doc,
		dir         = .Weasel_To_Odin,
	}
	if params_val, has_params := obj["params"]; has_params {
		pv := params_val
		_rewrite_lsp_value(&pv, &ctx)
	}
	return _marshal_and_send(p.ols_writer, json.Value(obj))
}

// _extract_text_document_uri pulls `textDocument.uri` out of a params
// value.  Returns ("", false) when the shape doesn't match — the caller
// treats that as "no known document" and passes through.
@(private = "file")
_extract_text_document_uri :: proc(v: json.Value) -> (string, bool) {
	params, ok := v.(json.Object)
	if !ok {return "", false}
	td, td_ok := params["textDocument"].(json.Object)
	if !td_ok {return "", false}
	uri, uri_ok := td["uri"].(json.String)
	if !uri_ok {return "", false}
	return string(uri), true
}

// _pending_key_owned builds a stable map key from a JSON-RPC request
// id.  Integer and string ids share the same id space per the spec but
// their JSON shapes differ; prefix each to avoid accidental collision.
// The returned slice is allocated from context.allocator and must
// outlive the map entry — the key is freed by the consumer on response
// lookup or by proxy_destroy on shutdown.  Returns ("", false) for id
// values that aren't one of the expected scalar shapes.
@(private = "file")
_pending_key_owned :: proc(v: json.Value) -> (string, bool) {
	#partial switch x in v {
	case json.Integer:
		buf: [32]u8
		return strings.concatenate({"i:", _int_to_buf(buf[:], int(x))}), true
	case json.String:
		return strings.concatenate({"s:", string(x)}), true
	}
	return "", false
}

// _int_to_buf renders n into buf, right-aligned, and returns the filled
// slice.  Local because strconv.itoa rounds through the general-purpose
// number printer and this is the one place we stringify integers.
@(private = "file")
_int_to_buf :: proc(buf: []u8, n: int) -> string {
	if n == 0 {return "0"}
	neg := n < 0
	v := n
	if neg {v = -v}
	i := len(buf)
	for v > 0 {
		i -= 1
		buf[i] = u8('0' + u8(v % 10))
		v /= 10
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

// ---------------------------------------------------------------------------
// URI helpers
// ---------------------------------------------------------------------------

// weasel_uri_to_odin_uri appends `.odin` to a `.weasel` URI.  The second
// return value is false for non-`.weasel` URIs; the caller should treat the
// original URI as opaque in that case and pass it through unchanged.
weasel_uri_to_odin_uri :: proc(weasel_uri: string, allocator := context.allocator) -> (string, bool) {
	if !strings.has_suffix(weasel_uri, ".weasel") {return "", false}
	return strings.concatenate({weasel_uri, ".odin"}, allocator), true
}

// _is_weasel_uri — true for URIs we want to intercept.  Kept as a helper so
// the check is defined in one place; the proxy only knows about .weasel
// files today but the rule may tighten later (schema check, etc.).
@(private = "file")
_is_weasel_uri :: proc(uri: string) -> bool {
	return strings.has_suffix(uri, ".weasel")
}

// _file_uri_to_path strips the `file://` scheme and returns the filesystem
// path.  Returns ("", false) for non-file URIs — which `didSave` treats as
// a no-op (we can't write to a remote URI).
@(private = "file")
_file_uri_to_path :: proc(uri: string) -> (string, bool) {
	if !strings.has_prefix(uri, "file://") {return "", false}
	return uri[len("file://"):], true
}

// ---------------------------------------------------------------------------
// textDocument/didOpen
// ---------------------------------------------------------------------------

@(private = "file")
_handle_did_open :: proc(p: ^Proxy, body: []u8, params: json.Object) -> Frame_Error {
	td, _ := params["textDocument"].(json.Object)
	uri, _ := td["uri"].(json.String)
	text, _ := td["text"].(json.String)
	language_id, _ := td["languageId"].(json.String)
	version := _integer_from(td["version"])

	if !_is_weasel_uri(string(uri)) {
		return write_message(p.ols_writer, body)
	}

	// Replace any prior state for this URI.  An over-eager editor can
	// re-send didOpen without a didClose; drop the stale document instead of
	// leaking state.
	if existing, was := p.documents[string(uri)]; was {
		delete_key(&p.documents, string(uri))
		_document_destroy(existing)
		free(existing)
	}

	doc := new(Document)
	doc.weasel_uri  = strings.clone(string(uri))
	doc.language_id = strings.clone(string(language_id))
	doc.version     = version
	doc.weasel_text = strings.clone(string(text))
	odin_uri, _ := weasel_uri_to_odin_uri(doc.weasel_uri)
	doc.odin_uri = odin_uri

	diags := _transpile_into(doc)
	defer _diagnostics_free(diags)

	p.documents[doc.weasel_uri] = doc

	// Synthesize a didOpen toward ols carrying the generated Odin text.  We
	// always send a body even when transpile failed — if nothing was ever
	// good, the body is empty; ols will file syntax errors on it but the
	// document tracking stays consistent.
	if err := _send_did_open_to_ols(p, doc); err != .None {return err}

	// Publish any collected diagnostics back to the editor so the user sees
	// Weasel-side errors even on the initial open.
	return _publish_diagnostics(p, doc.weasel_uri, diags)
}

// ---------------------------------------------------------------------------
// textDocument/didChange
// ---------------------------------------------------------------------------

@(private = "file")
_handle_did_change :: proc(p: ^Proxy, body: []u8, params: json.Object) -> Frame_Error {
	td, _ := params["textDocument"].(json.Object)
	uri, _ := td["uri"].(json.String)
	version := _integer_from(td["version"])

	if !_is_weasel_uri(string(uri)) {
		return write_message(p.ols_writer, body)
	}

	doc, ok := p.documents[string(uri)]
	if !ok {
		// didChange before didOpen — shouldn't happen, but drop rather than
		// forward a .weasel URI to ols which wouldn't know what to do.
		return .None
	}

	changes, _ := params["contentChanges"].(json.Array)
	new_text, applied := _apply_content_changes(doc.weasel_text, changes)
	if applied {
		delete(doc.weasel_text)
		doc.weasel_text = new_text
	}
	doc.version = version

	diags := _transpile_into(doc)
	defer _diagnostics_free(diags)

	if err := _send_did_change_to_ols(p, doc); err != .None {return err}
	return _publish_diagnostics(p, doc.weasel_uri, diags)
}

// ---------------------------------------------------------------------------
// textDocument/didSave
// ---------------------------------------------------------------------------

@(private = "file")
_handle_did_save :: proc(p: ^Proxy, body: []u8, params: json.Object) -> Frame_Error {
	td, _ := params["textDocument"].(json.Object)
	uri, _ := td["uri"].(json.String)

	if !_is_weasel_uri(string(uri)) {
		return write_message(p.ols_writer, body)
	}

	doc, ok := p.documents[string(uri)]
	if !ok {return .None}

	// Write the last-good (or empty) generated Odin to the shadow path so
	// the developer can open and inspect it.  We ignore write errors here —
	// the user's editor will surface any filesystem problem in the next
	// save; failing the proxy over it would break a live ols session.
	if path, path_ok := _file_uri_to_path(doc.odin_uri); path_ok {
		_ = os.write_entire_file(path, transmute([]u8)doc.odin_text)
	}

	return _send_did_save_to_ols(p, doc)
}

// ---------------------------------------------------------------------------
// textDocument/didClose
// ---------------------------------------------------------------------------

@(private = "file")
_handle_did_close :: proc(p: ^Proxy, body: []u8, params: json.Object) -> Frame_Error {
	td, _ := params["textDocument"].(json.Object)
	uri, _ := td["uri"].(json.String)

	if !_is_weasel_uri(string(uri)) {
		return write_message(p.ols_writer, body)
	}

	doc, ok := p.documents[string(uri)]
	if !ok {return .None}

	// Tell ols about the close before we drop state so the URI names still
	// match.
	if err := _send_did_close_to_ols(p, doc); err != .None {
		// Even on write error we still need to free state — we won't see
		// the document again.
		delete_key(&p.documents, doc.weasel_uri)
		_document_destroy(doc)
		free(doc)
		return err
	}

	delete_key(&p.documents, doc.weasel_uri)
	_document_destroy(doc)
	free(doc)
	return .None
}

// ---------------------------------------------------------------------------
// Transpile + last-good tracking
// ---------------------------------------------------------------------------

// _Diagnostic is the proxy-facing representation of one scan/parse/transpile
// error.  Kept separate from the transpiler's Scan_Error / Parse_Error /
// Transpile_Error triples so the LSP layer can publish them uniformly
// regardless of origin.
@(private = "file")
_Diagnostic :: struct {
	message: string, // owned
	pos:     transpiler.Position,
}

@(private = "file")
_diagnostics_free :: proc(diags: [dynamic]_Diagnostic) {
	for d in diags {delete(d.message)}
	delete(diags)
}

// _transpile_into runs the scan/parse/transpile pipeline on doc.weasel_text.
// On success the document's odin_text / source_map / translator are
// refreshed and last_good flips to true.  On failure the previous
// last-good state is retained and the errors are returned as diagnostics.
//
// The scan/parse/transpile intermediates (tokens, parser nodes with nested
// dynamic arrays, transpile error strings, etc.) are allocated in a
// per-call Dynamic_Arena.  Keeping them there sidesteps manual deep-free
// for nested AST shapes.  Anything we want to retain — the generated Odin
// text, the Source_Map entries, the cloned diagnostic messages — is
// explicitly cloned into the outer allocator before the arena is
// destroyed.
@(private = "file")
_transpile_into :: proc(doc: ^Document) -> [dynamic]_Diagnostic {
	outer_alloc := context.allocator
	diags := make([dynamic]_Diagnostic, outer_alloc)

	arena: mem.Dynamic_Arena
	// 64-byte alignment so Odin map buckets (which demand cache-line
	// alignment in their internal allocator call) don't trip the runtime's
	// alignment check while the transpiler builds its name→has_slot map.
	mem.dynamic_arena_init(&arena, alignment = 64)
	defer mem.dynamic_arena_destroy(&arena)

	// Scan / parse / transpile allocate through context.allocator (including
	// fmt.aprintf for error messages), so redirect it at the arena for the
	// duration of the pipeline.
	context.allocator = mem.dynamic_arena_allocator(&arena)
	defer context.allocator = outer_alloc

	tokens, scan_errs := transpiler.scan(doc.weasel_text)
	for e in scan_errs {
		append(&diags, _Diagnostic{message = strings.clone(e.message, outer_alloc), pos = e.pos})
	}
	if len(scan_errs) > 0 {
		if !doc.last_good {_install_empty_transpile_with(doc, outer_alloc)}
		return diags
	}

	nodes, parse_errs := transpiler.parse(tokens[:])
	for e in parse_errs {
		append(&diags, _Diagnostic{message = strings.clone(e.message, outer_alloc), pos = e.pos})
	}
	if len(parse_errs) > 0 {
		if !doc.last_good {_install_empty_transpile_with(doc, outer_alloc)}
		return diags
	}

	source, smap, terrs := transpiler.transpile(nodes[:])
	for e in terrs {
		append(&diags, _Diagnostic{message = strings.clone(e.message, outer_alloc), pos = e.pos})
	}
	if len(terrs) > 0 {
		// The arena will swallow source/smap/terrs; nothing to free here.
		if !doc.last_good {_install_empty_transpile_with(doc, outer_alloc)}
		return diags
	}

	// Success — clone the result out of the arena into outer_alloc, then
	// swap it in over any previous last-good state.
	if doc.last_good {
		delete(doc.odin_text, outer_alloc)
		translator_destroy(&doc.translator)
		transpiler.source_map_destroy(&doc.source_map)
	}
	doc.odin_text = strings.clone(source, outer_alloc)
	new_entries   := make([dynamic]transpiler.Span_Entry, 0, len(smap.entries), outer_alloc)
	for entry in smap.entries {append(&new_entries, entry)}
	doc.source_map = transpiler.Source_Map{entries = new_entries}
	doc.translator = translator_make(&doc.source_map, outer_alloc)
	doc.last_good  = true
	return diags
}

// _install_empty_transpile_with seeds an empty Odin document for a Weasel
// file that has never transpiled successfully.  Keeps ols alive with a
// valid (if empty) source so it doesn't error out on the open.  Takes an
// explicit allocator because callers typically hold the arena-redirected
// context.allocator at the call site.
@(private = "file")
_install_empty_transpile_with :: proc(doc: ^Document, alloc: mem.Allocator) {
	if doc.last_good {return}
	doc.odin_text = strings.clone("", alloc)
	doc.source_map = transpiler.Source_Map{
		entries = make([dynamic]transpiler.Span_Entry, 0, 0, alloc),
	}
	doc.translator = translator_make(&doc.source_map, alloc)
}

// _document_destroy releases every allocation owned by doc.  Safe to call
// on a partially-populated Document (e.g. from an aborted didOpen) —
// cloned strings are always backed by an allocation, even the empty
// ones, and delete() tolerates the zero-length case.
@(private = "file")
_document_destroy :: proc(doc: ^Document) {
	delete(doc.weasel_uri)
	delete(doc.odin_uri)
	delete(doc.language_id)
	delete(doc.weasel_text)
	delete(doc.odin_text)
	translator_destroy(&doc.translator)
	transpiler.source_map_destroy(&doc.source_map)
}

// ---------------------------------------------------------------------------
// contentChanges application
// ---------------------------------------------------------------------------

// _apply_content_changes applies the LSP `contentChanges` entries in order.
// It supports:
//   • Full-document sync:    { "text": "…" }                 → replace entire text
//   • Incremental edit:      { "range": {…}, "text": "…" }   → splice in range
//
// Positions are interpreted as (line, character) with byte offsets on the
// line — a deliberate simplification: the LSP spec defines `character` as
// UTF-16 code units by default, so files containing non-ASCII code points
// will currently misalign.  This is acceptable for the in-memory
// transpilation task and tracked as a known limitation.
//
// Returns (new_text, true) on success; (nil, false) when no change was
// applicable (the caller keeps the existing text).
@(private = "file")
_apply_content_changes :: proc(text: string, changes: json.Array, allocator := context.allocator) -> (string, bool) {
	current := strings.clone(text, allocator)
	did_apply := false

	for change in changes {
		cobj, cok := change.(json.Object)
		if !cok {continue}

		text_val, has_text := cobj["text"].(json.String)
		if !has_text {continue}

		range_val, has_range := cobj["range"].(json.Object)
		if !has_range {
			// Full-document replacement.
			delete(current, allocator)
			current = strings.clone(string(text_val), allocator)
			did_apply = true
			continue
		}

		start_off, start_ok := _position_to_offset(current, range_val["start"])
		end_off,   end_ok   := _position_to_offset(current, range_val["end"])
		if !start_ok || !end_ok || start_off > end_off || end_off > len(current) {
			continue
		}

		next := strings.concatenate(
			{current[:start_off], string(text_val), current[end_off:]},
			allocator,
		)
		delete(current, allocator)
		current = next
		did_apply = true
	}

	if !did_apply {
		delete(current, allocator)
		return "", false
	}
	return current, true
}

// _position_to_offset converts an LSP { line, character } object into a
// byte offset into text.  Lines beyond the end of the buffer clamp to
// len(text); characters beyond a line clamp to the end of that line.
@(private = "file")
_position_to_offset :: proc(text: string, v: json.Value) -> (int, bool) {
	obj, ok := v.(json.Object)
	if !ok {return 0, false}
	line := int(_integer_from(obj["line"]))
	chr  := int(_integer_from(obj["character"]))

	// Walk the text counting newlines to find the start of `line`.
	off := 0
	for cur_line := 0; cur_line < line && off < len(text); off += 1 {
		if text[off] == '\n' {cur_line += 1}
	}
	// Advance up to `chr` bytes, bounded by the next newline.
	line_end := off
	for line_end < len(text) && text[line_end] != '\n' {line_end += 1}
	col_off := min(chr, line_end - off)
	return off + col_off, true
}

// ---------------------------------------------------------------------------
// Message synthesis toward ols
// ---------------------------------------------------------------------------

// _LSP_Position matches the wire shape of LSP's { line, character }.  Kept
// local to the synthesis code so we don't accidentally confuse it with
// transpiler.Position elsewhere.
@(private = "file")
_LSP_Position :: struct {
	line:      int `json:"line"`,
	character: int `json:"character"`,
}

@(private = "file")
_LSP_Range :: struct {
	start: _LSP_Position `json:"start"`,
	end:   _LSP_Position `json:"end"`,
}

@(private = "file")
_LSP_Diagnostic :: struct {
	range:    _LSP_Range `json:"range"`,
	severity: int        `json:"severity"`,
	source:   string     `json:"source"`,
	message:  string     `json:"message"`,
}

@(private = "file")
_DidOpen_TextDocument_Item :: struct {
	uri:        string `json:"uri"`,
	languageId: string `json:"languageId"`,
	version:    int    `json:"version"`,
	text:       string `json:"text"`,
}

@(private = "file")
_DidOpen_Params :: struct {
	textDocument: _DidOpen_TextDocument_Item `json:"textDocument"`,
}

@(private = "file")
_VersionedTextDocumentIdentifier :: struct {
	uri:     string `json:"uri"`,
	version: int    `json:"version"`,
}

@(private = "file")
_TextDocumentContentChange_Full :: struct {
	text: string `json:"text"`,
}

@(private = "file")
_DidChange_Params :: struct {
	textDocument:   _VersionedTextDocumentIdentifier   `json:"textDocument"`,
	contentChanges: []_TextDocumentContentChange_Full  `json:"contentChanges"`,
}

@(private = "file")
_TextDocumentIdentifier :: struct {
	uri: string `json:"uri"`,
}

@(private = "file")
_DidSave_Params :: struct {
	textDocument: _TextDocumentIdentifier `json:"textDocument"`,
	text:         string                  `json:"text"`,
}

@(private = "file")
_DidClose_Params :: struct {
	textDocument: _TextDocumentIdentifier `json:"textDocument"`,
}

@(private = "file")
_PublishDiagnostics_Params :: struct {
	uri:         string            `json:"uri"`,
	diagnostics: []_LSP_Diagnostic `json:"diagnostics"`,
}

// _Notification serialises as a JSON-RPC 2.0 notification envelope.  The
// JSON encoder handles quoting/escaping for us — building this by string
// concatenation would be a bug magnet on parameter text containing quotes
// or newlines.
@(private = "file")
_Notification :: struct($P: typeid) {
	jsonrpc: string `json:"jsonrpc"`,
	method:  string `json:"method"`,
	params:  P      `json:"params"`,
}

@(private = "file")
_send_did_open_to_ols :: proc(p: ^Proxy, doc: ^Document) -> Frame_Error {
	msg := _Notification(_DidOpen_Params){
		jsonrpc = "2.0",
		method  = "textDocument/didOpen",
		params  = _DidOpen_Params{
			textDocument = _DidOpen_TextDocument_Item{
				uri        = doc.odin_uri,
				languageId = "odin",
				version    = doc.version,
				text       = doc.odin_text,
			},
		},
	}
	return _marshal_and_send(p.ols_writer, msg)
}

@(private = "file")
_send_did_change_to_ols :: proc(p: ^Proxy, doc: ^Document) -> Frame_Error {
	changes := []_TextDocumentContentChange_Full{
		{text = doc.odin_text},
	}
	msg := _Notification(_DidChange_Params){
		jsonrpc = "2.0",
		method  = "textDocument/didChange",
		params  = _DidChange_Params{
			textDocument = _VersionedTextDocumentIdentifier{
				uri     = doc.odin_uri,
				version = doc.version,
			},
			contentChanges = changes,
		},
	}
	return _marshal_and_send(p.ols_writer, msg)
}

@(private = "file")
_send_did_save_to_ols :: proc(p: ^Proxy, doc: ^Document) -> Frame_Error {
	msg := _Notification(_DidSave_Params){
		jsonrpc = "2.0",
		method  = "textDocument/didSave",
		params  = _DidSave_Params{
			textDocument = _TextDocumentIdentifier{uri = doc.odin_uri},
			text         = doc.odin_text,
		},
	}
	return _marshal_and_send(p.ols_writer, msg)
}

@(private = "file")
_send_did_close_to_ols :: proc(p: ^Proxy, doc: ^Document) -> Frame_Error {
	msg := _Notification(_DidClose_Params){
		jsonrpc = "2.0",
		method  = "textDocument/didClose",
		params  = _DidClose_Params{
			textDocument = _TextDocumentIdentifier{uri = doc.odin_uri},
		},
	}
	return _marshal_and_send(p.ols_writer, msg)
}

// _publish_diagnostics pushes scan/parse/transpile errors (or an empty list
// to clear previous ones) back to the editor under the Weasel URI.
@(private = "file")
_publish_diagnostics :: proc(p: ^Proxy, weasel_uri: string, diags: [dynamic]_Diagnostic) -> Frame_Error {
	wire_diags := make([]_LSP_Diagnostic, len(diags))
	defer delete(wire_diags)
	for d, i in diags {
		// Transpiler positions are 1-based; LSP expects 0-based.  col-1
		// goes negative if a bad position slips through — clamp to 0 so we
		// never emit a broken frame.
		line := max(d.pos.line - 1, 0)
		col  := max(d.pos.col  - 1, 0)
		wire_diags[i] = _LSP_Diagnostic{
			range = _LSP_Range{
				start = _LSP_Position{line = line, character = col},
				end   = _LSP_Position{line = line, character = col + 1},
			},
			severity = 1, // LSP DiagnosticSeverity.Error
			source   = "weasel",
			message  = d.message,
		}
	}

	msg := _Notification(_PublishDiagnostics_Params){
		jsonrpc = "2.0",
		method  = "textDocument/publishDiagnostics",
		params  = _PublishDiagnostics_Params{
			uri         = weasel_uri,
			diagnostics = wire_diags,
		},
	}

	data, merr := json.marshal(msg)
	if merr != nil {return .IO}
	defer delete(data)
	return proxy_write_to_editor(p, data)
}

@(private = "file")
_marshal_and_send :: proc(w: io.Writer, v: any) -> Frame_Error {
	data, err := json.marshal(v)
	if err != nil {
		fmt.eprintfln("weasel-lsp: json marshal failed: %v", err)
		return .IO
	}
	defer delete(data)
	return write_message(w, data)
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

// _integer_from tolerates Integer / Float / missing values uniformly.
// LSP versions arrive as integers in practice, but JSON5 parsing may pick
// the Float branch in some configurations — handle both rather than tying
// the proxy to the parser's spec choice.
@(private = "file")
_integer_from :: proc(v: json.Value) -> int {
	#partial switch x in v {
	case json.Integer: return int(x)
	case json.Float:   return int(x)
	}
	return 0
}
