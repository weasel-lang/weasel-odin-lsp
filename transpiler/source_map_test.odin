package transpiler

import "core:strings"
import "core:testing"

// _spt_with_map scans, parses, and transpiles src and returns everything
// including the source map so tests can make assertions against it.
@(private = "file")
_spt_with_map :: proc(
	src: string,
) -> (out: string, smap: Source_Map, errs: [dynamic]Transpile_Error) {
	tokens, scan_errs := scan(src)
	defer delete(scan_errs)
	defer delete(tokens)
	nodes, parse_errs := parse(tokens[:])
	defer delete(parse_errs)
	defer delete(nodes)
	return transpile(nodes[:])
}

// _find_span_for_odin_text returns the first Span_Entry whose odin range
// slices out the given literal, or (zero, false) if none matches.
@(private = "file")
_find_span_for_odin_text :: proc(
	output: string,
	smap: Source_Map,
	literal: string,
) -> (Span_Entry, bool) {
	for entry in smap.entries {
		if entry.odin_start.offset < 0 {continue}
		if entry.odin_end.offset > len(output) {continue}
		if output[entry.odin_start.offset:entry.odin_end.offset] == literal {
			return entry, true
		}
	}
	return Span_Entry{}, false
}

// ---------------------------------------------------------------------------
// Basic position tracking
// ---------------------------------------------------------------------------

@(test)
test_source_map_advance_position_ascii :: proc(t: ^testing.T) {
	// Single-line advance: col and offset step by one, line stays put.
	got := advance_position(Position{offset = 5, line = 1, col = 6}, "abc")
	testing.expect_value(t, got, Position{offset = 8, line = 1, col = 9})
}

@(test)
test_source_map_advance_position_newline :: proc(t: ^testing.T) {
	// Newline resets column to 1 and advances line.
	got := advance_position(Position{offset = 0, line = 1, col = 1}, "ab\ncd")
	testing.expect_value(t, got, Position{offset = 5, line = 2, col = 3})
}

// ---------------------------------------------------------------------------
// Odin passthrough (non-template file) gets a span covering the whole text
// ---------------------------------------------------------------------------

@(test)
test_source_map_odin_passthrough_spans :: proc(t: ^testing.T) {
	src := "x := 42\n"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, len(smap.entries) >= 1, "expected at least one span for passthrough Odin")

	// The passthrough Odin span must cover the entire source verbatim.
	found := false
	for entry in smap.entries {
		if entry.odin_start.offset == 0 && entry.odin_end.offset == len(out) {
			testing.expect_value(t, entry.weasel_start, Position{offset = 0, line = 1, col = 1})
			testing.expect_value(t, entry.weasel_end, Position{offset = 8, line = 2, col = 1})
			found = true
			break
		}
	}
	testing.expect(t, found, "expected a span covering the full passthrough region")
}

// ---------------------------------------------------------------------------
// Procedure name span
// ---------------------------------------------------------------------------

@(test)
test_source_map_procedure_name :: proc(t: ^testing.T) {
	// Template at the start of the file: proc name must map to Weasel "greet".
	src := "greet :: template() {\n}"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "greet")
	testing.expect(t, found, "no span entry covers the 'greet' proc name in the output")

	// Odin side: "greet" is at the start of the output.
	testing.expect_value(t, entry.odin_start, Position{offset = 0, line = 1, col = 1})
	testing.expect_value(t, entry.odin_end, Position{offset = 5, line = 1, col = 6})
	// Weasel side: same — "greet" starts at offset 0.
	testing.expect_value(t, entry.weasel_start, Position{offset = 0, line = 1, col = 1})
	testing.expect_value(t, entry.weasel_end, Position{offset = 5, line = 1, col = 6})
}

@(test)
test_source_map_procedure_name_after_prefix :: proc(t: ^testing.T) {
	// Import prefix before the declaration shifts the proc name in both files.
	src := "import \"core:io\"\n\ngreet :: template() {\n}"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "greet")
	testing.expect(t, found, "no span entry covers 'greet'")

	// Weasel: "greet" starts on line 3 after the blank line.
	testing.expect_value(t, entry.weasel_start.line, 3)
	testing.expect_value(t, entry.weasel_start.col, 1)
	// Odin: same offset — the import prefix was preserved verbatim.
	odin_greet := strings.index(out, "greet")
	testing.expect(t, odin_greet >= 0, "greet not in output")
	testing.expect_value(t, entry.odin_start.offset, odin_greet)
}

// ---------------------------------------------------------------------------
// Parameter list span
// ---------------------------------------------------------------------------

@(test)
test_source_map_parameter_list :: proc(t: ^testing.T) {
	src := "greet :: template(name: string) {\n}"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "name: string")
	testing.expect(t, found, "no span entry covers the parameter list 'name: string'")

	// Weasel: "name: string" begins at the byte after the opening '('.
	open_paren := strings.index(src, "(")
	testing.expect_value(t, entry.weasel_start.offset, open_paren + 1)
}

// ---------------------------------------------------------------------------
// Inline expression identifier references
// ---------------------------------------------------------------------------

@(test)
test_source_map_inline_expression :: proc(t: ^testing.T) {
	src := "<p>{name}</p>"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "name")
	testing.expect(t, found, "no span entry covers the inline expr identifier 'name'")

	// Weasel: "name" sits at offset 4 (after '<p>{').
	testing.expect_value(t, entry.weasel_start, Position{offset = 4, line = 1, col = 5})
	testing.expect_value(t, entry.weasel_end, Position{offset = 8, line = 1, col = 9})
}

@(test)
test_source_map_dotted_inline_expression :: proc(t: ^testing.T) {
	src := "<p>{user.name}</p>"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "user.name")
	testing.expect(t, found, "no span entry covers the dotted inline expr 'user.name'")
	testing.expect_value(t, entry.weasel_start.offset, 4)
	testing.expect_value(t, entry.weasel_end.offset, 13)
}

// ---------------------------------------------------------------------------
// Component element name
// ---------------------------------------------------------------------------

@(test)
test_source_map_component_tag_name :: proc(t: ^testing.T) {
	src := "<card />"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "card")
	testing.expect(t, found, "no span entry covers the component tag 'card'")

	// Weasel: "card" begins at offset 1 (after '<').
	testing.expect_value(t, entry.weasel_start, Position{offset = 1, line = 1, col = 2})
	testing.expect_value(t, entry.weasel_end, Position{offset = 5, line = 1, col = 6})
}

@(test)
test_source_map_component_tag_with_props :: proc(t: ^testing.T) {
	// The props struct name (Card_Props) is synthesised from the tag; its
	// Weasel origin must still point back to the 'card' literal.
	src := `<card title="x" />`
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "Card_Props")
	testing.expect(t, found, "no span entry covers the derived 'Card_Props' identifier")
	testing.expect_value(t, entry.weasel_start.offset, 1)
	// The mapped Weasel range spans 'card' (4 bytes), not 'Card_Props' (10).
	testing.expect_value(t, entry.weasel_end.offset, 5)
}

// ---------------------------------------------------------------------------
// Sorted invariant and completeness
// ---------------------------------------------------------------------------

@(test)
test_source_map_entries_sorted_by_odin_offset :: proc(t: ^testing.T) {
	// Run a moderately complex fixture through and verify the entries slice
	// is monotonically non-decreasing in odin_start.offset.
	src := "greet :: template(name: string) {\n<p>Hello, {name}!</p>\n}"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)
	testing.expect(t, len(smap.entries) >= 3, "expected at least 3 span entries for this fixture")

	for i in 1 ..< len(smap.entries) {
		prev := smap.entries[i - 1].odin_start.offset
		cur  := smap.entries[i].odin_start.offset
		testing.expectf(t, prev <= cur, "entries not sorted: [%d]=%d, [%d]=%d", i - 1, prev, i, cur)
	}
}

@(test)
test_source_map_fixture_covers_key_identifiers :: proc(t: ^testing.T) {
	// All LSP-relevant identifiers in this fixture must produce at least one
	// span entry whose odin slice matches them exactly.
	src := "greet :: template(name: string) {\n<p>Hello, {name}!</p>\n}"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}
	testing.expect_value(t, len(errs), 0)

	expected := []string{"greet", "name: string", "name"}
	for literal in expected {
		_, found := _find_span_for_odin_text(out, smap, literal)
		testing.expectf(t, found, "no span entry covers '%s' in generated Odin", literal)
	}
}

// ---------------------------------------------------------------------------
// Odin_Block (control-flow) head mapping
// ---------------------------------------------------------------------------

@(test)
test_source_map_control_flow_head :: proc(t: ^testing.T) {
	// The for-loop head ("for item in items ") must map back to the
	// corresponding Weasel byte range (inside the {...} block).
	src := "<ul>{for item in items { <li></li>\n}}</ul>"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	entry, found := _find_span_for_odin_text(out, smap, "for item in items ")
	testing.expect(t, found, "no span entry covers the for-loop head")

	// Weasel: the head starts right after the outer '{' at offset 5.
	testing.expect_value(t, entry.weasel_start.offset, 5)
}

// ---------------------------------------------------------------------------
// Dynamic attribute expressions on components (identifier references)
// ---------------------------------------------------------------------------

@(test)
test_source_map_dynamic_attr_expression :: proc(t: ^testing.T) {
	// The identifier 'n' inside size={n} must be mapped back to the Weasel
	// source, even when used as a component attribute.
	src := "<card size={n} />"
	out, smap, errs := _spt_with_map(src)
	defer {
		delete(transmute([]u8)out)
		source_map_destroy(&smap)
		delete(errs)
	}

	testing.expect_value(t, len(errs), 0)

	_, found := _find_span_for_odin_text(out, smap, "n")
	testing.expect(t, found, "no span entry covers the dynamic attr expression 'n'")
}
