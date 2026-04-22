/*
	weasel CLI — entry point for the `weasel generate` command.

	Usage:
	  weasel generate [--out <dir>] [--force] <file.weasel>...

	Each input .weasel file is processed through the lexer → parser → transpiler
	pipeline and the resulting Odin source is written alongside the input file
	(or to --out <dir> when specified).  Files whose output is already up-to-date
	(output mtime ≥ input mtime) are skipped unless --force is passed.
*/
package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "../transpiler"

// Generate_Args defines the flags accepted by `weasel generate`.
// Unrecognised positional arguments (the .weasel input files) land in overflow.
Generate_Args :: struct {
	out:      string          `usage:"Write output files to this directory instead of alongside the source."`,
	force:    bool            `usage:"Regenerate files even if the output is already up-to-date."`,
	overflow: [dynamic]string `usage:"Input .weasel files to process."`,
}

main :: proc() {
	// The first argument must be the "generate" subcommand, for now.
	if len(os.args) < 2 || os.args[1] != "generate" {
		if len(os.args) >= 2 {
			fmt.eprintfln("weasel: unknown command '%s'", os.args[1])
		}
		fmt.eprintln("Usage: weasel generate [--out <dir>] [--force] <file.weasel>...")
		os.exit(1)
	}

	// Build a synthetic args slice so that parse_or_exit displays the correct
	// program name ("weasel generate") in usage and error output.
	// Element [0] is treated as the program name; the real flags follow.
	synthetic := make([]string, max(1, len(os.args) - 1))
	defer delete(synthetic)
	synthetic[0] = "weasel generate"

	if len(os.args) > 2 {
		copy(synthetic[1:], os.args[2:])
	}

	cli := Generate_Args{}
	defer delete(cli.overflow)
	flags.parse_or_exit(&cli, synthetic, .Unix)

	if len(cli.overflow) == 0 {
		fmt.eprintln("weasel: no input files specified")
		fmt.eprintln("Usage: weasel generate [--out <dir>] [--force] <file.weasel>...")
		os.exit(1)
	}

	skipped, generated, failed := 0, 0, 0

	for in_path in cli.overflow {
		out_path := _out_path(in_path, cli.out)
		defer delete(out_path)

		if !cli.force && _is_up_to_date(in_path, out_path) {
			fmt.printfln("  skip  %s", in_path)
			skipped += 1
			continue
		}

		if _generate_file(in_path, out_path) {
			fmt.printfln("  gen   %s -> %s", in_path, out_path)
			generated += 1
		} else {
			failed += 1
		}
	}

	if failed > 0 {
		fmt.eprintfln("weasel: generate failed (%d error(s))", failed)
		os.exit(1)
	}

	fmt.printfln("weasel: %d generated, %d skipped", generated, skipped)
}

// _out_path computes the output .odin path for in_path.
// When out_dir is non-empty the file is placed there; otherwise alongside the input.
// The returned string is heap-allocated; the caller must delete it.
_out_path :: proc(in_path, out_dir: string) -> string {
	// filepath.stem strips the directory and the last extension:
	//   "templates/card.weasel" → "card"
	stem := filepath.stem(in_path)
	out_name := strings.concatenate({stem, ".odin"})
	defer delete(out_name)

	if out_dir != "" {
		result, _ := filepath.join([]string{out_dir, out_name}, context.allocator)
		return result
	}

	dir := filepath.dir(in_path)
	defer delete(dir)
	result, _ := filepath.join([]string{dir, out_name}, context.allocator)
	return result
}

// _is_up_to_date returns true when out_path exists and its modification time
// is not earlier than in_path's modification time.
_is_up_to_date :: proc(in_path, out_path: string) -> bool {
	in_info, in_err := os.stat(in_path, context.allocator)
	if in_err != nil {
		return false
	}
	defer os.file_info_delete(in_info, context.allocator)

	out_info, out_err := os.stat(out_path, context.allocator)
	if out_err != nil {
		return false
	}
	defer os.file_info_delete(out_info, context.allocator)

	in_ns  := time.time_to_unix_nano(in_info.modification_time)
	out_ns := time.time_to_unix_nano(out_info.modification_time)
	return out_ns >= in_ns
}

// _generate_file runs the full pipeline on in_path and writes the result to out_path.
// Diagnostic messages are printed to stderr.  Returns true on success.
_generate_file :: proc(in_path, out_path: string) -> bool {
	// --- Read source ---
	data, read_err := os.read_entire_file(in_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("weasel: cannot read '%s': %v", in_path, read_err)
		return false
	}
	defer delete(data)
	src := string(data)

	// --- Lex ---
	tokens, scan_errs := transpiler.scan(src)
	defer delete(tokens)
	defer delete(scan_errs)

	if len(scan_errs) > 0 {
		for e in scan_errs {
			fmt.eprintfln("%s:%d:%d: error: %s", in_path, e.pos.line, e.pos.col, e.message)
		}
		return false
	}

	// --- Parse ---
	nodes, parse_errs := transpiler.parse(tokens[:])
	defer delete(nodes)
	defer delete(parse_errs)

	if len(parse_errs) > 0 {
		for e in parse_errs {
			fmt.eprintfln("%s:%d:%d: error: %s", in_path, e.pos.line, e.pos.col, e.message)
		}
		return false
	}

	// --- Transpile ---
	source, transpile_errs := transpiler.transpile(nodes[:])
	defer delete(transpile_errs)
	defer delete(transmute([]u8)source)

	if len(transpile_errs) > 0 {
		for e in transpile_errs {
			fmt.eprintfln("%s:%d:%d: error: %s", in_path, e.pos.line, e.pos.col, e.message)
		}
		return false
	}

	// --- Write output ---
	write_err := os.write_entire_file(out_path, transmute([]u8)source)

	if write_err != nil {
		fmt.eprintfln("weasel: cannot write '%s': %v", out_path, write_err)
		return false
	}

	return true
}
