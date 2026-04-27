/*
	Weasel corpus test runner.

	Discovers all .weasel files under the corpus directory, runs each through the
	full lexer → parser → transpiler pipeline, and diffs the result against the
	corresponding .odin.golden file.

	Usage:
	  odin run tests/ -- [--update] [--corpus <dir>]

	Flags:
	  --update        Overwrite .odin.golden files with current transpiler output
	                  instead of comparing.  Use this to snapshot new golden files
	                  or after an intentional output change.
	  --corpus <dir>  Path to the corpus directory (default: tests/corpus).
*/
package corpus_tests

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "../transpiler"

Args :: struct {
	update: bool   `usage:"Overwrite .odin.golden files with current transpiler output."`,
	corpus: string `usage:"Path to the corpus directory (default: tests/corpus)."`,
}

main :: proc() {
	args := Args{corpus = "tests/corpus"}
	flags.parse_or_exit(&args, os.args, .Unix)

	pattern := fmt.aprintf("%s/*.weasel", args.corpus)
	defer delete(pattern)

	paths, glob_err := filepath.glob(pattern)

	if glob_err != nil {
		fmt.eprintfln("error: cannot glob '%s'", pattern)
		os.exit(1)
	}
	defer {
		for p in paths {delete(p)}
		delete(paths)
	}

	if len(paths) == 0 {
		fmt.eprintfln("warning: no .weasel files found in '%s'", args.corpus)
	}

	pass, fail, updated := 0, 0, 0

	for weasel_path in paths {
		ok := _run_fixture(weasel_path, args.update)
		switch {
		case args.update && ok:
			updated += 1
		case !args.update && ok:
			pass += 1
		case:
			fail += 1
		}
	}

	if args.update {
		fmt.printfln("corpus: %d golden file(s) updated, %d failed", updated, fail)
	} else {
		fmt.printfln("corpus: %d passed, %d failed", pass, fail)
	}

	if fail > 0 {
		os.exit(1)
	}
}

// _run_fixture transpiles weasel_path and either compares or updates the golden file.
// Returns true on success.
@(private = "file")
_run_fixture :: proc(weasel_path: string, update: bool) -> bool {
	base := filepath.base(weasel_path)
	dir  := filepath.dir(weasel_path)
	defer delete(dir)

	stem        := filepath.stem(base)
	golden_name := strings.concatenate([]string{stem, ".odin.golden"})
	defer delete(golden_name)
	golden_path, _ := filepath.join([]string{dir, golden_name}, context.allocator)
	defer delete(golden_path)

	output, ok := _transpile_file(weasel_path, base)
	if !ok {return false}
	defer delete(transmute([]u8)output)

	if update {
		if err := os.write_entire_file(golden_path, transmute([]u8)output); err != nil {
			fmt.eprintfln("FAIL  %s: cannot write golden: %v", base, err)
			return false
		}
		fmt.printfln("  upd   %s", golden_name)
		return true
	}

	golden_bytes, golden_err := os.read_entire_file(golden_path, context.allocator)
	if golden_err != nil {
		fmt.eprintfln("FAIL  %s: golden file missing — run with --update to create it", base)
		return false
	}
	defer delete(golden_bytes)

	golden_trimmed := strings.trim_right(string(golden_bytes), "\r\n")
	output_trimmed := strings.trim_right(output, "\r\n")

	if output_trimmed == golden_trimmed {
		fmt.printfln("  ok    %s", base)
		return true
	}

	fmt.eprintfln("FAIL  %s: output differs from golden", base)
	_print_diff(string(golden_bytes), output)
	return false
}

// _transpile_file runs the full pipeline on path and returns the emitted Odin source.
// display_name is used in error messages.  Caller owns the returned string.
@(private = "file")
_transpile_file :: proc(path, display_name: string) -> (output: string, ok: bool) {
	src_bytes, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("FAIL  %s: read error: %v", display_name, err)
		return "", false
	}
	defer delete(src_bytes)

	tokens, scan_errs := transpiler.scan(string(src_bytes))
	defer delete(tokens)
	defer delete(scan_errs)

	if len(scan_errs) > 0 {
		fmt.eprintfln("FAIL  %s: scan errors:", display_name)
		for e in scan_errs {
			fmt.eprintfln("       %d:%d: %s", e.pos.line, e.pos.col, e.message)
		}
		return "", false
	}

	nodes, parse_errs := transpiler.parse(tokens[:])
	defer delete(nodes)
	defer delete(parse_errs)

	if len(parse_errs) > 0 {
		fmt.eprintfln("FAIL  %s: parse errors:", display_name)
		for e in parse_errs {
			fmt.eprintfln("       %d:%d: %s", e.pos.line, e.pos.col, e.message)
		}
		return "", false
	}

	result, smap, transpile_errs := transpiler.transpile(nodes[:], transpiler.odin_transpile_options())
	defer delete(transpile_errs)
	defer transpiler.source_map_destroy(&smap)

	if len(transpile_errs) > 0 {
		fmt.eprintfln("FAIL  %s: transpile errors:", display_name)
		for e in transpile_errs {
			fmt.eprintfln("       %d:%d: %s", e.pos.line, e.pos.col, e.message)
		}
		delete(transmute([]u8)result)
		return "", false
	}

	return result, true
}

// _print_diff prints up to 10 line-level differences between expected and got.
@(private = "file")
_print_diff :: proc(expected, got: string) {
	exp_lines := strings.split_lines(expected)
	got_lines := strings.split_lines(got)
	defer delete(exp_lines)
	defer delete(got_lines)

	n_exp  := len(exp_lines)
	n_got  := len(got_lines)
	limit  := max(n_exp, n_got)
	shown  := 0

	for i in 0 ..< limit {
		exp_line := exp_lines[i] if i < n_exp else ""
		got_line := got_lines[i] if i < n_got else ""

		if exp_line != got_line {
			fmt.eprintfln("  line %d:", i + 1)
			fmt.eprintfln("    expected: %q", exp_line)
			fmt.eprintfln("         got: %q", got_line)
			shown += 1
			if shown >= 10 {
				fmt.eprintln("  ... (first 10 differences shown)")
				break
			}
		}
	}
}
