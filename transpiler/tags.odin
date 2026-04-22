/*
	Weasel element resolution heuristic.

	Decides, for each tag name, whether to emit it as raw HTML or as a
	template proc call. Three rules applied in order:

	  1. Dash rule   — tag name contains '-'  → Raw (custom web component)
	  2. HTML map    — tag name is a standard HTML element → Raw
	  3. Default     — everything else → Component
*/
package transpiler

import "core:strings"

// Tag_Kind is the result of resolving a Weasel element tag name.
Tag_Kind :: enum u8 {
	// Emit as a raw HTML string (standard HTML element or custom web component).
	Raw,
	// Emit as a template proc call.
	Component,
}

// resolve_tag applies the three-rule heuristic and returns the Tag_Kind for
// the given tag name. It is a pure function with no side effects or global
// state; safe to call from any context.
resolve_tag :: proc(name: string) -> Tag_Kind {
	// Rule 1: dash rule — custom web components always emit as raw HTML.
	if strings.contains_rune(name, '-') {
		return .Raw
	}

	// Rule 2: hard-coded WHATWG HTML living-standard element set.
	// Source: https://html.spec.whatwg.org/multipage/#toc-semantics
	switch name {
	case "a", "abbr", "address", "area", "article", "aside", "audio",
	     "b", "base", "bdi", "bdo", "blockquote", "body", "br", "button",
	     "canvas", "caption", "cite", "code", "col", "colgroup",
	     "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt",
	     "em", "embed",
	     "fieldset", "figcaption", "figure", "footer", "form",
	     "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html",
	     "i", "iframe", "img", "input", "ins",
	     "kbd",
	     "label", "legend", "li", "link",
	     "main", "map", "mark", "menu", "meta", "meter",
	     "nav", "noscript",
	     "object", "ol", "optgroup", "option", "output",
	     "p", "picture", "pre", "progress",
	     "q",
	     "rp", "rt", "ruby",
	     "s", "samp", "script", "search", "section", "select", "slot",
	     "small", "source", "span", "strong", "style", "sub", "summary", "sup",
	     "table", "tbody", "td", "template", "textarea", "tfoot", "th", "thead",
	     "time", "title", "tr", "track",
	     "u", "ul",
	     "var", "video",
	     "wbr":
		return .Raw
	}

	// Rule 3: default — treat as a template proc call.
	return .Component
}
