package weasel

import "core:io"
import "core:slice"
import "core:strconv"

Attribute_Value :: union {
	int,
	bool,
	string,
}

Attributes :: map[string]Attribute_Value

// write_spread emits each entry in attrs as an HTML attribute pair ` key="value"`.
// bool true emits as a bare attribute name; bool false is omitted.
// int values are written as decimal strings.
// string values are HTML-escaped.
// Keys are sorted before emission so output is deterministic.
write_spread :: proc(w: io.Writer, attrs: Attributes) -> io.Error {
	keys := make([]string, len(attrs), context.temp_allocator)
	i := 0
	for k in attrs {
		keys[i] = k
		i += 1
	}
	slice.sort(keys)

	buf: [32]byte
	for k in keys {
		switch val in attrs[k] {
		case bool:
			if val {
				io.write_byte(w, ' ') or_return
				io.write_string(w, k) or_return
			}
		case int:
			io.write_byte(w, ' ') or_return
			io.write_string(w, k) or_return
			io.write_string(w, `="`) or_return
			io.write_string(w, strconv.write_int(buf[:], i64(val), 10)) or_return
			io.write_byte(w, '"') or_return
		case string:
			io.write_byte(w, ' ') or_return
			io.write_string(w, k) or_return
			io.write_string(w, `="`) or_return
			write_escaped_string(w, val) or_return
			io.write_byte(w, '"') or_return
		}
	}
	return nil
}

/*
	Writes a string to the writer with special characters that can be used in XSS escaped.
*/
write_escaped_string :: proc(w: io.Writer, str: string) -> io.Error {
	for i in 0 ..< len(str) {
		b := str[i]

		switch b {
		case '&':
			io.write_string(w, "&amp;") or_return
		case '"':
			io.write_string(w, "&quot;") or_return
		case '\'':
			io.write_string(w, "&#039;") or_return
		case '<':
			io.write_string(w, "&lt;") or_return
		case '>':
			io.write_string(w, "&gt;") or_return
		case:
			io.write_byte(w, b) or_return
		}
	}
	return nil
}

/*
	Writes a raw string directly to the writer without escaping.
*/
write_raw_string :: #force_inline proc(w: io.Writer, s: string) -> io.Error {
    _, err := io.write_string(w, s)
	return err
}
