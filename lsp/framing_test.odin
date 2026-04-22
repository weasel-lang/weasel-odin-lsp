package lsp

import "core:bytes"
import "core:io"
import "core:strings"
import "core:testing"

// _Chunk_Reader is a test-only io.Reader that hands out at most `chunk`
// bytes per call.  It lets us simulate streams where headers or bodies
// arrive spread across multiple read() calls — the proxy has to tolerate
// that because real OS pipes do the same.
@(private = "file")
_Chunk_Reader :: struct {
	data:  []u8,
	pos:   int,
	chunk: int,
}

@(private = "file")
_chunk_reader_proc :: proc(
	stream_data: rawptr,
	mode: io.Stream_Mode,
	p: []byte,
	offset: i64,
	whence: io.Seek_From,
) -> (n: i64, err: io.Error) {
	cr := (^_Chunk_Reader)(stream_data)
	switch mode {
	case .Read:
		if cr.pos >= len(cr.data) {return 0, .EOF}
		max := min(cr.chunk, len(p), len(cr.data) - cr.pos)
		for i in 0 ..< max {
			p[i] = cr.data[cr.pos + i]
		}
		cr.pos += max
		return i64(max), nil
	case .Query:
		return i64(io.Stream_Mode_Set{.Read, .Query}), nil
	case .Close, .Destroy, .Flush, .Read_At, .Write, .Write_At, .Seek, .Size:
		return 0, .Empty
	}
	return 0, .Empty
}

@(private = "file")
_chunk_reader :: proc(cr: ^_Chunk_Reader) -> io.Reader {
	s: io.Stream
	s.data = cr
	s.procedure = _chunk_reader_proc
	return s
}

// ---------------------------------------------------------------------------
// read_message
// ---------------------------------------------------------------------------

@(test)
test_framing_read_basic :: proc(t: ^testing.T) {
	input := "Content-Length: 11\r\n\r\nhello world"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 1024}
	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, string(body), "hello world")
}

// Headers + body arrive byte-by-byte — exercises the case where the read
// loop must keep calling io.read until a full frame is assembled.
@(test)
test_framing_read_byte_at_a_time :: proc(t: ^testing.T) {
	input := "Content-Length: 5\r\n\r\nhi!xy"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 1}
	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, string(body), "hi!xy")
}

// Multiple messages in a row share the same reader.  The second read must
// pick up exactly where the first left off.
@(test)
test_framing_read_back_to_back :: proc(t: ^testing.T) {
	input := "Content-Length: 3\r\n\r\nabcContent-Length: 4\r\n\r\nwxyz"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 7}

	body1, err1 := read_message(_chunk_reader(&cr))
	defer delete(body1)
	testing.expect_value(t, err1, Frame_Error.None)
	testing.expect_value(t, string(body1), "abc")

	body2, err2 := read_message(_chunk_reader(&cr))
	defer delete(body2)
	testing.expect_value(t, err2, Frame_Error.None)
	testing.expect_value(t, string(body2), "wxyz")
}

// The proxy must accept extra headers (Content-Type at minimum) without
// treating them as errors.
@(test)
test_framing_read_extra_headers :: proc(t: ^testing.T) {
	input := "Content-Length: 2\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\nok"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 16}

	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, string(body), "ok")
}

// Bare-LF headers are legal here — the spec says CRLF but some clients
// send plain LF and the proxy is lenient.
@(test)
test_framing_read_lf_only :: proc(t: ^testing.T) {
	input := "Content-Length: 4\n\nPING"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 3}

	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, string(body), "PING")
}

// Zero-length body is legal at the frame layer.
@(test)
test_framing_read_zero_body :: proc(t: ^testing.T) {
	input := "Content-Length: 0\r\n\r\n"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 1024}

	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, len(body), 0)
}

// A clean EOF before any header byte is .EOF, not an error — the proxy
// uses this to know the peer closed cleanly.
@(test)
test_framing_read_clean_eof :: proc(t: ^testing.T) {
	cr := _Chunk_Reader{data = []u8{}, chunk = 1}
	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.EOF)
	testing.expect(t, body == nil, "clean EOF must not allocate a body")
}

// EOF mid-frame (after some header bytes) is Unexpected_EOF — the peer
// died while we were mid-message.
@(test)
test_framing_read_truncated_headers :: proc(t: ^testing.T) {
	input := "Content-Length: 3\r\n"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 4}

	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.Unexpected_EOF)
	testing.expect(t, body == nil, "truncated header must not allocate a body")
}

// Header terminator arrives but the body is short — also Unexpected_EOF.
@(test)
test_framing_read_truncated_body :: proc(t: ^testing.T) {
	input := "Content-Length: 10\r\n\r\nabc"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 64}

	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.Unexpected_EOF)
	testing.expect(t, body == nil, "truncated body must not leak")
}

// Missing Content-Length → Invalid_Header.
@(test)
test_framing_read_missing_content_length :: proc(t: ^testing.T) {
	input := "Content-Type: application/json\r\n\r\nbody"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 16}

	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.Invalid_Header)
	testing.expect(t, body == nil, "invalid header must not allocate a body")
}

// Garbage header line (no colon) → Invalid_Header.
@(test)
test_framing_read_garbage_header :: proc(t: ^testing.T) {
	input := "not-a-header\r\n\r\nbody"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 32}

	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.Invalid_Header)
	testing.expect(t, body == nil, "invalid header must not allocate a body")
}

// Non-numeric Content-Length → Invalid_Header.
@(test)
test_framing_read_bad_content_length :: proc(t: ^testing.T) {
	input := "Content-Length: lol\r\n\r\nbody"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 32}

	body, err := read_message(_chunk_reader(&cr))
	testing.expect_value(t, err, Frame_Error.Invalid_Header)
	testing.expect(t, body == nil, "invalid length must not allocate a body")
}

// Content-Length header is matched case-insensitively.
@(test)
test_framing_read_case_insensitive_header :: proc(t: ^testing.T) {
	input := "content-length: 3\r\n\r\nyes"
	cr := _Chunk_Reader{data = transmute([]u8)input, chunk = 32}

	body, err := read_message(_chunk_reader(&cr))
	defer delete(body)
	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, string(body), "yes")
}

// ---------------------------------------------------------------------------
// write_message
// ---------------------------------------------------------------------------

@(test)
test_framing_write_basic :: proc(t: ^testing.T) {
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, 64)
	defer bytes.buffer_destroy(&buf)

	err := write_message(bytes.buffer_to_stream(&buf), transmute([]u8)string("hello"))
	testing.expect_value(t, err, Frame_Error.None)

	got := string(bytes.buffer_to_bytes(&buf))
	testing.expect_value(t, got, "Content-Length: 5\r\n\r\nhello")
}

@(test)
test_framing_write_zero_body :: proc(t: ^testing.T) {
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, 64)
	defer bytes.buffer_destroy(&buf)

	err := write_message(bytes.buffer_to_stream(&buf), []u8{})
	testing.expect_value(t, err, Frame_Error.None)

	got := string(bytes.buffer_to_bytes(&buf))
	testing.expect_value(t, got, "Content-Length: 0\r\n\r\n")
}

// Round-trip: what we write, we read back.
@(test)
test_framing_round_trip :: proc(t: ^testing.T) {
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, 128)
	defer bytes.buffer_destroy(&buf)

	payload := `{"jsonrpc":"2.0","id":1,"method":"initialize"}`
	err_w := write_message(bytes.buffer_to_stream(&buf), transmute([]u8)payload)
	testing.expect_value(t, err_w, Frame_Error.None)

	// Replay via a byte-at-a-time reader to exercise the straddle case.
	serialized := strings.clone(string(bytes.buffer_to_bytes(&buf)))
	defer delete(serialized)
	cr := _Chunk_Reader{data = transmute([]u8)serialized, chunk = 1}
	body, err_r := read_message(_chunk_reader(&cr))
	defer delete(body)

	testing.expect_value(t, err_r, Frame_Error.None)
	testing.expect_value(t, string(body), payload)
}
