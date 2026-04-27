package transpiler

import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// load_config_from_bytes — covers parsing without file I/O
// ---------------------------------------------------------------------------

@(test)
test_config_no_file_returns_odin_defaults :: proc(t: ^testing.T) {
	// load_config_from_bytes with nil data should fail; test defaults via
	// direct helper instead.
	cfg := odin_default_weasel_config()
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cfg.host, "odin")
	testing.expect_value(t, cfg.lsp_binary, "ols")
	testing.expect_value(t, len(cfg.preamble), 2)
	testing.expect(t, strings.contains(cfg.preamble[0], "core:io"), "first preamble line should contain core:io")
	testing.expect(t, strings.contains(cfg.preamble[1], "weasel"), "second preamble line should contain weasel")
}

@(test)
test_config_full_json :: proc(t: ^testing.T) {
	json := `{"host":"odin","preamble":["import \"core:io\"","import \"lib:weasel\""],"lsp_binary":"ols","lsp_args":["--debug"]}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, cfg.host, "odin")
	testing.expect_value(t, cfg.lsp_binary, "ols")
	testing.expect_value(t, len(cfg.preamble), 2)
	testing.expect_value(t, len(cfg.lsp_args), 1)
	testing.expect_value(t, cfg.lsp_args[0], "--debug")
}

@(test)
test_config_partial_override_host_only :: proc(t: ^testing.T) {
	// Only "host" specified — preamble and lsp_binary should fall back to defaults.
	json := `{"host":"odin"}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, cfg.host, "odin")
	testing.expect_value(t, cfg.lsp_binary, "ols")
	testing.expect(t, len(cfg.preamble) == 2, "preamble should default to 2 lines")
}

@(test)
test_config_partial_override_lsp_binary :: proc(t: ^testing.T) {
	json := `{"lsp_binary":"my-ols"}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, cfg.lsp_binary, "my-ols")
	testing.expect_value(t, cfg.host, "odin") // default
}

@(test)
test_config_partial_override_preamble :: proc(t: ^testing.T) {
	// Explicit preamble replaces the built-in default.
	json := `{"preamble":["import \"core:io\""]}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, len(cfg.preamble), 1)
	testing.expect(t, strings.contains(cfg.preamble[0], "core:io"), "explicit preamble preserved")
}

@(test)
test_config_empty_json_object :: proc(t: ^testing.T) {
	// An empty JSON object uses all defaults.
	json := `{}`
	cfg, cerr := load_config_from_bytes(transmute([]byte)json)
	defer weasel_config_destroy(&cfg)

	testing.expect_value(t, cerr, Config_Error.None)
	testing.expect_value(t, cfg.host, "odin")
	testing.expect_value(t, cfg.lsp_binary, "ols")
}

@(test)
test_config_malformed_json :: proc(t: ^testing.T) {
	json := `{"host": oops}`
	_, cerr := load_config_from_bytes(transmute([]byte)json)
	testing.expect_value(t, cerr, Config_Error.Malformed_JSON)
}

// ---------------------------------------------------------------------------
// config_to_transpile_options
// ---------------------------------------------------------------------------

@(test)
test_config_to_transpile_options_odin :: proc(t: ^testing.T) {
	cfg := odin_default_weasel_config()
	defer weasel_config_destroy(&cfg)

	opts := config_to_transpile_options(cfg)
	testing.expect(t, opts.driver.emit_signature != nil, "emit_signature should be set")
	testing.expect(t, len(opts.preamble) == 2, "preamble should have 2 lines")
}
