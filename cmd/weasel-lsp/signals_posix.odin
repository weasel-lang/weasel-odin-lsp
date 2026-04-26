//+build !windows
package main

import "core:os"
import "core:thread"
import "core:sys/posix"

_Sig_Watcher :: struct {
	set: posix.sigset_t,
	ols: os.Process,
}

_sig_watcher_thread :: proc(data: rawptr) {
	w := (^_Sig_Watcher)(data)
	sig: posix.Signal
	posix.sigwait(&w.set, &sig)
	_ = os.process_terminate(w.ols)
	os.exit(1)
}

// _watch_and_forward_signals blocks SIGTERM, SIGINT, and SIGHUP in the calling
// thread (the mask is inherited by subsequently created threads), then starts a
// watcher thread that receives any of those signals via sigwait and terminates
// the ols child process before exiting.
_watch_and_forward_signals :: proc(ols: os.Process) {
	w := new(_Sig_Watcher)
	w.ols = ols
	posix.sigemptyset(&w.set)
	posix.sigaddset(&w.set, .SIGTERM)
	posix.sigaddset(&w.set, .SIGINT)
	posix.sigaddset(&w.set, .SIGHUP)
	posix.pthread_sigmask(.BLOCK, &w.set, nil)
	thread.create_and_start_with_data(
		rawptr(w),
		_sig_watcher_thread,
		init_context = context,
		self_cleanup = true,
	)
}
