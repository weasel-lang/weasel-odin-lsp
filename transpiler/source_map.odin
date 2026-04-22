/*
	Source map: correspondence between byte ranges in the generated Odin output
	and their originating `.weasel` source spans.

	The transpiler returns a Source_Map alongside the generated Odin string so
	downstream consumers (the LSP proxy) can translate coordinates between the
	two files.  The map lives in memory only — there is no on-disk format.

	Lookup strategy:
	  entries is sorted by odin_start.offset at the end of transpile(), so a
	  caller can binary-search for the Span_Entry whose odin range contains a
	  given output offset.
*/
package transpiler

import "core:slice"

// Span_Entry records one correspondence between a generated-Odin byte range
// and its originating Weasel byte range.  Both ends are inclusive of start
// and exclusive of end (half-open), matching the convention of Position as a
// cursor between bytes.
Span_Entry :: struct {
	odin_start:   Position,
	odin_end:     Position,
	weasel_start: Position,
	weasel_end:   Position,
}

// Source_Map is a sorted collection of Span_Entry.  Entries are appended
// during emission in arbitrary order and sorted by odin_start.offset at the
// end of transpile().
Source_Map :: struct {
	entries: [dynamic]Span_Entry,
}

// source_map_destroy releases the backing slice.  Safe to call on a zero-value
// Source_Map.
source_map_destroy :: proc(m: ^Source_Map) {
	delete(m.entries)
	m.entries = nil
}

// advance_position walks text byte-by-byte starting from p and returns the
// resulting Position.  Newlines advance line and reset col to 1; any other
// byte advances offset and col by one.  Used both for precomputing Weasel
// token-internal positions (e.g. the procedure name inside a wider Odin_Text
// token) and for tracking the emitter cursor inside transpile.
advance_position :: proc(p: Position, text: string) -> Position {
	out := p
	for i in 0 ..< len(text) {
		out.offset += 1
		if text[i] == '\n' {
			out.line += 1
			out.col = 1
		} else {
			out.col += 1
		}
	}
	return out
}

// _sort_entries orders entries by odin_start.offset so callers can
// binary-search for the entry covering a given output offset.  Called by
// transpile() at end of emission.
_sort_entries :: proc(m: ^Source_Map) {
	slice.sort_by(m.entries[:], proc(a, b: Span_Entry) -> bool {
		return a.odin_start.offset < b.odin_start.offset
	})
}
