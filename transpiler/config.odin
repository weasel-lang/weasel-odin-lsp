/*
	Weasel project config loader.

	Searches for a .weasel.json file starting from a given directory and
	walking up to the filesystem root.  Returns resolved Weasel_Config.
	All config fields are optional; absent fields fall back to driver defaults.
*/
package transpiler

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Weasel_Config holds the resolved contents of a .weasel.json config file.
// All fields are optional — absent fields carry the host driver's defaults.
// The caller owns all slice and string fields (use weasel_config_destroy).
Weasel_Config :: struct {
	host:       string,   // "odin" | "c3"; empty == "odin"
	preamble:   []string, // nil means use driver built-in default
	lsp_binary: string,   // empty means use driver built-in default ("ols")
	lsp_args:   []string, // nil means no extra LSP args
}

// _Json_Config is the on-disk JSON shape used by json.unmarshal.
// JSON field names match the Odin field names exactly; no struct tags needed.
// Fields absent from the file stay at their zero values (empty/nil).
@(private = "package")
_Json_Config :: struct {
	host:       string,
	preamble:   []string,
	lsp_binary: string,
	lsp_args:   []string,
}

// Config_Error distinguishes the outcome of load_config.
Config_Error :: enum {
	None,
	Malformed_JSON,
}

// load_config searches for .weasel.json starting at from_dir and walking up
// toward the filesystem root.  Returns Odin defaults and Config_Error.None
// when no file is found.  The caller owns all slice fields in the returned
// Weasel_Config (use weasel_config_destroy to release them).
load_config :: proc(
	from_dir: string,
	allocator := context.allocator,
) -> (cfg: Weasel_Config, cerr: Config_Error) {
	dir := strings.clone(from_dir, context.temp_allocator)
	for {
		elems      := []string{dir, ".weasel.json"}
		path, _    := filepath.join(elems, context.temp_allocator)
		data, rerr := os.read_entire_file(path, context.temp_allocator)
		if rerr == nil {
			raw: _Json_Config
			if jerr := json.unmarshal(data, &raw, allocator = context.temp_allocator); jerr != nil {
				cerr = .Malformed_JSON
				return
			}
			cfg = _resolve_config(raw, allocator)
			return
		}
		parent := filepath.dir(dir, context.temp_allocator)
		if parent == dir {
			break // reached filesystem root
		}
		dir = parent
	}
	// No .weasel.json found — return built-in Odin defaults.
	cfg = odin_default_weasel_config(allocator)
	return
}

// load_config_from_bytes parses a .weasel.json from an in-memory byte slice.
// Used by unit tests and in-memory config injection.
load_config_from_bytes :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (cfg: Weasel_Config, cerr: Config_Error) {
	raw: _Json_Config
	if jerr := json.unmarshal(data, &raw, allocator = context.temp_allocator); jerr != nil {
		cerr = .Malformed_JSON
		return
	}
	cfg = _resolve_config(raw, allocator)
	return
}

// weasel_config_destroy releases all allocations owned by cfg.
weasel_config_destroy :: proc(cfg: ^Weasel_Config, allocator := context.allocator) {
	delete(cfg.host, allocator)
	for s in cfg.preamble {
		delete(s, allocator)
	}
	delete(cfg.preamble, allocator)
	delete(cfg.lsp_binary, allocator)
	for s in cfg.lsp_args {
		delete(s, allocator)
	}
	delete(cfg.lsp_args, allocator)
}

// config_to_transpile_options converts a resolved Weasel_Config to a
// Transpile_Options.  The preamble slice in the returned options points into
// cfg.preamble — do not call weasel_config_destroy while the options are in use.
config_to_transpile_options :: proc(cfg: Weasel_Config) -> Transpile_Options {
	driver: Host_Driver
	switch cfg.host {
	case "c3":
		driver = c3_driver()
	case: // "odin", "" or unknown
		driver = odin_driver()
	}
	return Transpile_Options{
		driver   = driver,
		preamble = cfg.preamble,
	}
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

odin_default_weasel_config :: proc(allocator := context.allocator) -> Weasel_Config {
	preamble := make([]string, len(_odin_default_preamble), allocator)
	for line, i in _odin_default_preamble {
		preamble[i] = strings.clone(line, allocator)
	}
	return Weasel_Config{
		host       = strings.clone("odin", allocator),
		preamble   = preamble,
		lsp_binary = strings.clone("ols", allocator),
		lsp_args   = nil,
	}
}

@(private = "package")
_resolve_config :: proc(raw: _Json_Config, allocator := context.allocator) -> Weasel_Config {
	host := raw.host if len(raw.host) > 0 else "odin"

	preamble: []string
	if len(raw.preamble) > 0 {
		preamble = make([]string, len(raw.preamble), allocator)
		for s, i in raw.preamble {
			preamble[i] = strings.clone(s, allocator)
		}
	} else {
		// Fall back to the driver's built-in default preamble.
		switch host {
		case "c3":
			preamble = make([]string, len(_c3_default_preamble), allocator)
			for line, i in _c3_default_preamble {
				preamble[i] = strings.clone(line, allocator)
			}
		case: // "odin" or unknown
			preamble = make([]string, len(_odin_default_preamble), allocator)
			for line, i in _odin_default_preamble {
				preamble[i] = strings.clone(line, allocator)
			}
		}
	}

	default_lsp := "c3-lsp" if host == "c3" else "ols"
	lsp_binary  := raw.lsp_binary if len(raw.lsp_binary) > 0 else default_lsp

	lsp_args: []string
	if len(raw.lsp_args) > 0 {
		lsp_args = make([]string, len(raw.lsp_args), allocator)
		for s, i in raw.lsp_args {
			lsp_args[i] = strings.clone(s, allocator)
		}
	}

	return Weasel_Config{
		host       = strings.clone(host, allocator),
		preamble   = preamble,
		lsp_binary = strings.clone(lsp_binary, allocator),
		lsp_args   = lsp_args,
	}
}
