/*
	weasel-lsp — LSP proxy that sits between the editor and `ols` (the Odin
	Language Server).

	Data flow:
	  editor ──► proxy ──► ols           (editor-to-ols path: .weasel
	                                       lifecycle notifications are
	                                       re-transpiled and replaced with
	                                       matching .odin-URI notifications;
	                                       position-bearing requests
	                                       addressed to a known .weasel
	                                       document are rewritten
	                                       Weasel→Odin before forwarding.)
	  editor ◄── proxy ◄── ols           (ols-to-editor path: responses to
	                                       tracked requests and
	                                       publishDiagnostics notifications
	                                       are rewritten Odin→Weasel before
	                                       reaching the editor; unrelated
	                                       frames pass through.)

	Design:
	  - Spawn `ols` with pipes wired to its stdin/stdout (stderr inherits
	    this process's stderr so `ols` logs are still visible).
	  - Two I/O threads, one per direction:
	      • editor→ols funnels every editor message through
	        `lsp.proxy_process_editor_message`, which either forwards
	        verbatim or replaces the body with a synthesized message
	        (e.g. didOpen for the shadow .odin URI, or a re-marshaled
	        request with Weasel→Odin coordinates).
	      • ols→editor funnels every ols message through
	        `lsp.proxy_process_ols_message`, which rewrites Odin→Weasel
	        coordinates and URIs for responses to tracked requests and
	        for publishDiagnostics targeting our shadow documents.
	        Writes serialise through `proxy_write_to_editor`, which
	        also protects proxy-initiated frames (e.g.
	        publishDiagnostics for the Weasel side of a broken
	        keystroke).
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

// _Editor_To_Ols drains framed editor messages through the proxy, which
// handles `.weasel` lifecycle notifications and forwards everything else
// verbatim to `ols`.
_Editor_To_Ols :: struct {
	src:          io.Reader,
	close_on_end: ^os.File,
	proxy:        ^lsp.Proxy,
}

// _Ols_To_Editor forwards framed `ols` messages back to the editor.  Writes
// go through `lsp.proxy_write_to_editor` so they don't interleave with
// proxy-initiated frames.
_Ols_To_Editor :: struct {
	src:          io.Reader,
	close_on_end: ^os.File,
	proxy:        ^lsp.Proxy,
}

_forward_editor_to_ols :: proc(f: ^_Editor_To_Ols) {
	defer _signal_end(f.close_on_end)

	for {
		body, err := lsp.read_message(f.src)

		switch err {
		case .None:
			w_err := lsp.proxy_process_editor_message(f.proxy, body)
			delete(body)

			if w_err != .None {
				fmt.eprintfln("weasel-lsp: editor->ols: write error (%v)", w_err)
				return
			}
		case .EOF:
			return
		case .Unexpected_EOF, .Invalid_Header, .Oversize, .IO:
			fmt.eprintfln("weasel-lsp: editor->ols: read error (%v)", err)
			return
		}
	}
}

_forward_ols_to_editor :: proc(f: ^_Ols_To_Editor) {
	defer _signal_end(f.close_on_end)

	for {
		body, err := lsp.read_message(f.src)

		switch err {
		case .None:
			w_err := lsp.proxy_process_ols_message(f.proxy, body)
			delete(body)

			if w_err != .None {
				fmt.eprintfln("weasel-lsp: ols->editor: write error (%v)", w_err)
				return
			}
		case .EOF:
			return
		case .Unexpected_EOF, .Invalid_Header, .Oversize, .IO:
			fmt.eprintfln("weasel-lsp: ols->editor: read error (%v)", err)
			return
		}
	}
}

// _signal_end closes the forwarder's half-pipe once its forward loop has
// finished, propagating the end-of-stream to the opposite party.  For the
// editor->ols direction this is what makes ols see EOF on its stdin and
// exit cleanly after the LSP `exit` notification.
_signal_end :: proc(fd: ^os.File) {
	if fd != nil {os.close(fd)}
}

_editor_to_ols_thread :: proc(data: rawptr) {
	f := (^_Editor_To_Ols)(data)
	_forward_editor_to_ols(f)
}

_ols_to_editor_thread :: proc(data: rawptr) {
	f := (^_Ols_To_Editor)(data)
	_forward_ols_to_editor(f)
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

	// Shared proxy state: both threads consult the same document map and
	// funnel editor-bound writes through the same mutex.
	proxy: lsp.Proxy
	lsp.proxy_init(&proxy, os.to_writer(ols_stdin_w), os.to_writer(os.stdout))

	editor_to_ols := _Editor_To_Ols{
		src          = os.to_reader(os.stdin),
		close_on_end = ols_stdin_w,
		proxy        = &proxy,
	}
	ols_to_editor := _Ols_To_Editor{
		src          = os.to_reader(ols_stdout_r),
		close_on_end = ols_stdout_r,
		proxy        = &proxy,
	}

	// Threads self-clean on exit; we never join them — the main thread
	// blocks on the ols process and os.exit() tears everything down.
	ctx := context
	thread.create_and_start_with_data(
		rawptr(&editor_to_ols),
		_editor_to_ols_thread,
		init_context = ctx,
		self_cleanup = true,
	)
	thread.create_and_start_with_data(
		rawptr(&ols_to_editor),
		_ols_to_editor_thread,
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
