/*
	Weasel corpus test runner.

	Discovers .weasel fixtures under per-language directories (tests/odin,
	tests/c3, …), transpiles each with the matching driver, and diffs the
	result against the corresponding golden file (.odin.golden, .c3.golden, …).

	Usage:
	  odin run tests/ -- [--update] [--language <name>]

	Flags:
	  --update             Overwrite golden files with current transpiler output.
	  --language <name>    Run only the named language (odin, c3). Default: all.
*/
package corpus_tests

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "../transpiler"

Args :: struct {
	update:   bool   `usage:"Overwrite golden files with current transpiler output."`,
	language: string `usage:"Run only this language (e.g. odin, c3). Default: all."`,
}

_Language :: struct {
	name:       string,
	dir:        string,
	golden_ext: string,
	options:    transpiler.Transpile_Options,
}

main :: proc() {
	args: Args
	flags.parse_or_exit(&args, os.args, .Unix)

	languages := [?]_Language{
		{
			name       = "odin",
			dir        = "tests/odin",
			golden_ext = ".odin.golden",
			options    = transpiler.odin_transpile_options(),
		},
		{
			name       = "c3",
			dir        = "tests/c3",
			golden_ext = ".c3.golden",
			options    = transpiler.c3_transpile_options(),
		},
	}

	total_pass, total_fail, total_updated := 0, 0, 0
	langs_run := 0

	for lang in languages {
		if args.language != "" && args.language != lang.name {
			continue
		}

		pattern := fmt.aprintf("%s/*.weasel", lang.dir)
		paths, glob_err := filepath.glob(pattern)
		delete(pattern)

		if glob_err != nil || len(paths) == 0 {
			for p in paths {delete(p)}
			delete(paths)
			if args.language != "" {
				fmt.eprintfln("warning: no .weasel files found in '%s'", lang.dir)
			}
			continue
		}

		langs_run += 1
		fmt.printfln("%s:", lang.name)
		pass, fail, updated := 0, 0, 0

		for weasel_path in paths {
			ok := _run_fixture(weasel_path, lang, args.update)
			switch {
			case args.update && ok:
				updated += 1
			case !args.update && ok:
				pass += 1
			case:
				fail += 1
			}
		}

		for p in paths {delete(p)}
		delete(paths)

		if args.update {
			fmt.printfln("  %d golden file(s) updated, %d failed", updated, fail)
		} else {
			fmt.printfln("  %d passed, %d failed", pass, fail)
		}

		total_pass    += pass
		total_fail    += fail
		total_updated += updated
	}

	if langs_run > 1 {
		if args.update {
			fmt.printfln("total: %d updated, %d failed", total_updated, total_fail)
		} else {
			fmt.printfln("total: %d passed, %d failed", total_pass, total_fail)
		}
	}

	if total_fail > 0 {
		os.exit(1)
	}
}

@(private = "file")
_run_fixture :: proc(weasel_path: string, lang: _Language, update: bool) -> bool {
	base := filepath.base(weasel_path)
	dir  := filepath.dir(weasel_path)
	defer delete(dir)

	stem        := filepath.stem(base)
	golden_name := strings.concatenate([]string{stem, lang.golden_ext})
	defer delete(golden_name)
	golden_path, _ := filepath.join([]string{dir, golden_name}, context.allocator)
	defer delete(golden_path)

	output, ok := _transpile_file(weasel_path, base, lang.options)
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

@(private = "file")
_transpile_file :: proc(
	path, display_name: string,
	options: transpiler.Transpile_Options,
) -> (output: string, ok: bool) {
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

	result, smap, transpile_errs := transpiler.transpile(nodes[:], options)
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

@(private = "file")
_print_diff :: proc(expected, got: string) {
	exp_lines := strings.split_lines(expected)
	got_lines := strings.split_lines(got)
	defer delete(exp_lines)
	defer delete(got_lines)

	n_exp := len(exp_lines)
	n_got := len(got_lines)
	limit := max(n_exp, n_got)
	shown := 0

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
