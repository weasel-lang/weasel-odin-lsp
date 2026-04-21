package weasel

import "core:io"

/*
	Writes a string to the writer with special characters that can be used in XSS escaped.
*/
__weasel_write_escaped_string :: proc(w: io.Writer, str: string) -> io.Error {
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
__weasel_write_raw_string :: proc(w: io.Writer, s: string) -> io.Error {
	_, err := io.write_string(w, s)
	if err != .None {
		return err
	}
	return nil
}
