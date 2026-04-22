package transpiler

import "core:testing"

// ── Rule 1: dash rule ────────────────────────────────────────────────────────

@(test)
test_dash_rule_simple :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_tag("my-component"), Tag_Kind.Raw)
}

@(test)
test_dash_rule_multiple_dashes :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_tag("x-foo-bar"), Tag_Kind.Raw)
}

@(test)
test_dash_rule_leading_dash :: proc(t: ^testing.T) {
	// Unusual but the rule fires on any '-' present.
	testing.expect_value(t, resolve_tag("-weird"), Tag_Kind.Raw)
}

// ── Rule 2: known HTML elements → Raw ───────────────────────────────────────

@(test)
test_common_html_tags :: proc(t: ^testing.T) {
	common := []string{"div", "span", "p", "a", "ul", "li", "h1", "h2", "h3", "input", "button"}
	for tag in common {
		testing.expect_value(t, resolve_tag(tag), Tag_Kind.Raw)
	}
}

@(test)
test_uncommon_html_tags :: proc(t: ^testing.T) {
	uncommon := []string{
		"details", "dialog", "summary", "canvas", "picture", "slot",
		"datalist", "meter", "progress", "output", "search", "hgroup",
		"bdi", "bdo", "wbr", "figcaption", "figure",
	}
	for tag in uncommon {
		testing.expect_value(t, resolve_tag(tag), Tag_Kind.Raw)
	}
}

@(test)
test_html_template_tag :: proc(t: ^testing.T) {
	// The HTML <template> element is Raw; Weasel template procs must not be
	// named "template" to avoid the silent collision described in WEASEL-A-0002.
	testing.expect_value(t, resolve_tag("template"), Tag_Kind.Raw)
}

@(test)
test_media_html_tags :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_tag("audio"), Tag_Kind.Raw)
	testing.expect_value(t, resolve_tag("video"), Tag_Kind.Raw)
	testing.expect_value(t, resolve_tag("source"), Tag_Kind.Raw)
	testing.expect_value(t, resolve_tag("track"), Tag_Kind.Raw)
}

@(test)
test_table_html_tags :: proc(t: ^testing.T) {
	tags := []string{"table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption", "col", "colgroup"}
	for tag in tags {
		testing.expect_value(t, resolve_tag(tag), Tag_Kind.Raw)
	}
}

// ── Rule 3: unknown tags → Component ────────────────────────────────────────

@(test)
test_component_tag :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_tag("card"), Tag_Kind.Component)
}

@(test)
test_component_tag_underscore :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_tag("task_item"), Tag_Kind.Component)
}

@(test)
test_package_qualified_resolves_component :: proc(t: ^testing.T) {
	// Package-qualified names (e.g. "ui.card") contain neither '-' nor any
	// HTML tag name, so they resolve to Component.
	testing.expect_value(t, resolve_tag("ui.card"), Tag_Kind.Component)
}

@(test)
test_empty_string :: proc(t: ^testing.T) {
	// Empty string is not an HTML tag — falls through to Component.
	testing.expect_value(t, resolve_tag(""), Tag_Kind.Component)
}

@(test)
test_near_miss_html :: proc(t: ^testing.T) {
	// "divv", "spann", "pparagraph" are not HTML tags.
	testing.expect_value(t, resolve_tag("divv"), Tag_Kind.Component)
	testing.expect_value(t, resolve_tag("spann"), Tag_Kind.Component)
}
