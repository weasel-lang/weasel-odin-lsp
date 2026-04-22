/*
	LSP-side index over a transpiler Source_Map.

	The transpiler returns its Span_Entry slice sorted by odin_start.offset so
	ols responses (keyed by Odin positions) can be rewritten cheaply.  LSP
	requests from the editor arrive in Weasel coordinates and need the inverse
	lookup, which requires a second ordering of the same entries keyed by
	weasel_start.offset.  This file owns that second ordering and the
	translation procedures that binary-search the two orderings.

	Keeping this out of the transpiler means the CLI (`weasel generate`)
	doesn't build an index it never uses.  The proxy builds a Translator
	alongside each in-memory transpile result and reuses it for every LSP
	request against that document.
*/
package lsp

import "core:slice"

import "../transpiler"

// Translator bundles the two orderings over a Source_Map's entries.
// odin_sorted is borrowed from the Source_Map (no copy); weasel_sorted is an
// owned copy sorted by weasel_start.offset.
//
// The Translator holds a direct slice into Source_Map.entries, so the
// owning Source_Map must outlive the Translator.
Translator :: struct {
	odin_sorted:   []transpiler.Span_Entry,
	weasel_sorted: [dynamic]transpiler.Span_Entry,
}

// translator_make builds a Translator over sm.  The returned struct shares
// its odin_sorted slice with sm.entries and owns its weasel_sorted.  Pair
// with translator_destroy.
translator_make :: proc(
	sm: ^transpiler.Source_Map,
	allocator := context.allocator,
) -> Translator {
	t: Translator
	t.odin_sorted = sm.entries[:]
	t.weasel_sorted = make([dynamic]transpiler.Span_Entry, 0, len(sm.entries), allocator)
	for entry in sm.entries {
		append(&t.weasel_sorted, entry)
	}
	slice.sort_by(t.weasel_sorted[:], proc(a, b: transpiler.Span_Entry) -> bool {
		return a.weasel_start.offset < b.weasel_start.offset
	})
	return t
}

// translator_destroy releases the owned weasel_sorted slice.  The borrowed
// odin_sorted slice is left alone — it belongs to the Source_Map.  Safe to
// call on a zero-value Translator.
translator_destroy :: proc(t: ^Translator) {
	delete(t.weasel_sorted)
	t.weasel_sorted = nil
	t.odin_sorted = nil
}

// odin_to_weasel translates an Odin position to its originating Weasel
// position.  Returns (zero, false) when the position falls between spans or
// outside the map's coverage (e.g. inside generated scaffolding such as
// `proc(` that has no Weasel origin).  Runs in O(log n).
odin_to_weasel :: proc(
	t: ^Translator,
	pos: transpiler.Position,
) -> (transpiler.Position, bool) {
	entry, ok := _find_span(t.odin_sorted, pos.offset, true)
	if !ok {return {}, false}
	return _interpolate(pos, entry.odin_start, entry.weasel_start), true
}

// weasel_to_odin translates a Weasel position to its corresponding position
// in the generated Odin.  Returns (zero, false) when no span covers the
// given Weasel position (e.g. interior of a whitespace-only region or a
// comment that was not emitted).  Runs in O(log n).
weasel_to_odin :: proc(
	t: ^Translator,
	pos: transpiler.Position,
) -> (transpiler.Position, bool) {
	entry, ok := _find_span(t.weasel_sorted[:], pos.offset, false)
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
	entries: []transpiler.Span_Entry,
	target: int,
	odin_side: bool,
) -> (transpiler.Span_Entry, bool) {
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
_interpolate :: proc(
	pos, src_start, dst_start: transpiler.Position,
) -> transpiler.Position {
	delta_offset := pos.offset - src_start.offset
	delta_line := pos.line - src_start.line
	result: transpiler.Position
	result.offset = dst_start.offset + delta_offset
	result.line = dst_start.line + delta_line
	if delta_line == 0 {
		result.col = dst_start.col + (pos.col - src_start.col)
	} else {
		result.col = pos.col
	}
	return result
}
