/*
	LSP JSON-RPC framing.

	The Language Server Protocol wraps every JSON-RPC payload in a short
	header block terminated by a blank line:

	    Content-Length: 42\r\n
	    Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n
	    \r\n
	    {...42 bytes of UTF-8 JSON...}

	Only `Content-Length` is mandatory; we ignore every other header.  Both
	CRLF and bare LF line endings are accepted on the read side to be lenient
	with broken clients, but everything we emit uses CRLF as the spec requires.

	This file provides two primitives used by the proxy:
	  - read_message: consume one framed message from an io.Reader and return
	    the body as a freshly-allocated byte slice.
	  - write_message: frame a body and write it to an io.Writer.

	Bodies are opaque bytes at this layer — no JSON parsing.  The proxy is a
	pure passthrough at this stage; T-0014 will start inspecting bodies.
*/
package lsp

import "core:bytes"
import "core:io"
import "core:strconv"
import "core:strings"

// Frame_Error is the flat error space exposed to callers.
Frame_Error :: enum {
	None,
	EOF,             // clean close before any header byte of a new frame
	Unexpected_EOF,  // stream closed mid-frame (headers or body incomplete)
	Invalid_Header,  // malformed header or missing/negative Content-Length
	Oversize,        // Content-Length exceeds MAX_BODY_BYTES
	IO,              // lower-level read/write error from the stream
}

// MAX_HEADER_BYTES caps total header bytes (including the trailing blank
// line) to protect the proxy from a runaway stream that never sends the
// terminating \r\n\r\n.  Real LSP headers are a few hundred bytes at most.
MAX_HEADER_BYTES :: 8192

// MAX_BODY_BYTES caps a single message body.  LSP payloads are occasionally
// large (e.g. full document sync on a big file) but 64 MiB is beyond
// anything realistic and a sensible DoS guard.
MAX_BODY_BYTES :: 64 * 1024 * 1024

// read_message consumes one framed LSP message from r.  On success the
// returned slice is the body (Content-Length bytes, no headers) and err is
// .None.  The caller owns the slice and must free it with the same
// allocator.
//
// On a clean close (EOF before any header byte of a new frame) returns
// (nil, .EOF) so the caller can distinguish "peer disconnected cleanly"
// from "stream died mid-message" (.Unexpected_EOF).
read_message :: proc(
	r: io.Reader,
	allocator := context.allocator,
) -> (body: []u8, err: Frame_Error) {
	content_length, header_err := _read_headers(r)
	if header_err != .None {return nil, header_err}

	if content_length < 0 {return nil, .Invalid_Header}
	if content_length > MAX_BODY_BYTES {return nil, .Oversize}

	// Zero-length body is legal (rare but permitted by JSON-RPC — e.g. an
	// empty notification payload would have been a parse error upstream but
	// at the frame layer we just forward it).
	buf := make([]u8, content_length, allocator)
	if content_length == 0 {return buf, .None}

	n, read_err := io.read_full(r, buf)
	if read_err == .EOF || read_err == .Unexpected_EOF || n < content_length {
		delete(buf, allocator)
		return nil, .Unexpected_EOF
	}
	if read_err != .None {
		delete(buf, allocator)
		return nil, .IO
	}
	return buf, .None
}

// write_message writes body to w with a Content-Length header.  The header
// is emitted with CRLF line endings per the LSP spec.
write_message :: proc(w: io.Writer, body: []u8) -> Frame_Error {
	// Header: "Content-Length: <n>\r\n\r\n".  Bounded stack buffer is plenty.
	digits: [32]u8
	n_str := strconv.write_int(digits[:], i64(len(body)), 10)

	// Issue the header in one compact sequence of writes.  Any write error
	// collapses to .IO; partial writes from io.write_full advance on our
	// behalf until the target is reached or an error is returned.
	if _, e := io.write_full(w, transmute([]u8)string("Content-Length: ")); e != .None {return .IO}
	if _, e := io.write_full(w, transmute([]u8)n_str); e != .None {return .IO}
	if _, e := io.write_full(w, transmute([]u8)string("\r\n\r\n")); e != .None {return .IO}
	if len(body) > 0 {
		if _, e := io.write_full(w, body); e != .None {return .IO}
	}
	return .None
}

// _read_headers consumes bytes from r up to and including the blank line
// that terminates the header block, parses each header, and returns the
// Content-Length value.  Missing or malformed Content-Length surfaces as
// .Invalid_Header.  A clean EOF before any header byte returns .EOF.
@(private = "file")
_read_headers :: proc(r: io.Reader) -> (content_length: int, err: Frame_Error) {
	accum: bytes.Buffer
	bytes.buffer_init_allocator(&accum, 0, 256)
	defer bytes.buffer_destroy(&accum)

	content_length = -1
	have_any_byte := false

	// Read byte-by-byte until we've consumed a blank line (i.e. two
	// consecutive LF bytes with only optional CR between them).  Counting
	// bytes guards against an unbounded header.
	b: [1]u8
	for {
		if bytes.buffer_length(&accum) > MAX_HEADER_BYTES {
			return -1, .Invalid_Header
		}

		n, read_err := io.read(r, b[:])
		if read_err == .EOF {
			if !have_any_byte {return -1, .EOF}
			return -1, .Unexpected_EOF
		}
		if read_err == .Unexpected_EOF {
			return -1, .Unexpected_EOF
		}
		if read_err != .None {
			return -1, .IO
		}
		if n == 0 {continue}
		have_any_byte = true

		bytes.buffer_write_byte(&accum, b[0])

		// Detect the end of the header block: either "\r\n\r\n" or "\n\n".
		if _ends_with_blank_line(bytes.buffer_to_bytes(&accum)) {
			break
		}
	}

	// Parse accumulated headers.  Strip the trailing blank line before
	// splitting so we don't produce an empty trailing entry.
	raw := string(bytes.buffer_to_bytes(&accum))
	raw = _strip_trailing_blank(raw)

	it := raw
	for line in strings.split_lines_iterator(&it) {
		if len(line) == 0 {continue}
		// Strip a possible trailing CR (when the peer used CRLF).
		trimmed := strings.trim_right(line, "\r")
		if trimmed == "" {continue}

		colon := strings.index_byte(trimmed, ':')
		if colon < 0 {return -1, .Invalid_Header}

		key := strings.trim_space(trimmed[:colon])
		val := strings.trim_space(trimmed[colon + 1:])

		if strings.equal_fold(key, "Content-Length") {
			parsed, ok := strconv.parse_int(val)
			if !ok {return -1, .Invalid_Header}
			content_length = parsed
		}
		// All other headers are ignored at this stage.
	}

	if content_length < 0 {return -1, .Invalid_Header}
	return content_length, .None
}

// _ends_with_blank_line returns true when the byte slice terminates with a
// blank-line delimiter — either CRLF CRLF or LF LF.  Everything else (a
// lone CR, a single LF on its own, etc.) does not end the header block.
@(private = "file")
_ends_with_blank_line :: proc(buf: []u8) -> bool {
	n := len(buf)
	if n >= 4 && buf[n-4] == '\r' && buf[n-3] == '\n' && buf[n-2] == '\r' && buf[n-1] == '\n' {
		return true
	}
	if n >= 2 && buf[n-2] == '\n' && buf[n-1] == '\n' {
		return true
	}
	return false
}

// _strip_trailing_blank removes the trailing CRLFCRLF or LFLF so the
// remaining string can be split into header lines without producing a
// spurious empty line at the end.
@(private = "file")
_strip_trailing_blank :: proc(s: string) -> string {
	n := len(s)
	if n >= 4 && s[n-4] == '\r' && s[n-3] == '\n' && s[n-2] == '\r' && s[n-1] == '\n' {
		return s[:n-4]
	}
	if n >= 2 && s[n-2] == '\n' && s[n-1] == '\n' {
		return s[:n-2]
	}
	return s
}
