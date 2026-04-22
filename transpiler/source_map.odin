/*
	Source map: correspondence between byte ranges in the generated Odin output
	and their originating `.weasel` source spans.

	The transpiler returns a Source_Map alongside the generated Odin string.
	Entries are emitted in arbitrary order and sorted by odin_start.offset at
	the end of transpile(); that ordering is the natural output of emission and
	costs nothing to maintain.

	The map is pure data — no lookup APIs are defined here.  Translation
	between Weasel and Odin positions lives in the LSP layer (package lsp),
	which builds a secondary index keyed by weasel_start.offset.  Keeping the
	reverse index out of the transpiler means the CLI (`weasel generate`)
	doesn't pay to build something it never uses.
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

// Source_Map is a sorted collection of Span_Entry, ordered by
// odin_start.offset.  The transpiler appends entries during emission and
// _sort_entries() establishes the ordering once emission is complete.
Source_Map :: struct {
	entries: [dynamic]Span_Entry,
}

// source_map_destroy releases the backing slice.  Safe to call on a
// zero-value Source_Map.
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

// _sort_entries orders entries by odin_start.offset.  Called by transpile()
// at the end of emission; the resulting slice is what the LSP layer indexes
// into when building its Weasel-keyed translation table.
_sort_entries :: proc(m: ^Source_Map) {
	slice.sort_by(m.entries[:], proc(a, b: Span_Entry) -> bool {
		return a.odin_start.offset < b.odin_start.offset
	})
}
