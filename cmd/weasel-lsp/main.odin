/*
	weasel-lsp — LSP proxy that sits between the editor and `ols` (the Odin
	Language Server).  At this stage it is a pure passthrough: every framed
	LSP message from the editor is forwarded verbatim to `ols`, and every
	framed message from `ols` is forwarded verbatim back to the editor.
	Translation of positions across the Weasel / generated-Odin boundary is
	the job of later tasks (WEASEL-T-0014); this binary's only job is to
	make sure the plumbing is solid.

	Design:
	  - Spawn `ols` with pipes wired to its stdin/stdout (stderr inherits
	    this process's stderr so `ols` logs are still visible).
	  - One I/O thread per direction, each reading framed messages from one
	    side and writing them to the other.  Using the framing layer (not
	    raw byte forwarding) catches protocol errors early and mirrors the
	    future shape of the proxy once T-0014 starts rewriting bodies.
	  - Main thread blocks on `process_wait`.  When `ols` exits, the proxy
	    exits too — with `ols`'s exit code when it's non-zero and an
	    explanatory message on stderr.

	Assumptions:
	  - `ols` is on PATH (override with `--ols <path>`).
	  - Input/output streams are line-framed per the LSP spec
	    (`Content-Length` + blank line + JSON body).
*/
package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:thread"

import "../../lsp"

// A forwarder drains framed messages from src into dst until the source
// reports a clean EOF (peer closed) or an error.  When the forwarder
// detects EOF/error it closes `close_on_end` (if non-nil), which signals
// the opposite side of the proxy that the stream is over.
Forwarder :: struct {
	src:          io.Reader,
	dst:          io.Writer,
	close_on_end: ^os.File,
	name:         string,
}

_forward :: proc(f: ^Forwarder) {
	defer _signal_end(f)

	for {
		body, err := lsp.read_message(f.src)
		switch err {
		case .None:
			w_err := lsp.write_message(f.dst, body)
			delete(body)
			if w_err != .None {
				fmt.eprintfln("weasel-lsp: %s: write error (%v)", f.name, w_err)
				return
			}
		case .EOF:
			return
		case .Unexpected_EOF, .Invalid_Header, .Oversize, .IO:
			fmt.eprintfln("weasel-lsp: %s: read error (%v)", f.name, err)
			return
		}
	}
}

// _signal_end closes the forwarder's half-pipe once the forward loop has
// finished, propagating the end-of-stream to the opposite party.  For the
// editor->ols direction this is what makes ols see EOF on its stdin and
// exit cleanly after the LSP `exit` notification.
_signal_end :: proc(f: ^Forwarder) {
	if f.close_on_end != nil {
		os.close(f.close_on_end)
		f.close_on_end = nil
	}
}

_forward_thread_proc :: proc(data: rawptr) {
	f := (^Forwarder)(data)
	_forward(f)
}

main :: proc() {
	ols_path := "ols"

	i := 1
	for i < len(os.args) {
		a := os.args[i]
		switch a {
		case "--ols":
			if i + 1 >= len(os.args) {
				fmt.eprintln("weasel-lsp: --ols requires a path argument")
				os.exit(2)
			}
			ols_path = os.args[i + 1]
			i += 2
		case "-h", "--help":
			fmt.println("Usage: weasel-lsp [--ols <path>]")
			fmt.println("  --ols <path>   Path to the ols binary (default: 'ols' on PATH).")
			os.exit(0)
		case:
			fmt.eprintfln("weasel-lsp: unknown argument '%s'", a)
			fmt.eprintln("Usage: weasel-lsp [--ols <path>]")
			os.exit(2)
		}
	}

	ols_stdin_r, ols_stdin_w, e1 := os.pipe()
	if e1 != nil {
		fmt.eprintfln("weasel-lsp: cannot create pipe (ols stdin): %v", e1)
		os.exit(1)
	}

	ols_stdout_r, ols_stdout_w, e2 := os.pipe()
	if e2 != nil {
		fmt.eprintfln("weasel-lsp: cannot create pipe (ols stdout): %v", e2)
		os.exit(1)
	}

	handle, spawn_err := os.process_start(os.Process_Desc{
		command = []string{ols_path},
		stdin   = ols_stdin_r,
		stdout  = ols_stdout_w,
		stderr  = os.stderr,
	})
	if spawn_err != nil {
		fmt.eprintfln("weasel-lsp: cannot spawn '%s': %v", ols_path, spawn_err)
		os.exit(1)
	}

	// The child owns its ends now; drop ours so EOF propagates correctly.
	os.close(ols_stdin_r)
	os.close(ols_stdout_w)

	editor_to_ols := Forwarder{
		src          = os.to_reader(os.stdin),
		dst          = os.to_writer(ols_stdin_w),
		close_on_end = ols_stdin_w,
		name         = "editor->ols",
	}
	ols_to_editor := Forwarder{
		src          = os.to_reader(ols_stdout_r),
		dst          = os.to_writer(os.stdout),
		close_on_end = ols_stdout_r,
		name         = "ols->editor",
	}

	// Threads self-clean on exit; we never join them — the main thread
	// blocks on the ols process and os.exit() tears everything down.
	ctx := context
	thread.create_and_start_with_data(
		rawptr(&editor_to_ols),
		_forward_thread_proc,
		init_context = ctx,
		self_cleanup = true,
	)
	thread.create_and_start_with_data(
		rawptr(&ols_to_editor),
		_forward_thread_proc,
		init_context = ctx,
		self_cleanup = true,
	)

	state, wait_err := os.process_wait(handle)
	if wait_err != nil {
		fmt.eprintfln("weasel-lsp: error waiting on ols: %v", wait_err)
		os.exit(1)
	}

	if !state.exited {
		// Should not happen with an infinite wait; treat as abnormal.
		fmt.eprintfln("weasel-lsp: ols did not exit cleanly (state: %v)", state)
		os.exit(1)
	}

	if state.exit_code != 0 {
		fmt.eprintfln("weasel-lsp: ols exited unexpectedly with code %d", state.exit_code)
		os.exit(state.exit_code)
	}

	os.exit(0)
}
