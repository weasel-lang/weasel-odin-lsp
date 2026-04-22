/*
	Source map: correspondence between byte ranges in the generated Odin output
	and their originating `.weasel` source spans.

	The transpiler returns a Source_Map alongside the generated Odin string so
	downstream consumers (the LSP proxy) can translate coordinates between the
	two files.  The map lives in memory only — there is no on-disk format.

	Lookup strategy:
	  After transpile() finishes, entries is sorted by odin_start.offset and a
	  parallel copy weasel_sorted is sorted by weasel_start.offset.  Callers
	  binary-search the appropriate slice via odin_to_weasel / weasel_to_odin.
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
// end of transpile(); weasel_sorted holds the same entries ordered by
// weasel_start.offset for the reverse-lookup direction.
Source_Map :: struct {
	entries:       [dynamic]Span_Entry,
	weasel_sorted: [dynamic]Span_Entry,
}

// source_map_destroy releases the backing slices.  Safe to call on a
// zero-value Source_Map.
source_map_destroy :: proc(m: ^Source_Map) {
	delete(m.entries)
	delete(m.weasel_sorted)
	m.entries = nil
	m.weasel_sorted = nil
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

// _sort_entries orders entries by odin_start.offset and builds the
// weasel_sorted companion slice (same entries, sorted by
// weasel_start.offset).  Called by transpile() at end of emission so that
// both odin_to_weasel and weasel_to_odin can binary-search in O(log n).
_sort_entries :: proc(m: ^Source_Map) {
	slice.sort_by(m.entries[:], proc(a, b: Span_Entry) -> bool {
		return a.odin_start.offset < b.odin_start.offset
	})

	clear(&m.weasel_sorted)
	reserve(&m.weasel_sorted, len(m.entries))
	for entry in m.entries {
		append(&m.weasel_sorted, entry)
	}
	slice.sort_by(m.weasel_sorted[:], proc(a, b: Span_Entry) -> bool {
		return a.weasel_start.offset < b.weasel_start.offset
	})
}

// odin_to_weasel translates an Odin position to its originating Weasel
// position.  Returns (zero, false) when the position falls between spans or
// outside the map's coverage (e.g. inside generated scaffolding such as
// `proc(` that has no Weasel origin).  Runs in O(log n).
odin_to_weasel :: proc(sm: ^Source_Map, pos: Position) -> (Position, bool) {
	entry, ok := _find_span(sm.entries[:], pos.offset, true)
	if !ok {return {}, false}
	return _interpolate(pos, entry.odin_start, entry.weasel_start), true
}

// weasel_to_odin translates a Weasel position to its corresponding position
// in the generated Odin.  Returns (zero, false) when no span covers the
// given Weasel position (e.g. interior of a whitespace-only region or a
// comment that was not emitted).  Runs in O(log n).
weasel_to_odin :: proc(sm: ^Source_Map, pos: Position) -> (Position, bool) {
	entry, ok := _find_span(sm.weasel_sorted[:], pos.offset, false)
	if !ok {return {}, false}
	return _interpolate(pos, entry.weasel_start, entry.odin_start), true
}

// _find_span binary-searches a slice of Span_Entry (sorted by the chosen
// side's start offset) for the first span whose end offset is strictly
// greater than target.  If that span's start offset is <= target the span
// contains the cursor and is returned; otherwise target lies between spans
// and (zero, false) is returned.
@(private = "file")
_find_span :: proc(
	entries: []Span_Entry,
	target: int,
	odin_side: bool,
) -> (Span_Entry, bool) {
	n := len(entries)
	lo, hi := 0, n
	for lo < hi {
		mid := (lo + hi) / 2
		end_off :=
			entries[mid].odin_end.offset if odin_side else entries[mid].weasel_end.offset
		if end_off > target {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	if lo == n {return {}, false}
	entry := entries[lo]
	start_off := entry.odin_start.offset if odin_side else entry.weasel_start.offset
	if target < start_off {return {}, false}
	return entry, true
}

// _interpolate maps pos within [src_start, ...) to the corresponding
// position inside the destination span that begins at dst_start.  The
// translation preserves byte offset and line-break deltas; columns are
// carried over unchanged for any target line past the span's first, and
// interpolated column-wise on the first line.  This is exact for spans
// whose Weasel and Odin text are byte-identical (e.g. Odin passthrough) and
// does the right thing for single-line identifiers of differing length
// (e.g. `card` -> `Card_Props`), where the offset delta still lands inside
// or at the end of the target identifier.
@(private = "file")
_interpolate :: proc(pos, src_start, dst_start: Position) -> Position {
	delta_offset := pos.offset - src_start.offset
	delta_line := pos.line - src_start.line
	result: Position
	result.offset = dst_start.offset + delta_offset
	result.line = dst_start.line + delta_line
	if delta_line == 0 {
		result.col = dst_start.col + (pos.col - src_start.col)
	} else {
		result.col = pos.col
	}
	return result
}
