package lsp

import "core:slice"
import "core:testing"

import "../transpiler"

// _make_translator constructs a Source_Map from a literal slice of entries,
// sorts it by odin_start.offset the way the transpiler does at the end of
// emission, and wraps it in a Translator ready for translation queries.
// Pair with the _destroy helper to free both the map and the reverse index.
@(private = "file")
_make_translator :: proc(
	entries: []transpiler.Span_Entry,
) -> (sm: transpiler.Source_Map, t: Translator) {
	sm.entries = make([dynamic]transpiler.Span_Entry, 0, len(entries))
	for e in entries {append(&sm.entries, e)}
	slice.sort_by(sm.entries[:], proc(a, b: transpiler.Span_Entry) -> bool {
		return a.odin_start.offset < b.odin_start.offset
	})
	t = translator_make(&sm)
	return
}

@(private = "file")
_destroy :: proc(sm: ^transpiler.Source_Map, t: ^Translator) {
	translator_destroy(t)
	transpiler.source_map_destroy(sm)
}

// ---------------------------------------------------------------------------
// odin_to_weasel
// ---------------------------------------------------------------------------

// Exact span start — position sits on the very first byte of the span.
@(test)
test_translate_odin_to_weasel_exact_start :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 10, line = 2, col = 1},
			odin_end     = {offset = 15, line = 2, col = 6},
			weasel_start = {offset = 0,  line = 1, col = 1},
			weasel_end   = {offset = 5,  line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	got, ok := odin_to_weasel(&tr, transpiler.Position{offset = 10, line = 2, col = 1})
	testing.expect(t, ok, "exact start should be inside the span")
	testing.expect_value(t, got, transpiler.Position{offset = 0, line = 1, col = 1})
}

// Exact span end — half-open convention: end.offset is NOT inside the span.
// With no adjacent span, the translation returns false.
@(test)
test_translate_odin_to_weasel_exact_end_no_successor :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := odin_to_weasel(&tr, transpiler.Position{offset = 5, line = 1, col = 6})
	testing.expect(t, !ok, "exact end with no successor must return false")
}

// Exact span end — when an adjacent span starts at the same offset, the
// position resolves to the successor span.
@(test)
test_translate_odin_to_weasel_exact_end_has_successor :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 100, line = 10, col = 1},
			weasel_end   = {offset = 105, line = 10, col = 6},
		},
		{
			odin_start   = {offset = 5,  line = 1, col = 6},
			odin_end     = {offset = 10, line = 1, col = 11},
			weasel_start = {offset = 200, line = 20, col = 1},
			weasel_end   = {offset = 205, line = 20, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	got, ok := odin_to_weasel(&tr, transpiler.Position{offset = 5, line = 1, col = 6})
	testing.expect(t, ok, "offset at adjacent boundary should land in successor")
	testing.expect_value(t, got, transpiler.Position{offset = 200, line = 20, col = 1})
}

// Interior of span — a cursor mid-identifier should map to the
// corresponding mid-identifier byte in the other file (column math).
@(test)
test_translate_odin_to_weasel_interior :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 20, line = 3, col = 5},
			odin_end     = {offset = 25, line = 3, col = 10}, // "greet"
			weasel_start = {offset = 0,  line = 1, col = 1},
			weasel_end   = {offset = 5,  line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	// Middle of "greet" in Odin — offset 22, col 7 — should map to offset 2, col 3 in Weasel.
	got, ok := odin_to_weasel(&tr, transpiler.Position{offset = 22, line = 3, col = 7})
	testing.expect(t, ok, "interior of span should be inside")
	testing.expect_value(t, got, transpiler.Position{offset = 2, line = 1, col = 3})
}

// Between spans — a cursor that falls into a gap (generated scaffolding
// like ` :: proc(`) has no Weasel origin and must return false.
@(test)
test_translate_odin_to_weasel_between :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
		{
			odin_start   = {offset = 20, line = 1, col = 21},
			odin_end     = {offset = 30, line = 1, col = 31},
			weasel_start = {offset = 10, line = 2, col = 1},
			weasel_end   = {offset = 20, line = 2, col = 11},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := odin_to_weasel(&tr, transpiler.Position{offset = 12, line = 1, col = 13})
	testing.expect(t, !ok, "between spans must return false")
}

// Before first span.
@(test)
test_translate_odin_to_weasel_before_first :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 10, line = 1, col = 11},
			odin_end     = {offset = 15, line = 1, col = 16},
			weasel_start = {offset = 0,  line = 1, col = 1},
			weasel_end   = {offset = 5,  line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := odin_to_weasel(&tr, transpiler.Position{offset = 5, line = 1, col = 6})
	testing.expect(t, !ok, "offset before first span must return false")
}

// After last span.
@(test)
test_translate_odin_to_weasel_after_last :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := odin_to_weasel(&tr, transpiler.Position{offset = 100, line = 50, col = 1})
	testing.expect(t, !ok, "offset after last span must return false")
}

// Empty map — any lookup returns false.
@(test)
test_translate_odin_to_weasel_empty_map :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{})
	defer _destroy(&sm, &tr)

	_, ok := odin_to_weasel(&tr, transpiler.Position{offset = 0, line = 1, col = 1})
	testing.expect(t, !ok, "lookup on empty map must return false")
}

// Multi-line passthrough — interior position with a line delta.
@(test)
test_translate_odin_to_weasel_multiline_passthrough :: proc(t: ^testing.T) {
	// A passthrough span whose text runs across two lines: byte layout is
	// identical on both sides, so line/col deltas carry over unchanged.
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 8, line = 2, col = 1},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 8, line = 2, col = 1},
		},
	})
	defer _destroy(&sm, &tr)

	// Cursor on the second line of the span.
	got, ok := odin_to_weasel(&tr, transpiler.Position{offset = 6, line = 2, col = 3})
	testing.expect(t, ok, "multi-line interior should be inside")
	testing.expect_value(t, got, transpiler.Position{offset = 6, line = 2, col = 3})
}

// ---------------------------------------------------------------------------
// weasel_to_odin
// ---------------------------------------------------------------------------

// Exact span start on the Weasel side.
@(test)
test_translate_weasel_to_odin_exact_start :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 10, line = 2, col = 1},
			odin_end     = {offset = 15, line = 2, col = 6},
			weasel_start = {offset = 0,  line = 1, col = 1},
			weasel_end   = {offset = 5,  line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	got, ok := weasel_to_odin(&tr, transpiler.Position{offset = 0, line = 1, col = 1})
	testing.expect(t, ok, "exact Weasel start should be inside the span")
	testing.expect_value(t, got, transpiler.Position{offset = 10, line = 2, col = 1})
}

// Exact span end — half-open, no adjacent span → false.
@(test)
test_translate_weasel_to_odin_exact_end_no_successor :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := weasel_to_odin(&tr, transpiler.Position{offset = 5, line = 1, col = 6})
	testing.expect(t, !ok, "exact Weasel end with no successor must return false")
}

// Interior — mid-identifier on the Weasel side maps to the mid-identifier
// Odin position even when the Odin identifier is a different length.
@(test)
test_translate_weasel_to_odin_interior :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			// Odin-side "Card_Props" at offset 100, col 11 — length 10.
			odin_start   = {offset = 100, line = 5, col = 11},
			odin_end     = {offset = 110, line = 5, col = 21},
			// Weasel-side "card" at offset 1, col 2 — length 4.
			weasel_start = {offset = 1, line = 1, col = 2},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	got, ok := weasel_to_odin(&tr, transpiler.Position{offset = 3, line = 1, col = 4})
	testing.expect(t, ok, "interior of Weasel span should be inside")
	// delta_offset = 2, delta_col = 2 → Odin {102, 5, 13}.
	testing.expect_value(t, got, transpiler.Position{offset = 102, line = 5, col = 13})
}

// Between spans — a Weasel offset inside a region with no span (e.g. a
// comment or whitespace region that was not emitted) returns false.
@(test)
test_translate_weasel_to_odin_between :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
		{
			odin_start   = {offset = 5,  line = 1, col = 6},
			odin_end     = {offset = 10, line = 1, col = 11},
			weasel_start = {offset = 10, line = 2, col = 1},
			weasel_end   = {offset = 15, line = 2, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := weasel_to_odin(&tr, transpiler.Position{offset = 7, line = 1, col = 8})
	testing.expect(t, !ok, "Weasel offset in a gap must return false")
}

// Before first span on Weasel side.
@(test)
test_translate_weasel_to_odin_before_first :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0,  line = 1, col = 1},
			odin_end     = {offset = 5,  line = 1, col = 6},
			weasel_start = {offset = 10, line = 1, col = 11},
			weasel_end   = {offset = 15, line = 1, col = 16},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := weasel_to_odin(&tr, transpiler.Position{offset = 5, line = 1, col = 6})
	testing.expect(t, !ok, "Weasel offset before first span must return false")
}

// After last span on Weasel side.
@(test)
test_translate_weasel_to_odin_after_last :: proc(t: ^testing.T) {
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 0, line = 1, col = 1},
			odin_end     = {offset = 5, line = 1, col = 6},
			weasel_start = {offset = 0, line = 1, col = 1},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	_, ok := weasel_to_odin(&tr, transpiler.Position{offset = 200, line = 100, col = 1})
	testing.expect(t, !ok, "Weasel offset after last span must return false")
}

// Weasel → Odin where Odin spans share the same Weasel origin — the
// search must land on a covering span, whichever it is.
@(test)
test_translate_weasel_to_odin_shared_weasel_origin :: proc(t: ^testing.T) {
	// Both spans map the Weasel range [1,5) "card" to different Odin ranges
	// (e.g. the raw tag name and the derived Card_Props identifier).  A
	// query at Weasel offset 2 must produce a position inside one of them.
	sm, tr := _make_translator([]transpiler.Span_Entry{
		{
			odin_start   = {offset = 50,  line = 3, col = 1},
			odin_end     = {offset = 54,  line = 3, col = 5},
			weasel_start = {offset = 1, line = 1, col = 2},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
		{
			odin_start   = {offset = 100, line = 6, col = 1},
			odin_end     = {offset = 110, line = 6, col = 11},
			weasel_start = {offset = 1, line = 1, col = 2},
			weasel_end   = {offset = 5, line = 1, col = 6},
		},
	})
	defer _destroy(&sm, &tr)

	got, ok := weasel_to_odin(&tr, transpiler.Position{offset = 2, line = 1, col = 3})
	testing.expect(t, ok, "Weasel offset covered by both spans should succeed")
	// The returned Odin offset must land inside either covering span.
	inside_a := got.offset >= 50 && got.offset < 54
	inside_b := got.offset >= 100 && got.offset < 110
	testing.expect(t, inside_a || inside_b, "result must lie inside a covering span")
}

// ---------------------------------------------------------------------------
// End-to-end: round-trip via transpile()
// ---------------------------------------------------------------------------

@(test)
test_translate_roundtrip_via_transpile :: proc(t: ^testing.T) {
	// Use a real transpile to build the map, wrap it in a Translator, and
	// verify odin_to_weasel picks up the "greet" span start and the inverse
	// weasel_to_odin returns the Odin start.
	src := "greet :: template() {\n}"
	tokens, scan_errs := transpiler.scan(src)
	defer delete(tokens)
	defer delete(scan_errs)
	nodes, parse_errs := transpiler.parse(tokens[:])
	defer delete(nodes)
	defer delete(parse_errs)
	out, smap, errs := transpiler.transpile(nodes[:])
	defer {
		delete(transmute([]u8)out)
		transpiler.source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	tr := translator_make(&smap)
	defer translator_destroy(&tr)

	// "greet" appears at Weasel offset 0.  In the generated Odin the
	// auto-injected `import "core:io"\n` (17 bytes) precedes the proc, so
	// the Odin offset is 17.
	odin_pos, ok1 := weasel_to_odin(&tr, transpiler.Position{offset = 0, line = 1, col = 1})
	testing.expect(t, ok1, "weasel start of 'greet' should resolve")
	testing.expect_value(t, odin_pos.offset, 17)

	weasel_pos, ok2 := odin_to_weasel(&tr, odin_pos)
	testing.expect(t, ok2, "odin start of 'greet' should resolve back")
	testing.expect_value(t, weasel_pos, transpiler.Position{offset = 0, line = 1, col = 1})
}

// ---------------------------------------------------------------------------
// $() expression position round-trip
// ---------------------------------------------------------------------------

@(test)
test_translate_roundtrip_expr_via_transpile :: proc(t: ^testing.T) {
	// "<p>$(name)</p>" — no template so no import injection.
	// "name" (the inner expression) sits at Weasel offset 5 (after '<p>$(').
	// After transpiling, "name" appears as the identifier in:
	//   __weasel_write_escaped_string(w, name) or_return
	src := "<p>$(name)</p>"
	tokens, scan_errs := transpiler.scan(src)
	defer delete(tokens)
	defer delete(scan_errs)
	nodes, parse_errs := transpiler.parse(tokens[:])
	defer delete(nodes)
	defer delete(parse_errs)
	out, smap, errs := transpiler.transpile(nodes[:])
	defer {
		delete(transmute([]u8)out)
		transpiler.source_map_destroy(&smap)
		delete(errs)
	}
	testing.expect_value(t, len(errs), 0)

	tr := translator_make(&smap)
	defer translator_destroy(&tr)

	// Weasel: "name" starts at offset 5, col 6.
	weasel_expr := transpiler.Position{offset = 5, line = 1, col = 6}
	odin_pos, ok1 := weasel_to_odin(&tr, weasel_expr)
	testing.expect(t, ok1, "weasel position inside $() should resolve to odin")
	// The Odin text at that offset must be 'n' (start of "name").
	testing.expect(
		t,
		odin_pos.offset < len(out) && out[odin_pos.offset] == 'n',
		"odin position should point at 'n' of 'name' in write call",
	)

	// Round-trip: the Odin position must map back to exactly the same Weasel start.
	weasel_back, ok2 := odin_to_weasel(&tr, odin_pos)
	testing.expect(t, ok2, "odin expression position should round-trip back to weasel")
	testing.expect_value(t, weasel_back, weasel_expr)
}

@(test)
test_translate_expr_range_end_via_transpile :: proc(t: ^testing.T) {
	// The exclusive end of the "name" span (Weasel offset 9, after "name")
	// must translate via the range-end variant, mapping to the exclusive
	// end of the Odin "name" span.
	src := "<p>$(name)</p>"
	tokens, scan_errs := transpiler.scan(src)
	defer delete(tokens)
	defer delete(scan_errs)
	nodes, parse_errs := transpiler.parse(tokens[:])
	defer delete(nodes)
	defer delete(parse_errs)
	out, smap, errs := transpiler.transpile(nodes[:])
	defer {
		delete(transmute([]u8)out)
		transpiler.source_map_destroy(&smap)
		delete(errs)
	}
	testing.expect_value(t, len(errs), 0)

	tr := translator_make(&smap)
	defer translator_destroy(&tr)

	// Weasel end of "name" is at offset 9.
	weasel_end := transpiler.Position{offset = 9, line = 1, col = 10}
	odin_end, ok := weasel_to_odin_range_end(&tr, weasel_end)
	testing.expect(t, ok, "weasel range end of $() expression should resolve")
	// The character just before this Odin end must be 'e' (last byte of "name").
	testing.expect(
		t,
		odin_end.offset > 0 && odin_end.offset <= len(out) && out[odin_end.offset - 1] == 'e',
		"odin range end should point one past the 'e' of 'name'",
	)
}
