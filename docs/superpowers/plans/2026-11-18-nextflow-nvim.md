# nextflow.nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone Neovim plugin giving Nextflow filetype/LSP support plus a task explorer, resume picker, nf-test integration, schema-aware params, and nf-core module management.

**Architecture:** Pure-Lua plugin. Small modules under `lua/nextflow/`, each owning one feature; pure parsing/rewriting functions are separated from UI/IO so they can be unit-tested with plenary busted. All CLI calls go through one async helper (`util.run_async`); all menus use `vim.ui.select`; long-running/interactive commands go to a built-in `:terminal` split.

**Tech Stack:** Lua, Neovim ≥ 0.11 APIs (`vim.lsp.config/enable`, `vim.system`, `vim.fs`), plenary.nvim (tests only), CLIs: `nextflow`, `nf-test`, `nf-core`.

**Spec:** `docs/superpowers/specs/2026-11-18-nextflow-nvim-design.md`

## Global Constraints
- Neovim ≥ 0.11; macOS and Linux.
- No runtime dependency on LazyVim, Snacks, Mason, or picker plugins. Menus: `vim.ui.select` / `vim.ui.input` only.
- Every CLI call is asynchronous (`vim.system`); UI updates via `vim.schedule`.
- Never modify user files implicitly (no modelines, no auto-writes).
- Missing tool → exactly one notification naming the tool; notifications titled `Nextflow`.
- Shell commands sent to `:terminal` quote every path with `vim.fn.shellescape`.
- LSP server name `nextflow_ls`; default settings (verbatim from the user's current config):
  `languageVersion="26.10"`, `errorReportingMode="warnings"`, `completion={extended=true,maxItems=100}`,
  `formatting={harshilAlignment=false,maheshForm=false,sortDeclarations=false}`,
  `files.exclude={".git",".lineage",".nextflow",".nf-test",".pixi",".venv","work"}`, `telemetry.enabled=false`.
- Verified CLI facts: `.nextflow/history` = 7 tab-separated fields `date, duration, run_name, status, revision, session_id, command`;
  `nextflow log <run> -f status,exit,name,hash,duration,workdir` is tab-separated, one task per line;
  `nf-test list --silent <file>` prints lines `  [<path>@<hash>] <test name>`; `nf-test test <path>@<hash>` runs one test;
  `nf-core modules list remote --json` prints a JSON array of module-name strings.
- License MIT.

## Review Focus
1. `-resume` placed before the script (`nextflow run -resume main.nf …`) must not swallow `main.nf` when rewriting the resume command → test in Task 5.
2. A run whose `nextflow log` output is empty, or whose work dir was cleaned, must give a "no tasks"/"work dir missing" message, not an empty menu or error → tests in Task 6.
3. Project never run (no `.nextflow/history`) → one clear message from resume/tasks/failed → test in Task 5.
4. Cursor outside any `test("…")` block, or duplicate test names, for `test nearest` → falls back to the whole file with a notification / picks by position → tests in Task 7.
5. Schemas without `$defs` (plain `properties`) and params missing from the schema → lookup still works / "not in schema" → tests in Task 8.

---

## File Structure

```
nextflow.nvim/
├── LICENSE, README.md, Makefile, .gitignore
├── ftdetect/nextflow.lua          -- calls require("nextflow.filetype").setup()
├── plugin/nextflow.lua            -- defines :Nextflow (lazy requires)
├── doc/nextflow.txt
├── lua/nextflow/
│   ├── init.lua      setup(opts)
│   ├── config.lua    defaults + merge
│   ├── util.lua      roots, notify, run_async, scratch/float helpers
│   ├── filetype.lua  filetype + treesitter alias
│   ├── lsp.lua       cmd resolution, vim.lsp.config/enable, code-lens client commands
│   ├── terminal.lua  bottom :terminal split
│   ├── run.lua       run / rerun
│   ├── lint.lua      nextflow lint → quickfix
│   ├── history.lua   .nextflow/history + resume picker
│   ├── tasks.lua     task explorer + failed shortcut
│   ├── nftest.lua    nf-test runs + alternate file
│   ├── params.lua    schema lookup/float + yamlls/jsonls schema attach
│   ├── nfcore.lua    nf-core module pickers
│   ├── commands.lua  :Nextflow subcommand table + completion
│   ├── keymaps.lua   buffer-local maps
│   └── health.lua    :checkhealth nextflow
└── tests/
    ├── minimal_init.lua
    ├── fixtures/ (history, nextflow_log.tsv, lint.json, schema_defs.json, schema_flat.json, sample.nf.test)
    └── *_spec.lua
```

---

### Task 1: Scaffold, test harness, config, util

**Files:**
- Create: `LICENSE`, `.gitignore` (`/tests/.tmp/`), `Makefile`, `tests/minimal_init.lua`, `lua/nextflow/config.lua`, `lua/nextflow/util.lua`
- Test: `tests/config_spec.lua`, `tests/util_spec.lua`

**Interfaces:**
- Produces:
  - `config.defaults` table; `config.setup(opts?: table)`; `config.get() -> table` (deep-merged).
    Defaults: `lsp={enable=true,cmd=nil,settings={nextflow=<Global Constraints>}}`,
    `keymaps={run="<localleader>r",rerun="<localleader>R",resume="<localleader>s",lint="<localleader>l",format="<localleader>f",dag="<localleader>d",failed="<localleader>e",tasks="<localleader>k",test_file="<localleader>t",test_nearest="<localleader>n",test_all="<localleader>T",test_update="<localleader>u",alt="<localleader>a",param="<localleader>p",modules="<localleader>m"}` (whole table may be `false`; any key may be `false`),
    `terminal={height=0.35}`, `run={default_args="-resume"}`, `nextflow={cmd="nextflow"}`, `nf_test={cmd="nf-test"}`, `nf_core={cmd="nf-core",cache_ttl=86400}`, `dag={open_preview=true}`.
  - `util.notify(msg: string, level?: integer)` — title `Nextflow`.
  - `util.root(buf?: integer) -> string` — `vim.fs.root(buf, {"nextflow.config","main.nf"})` or cwd.
  - `util.launch_dir(buf?: integer) -> string|nil` — cwd if it contains `.nextflow/history`, else nearest ancestor of the buffer's file that does.
  - `util.run_async(cmd: string[], opts: {cwd?: string}, on_done: fun(res: vim.SystemCompleted))` — callback runs on the main loop; if `cmd[1]` is not executable, notifies `"<cmd[1]> not found"` and does not call `on_done`.
  - `util.expand_cmd(cmd: string|string[]) -> string[]` — expands `~`, splits a string on spaces.
  - `util.scratch(lines: string[], ft?: string) -> integer` — opens a vsplit with a nofile buffer, returns buf.

- [ ] **Step 1:** `git init` in `~/Projects/nextflow.nvim`; add MIT `LICENSE`, `.gitignore`, `Makefile` target `test`:
  `nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua', sequential=true}"`.
  `minimal_init.lua` prepends the repo and `~/.local/share/nvim/lazy/plenary.nvim` (overridable by `$PLENARY_DIR`) to `runtimepath` and runs `runtime plugin/plenary.vim`.
- [ ] **Step 2: Write failing tests**
  - `config_spec`: after `setup({keymaps={lint=false}, nf_core={cmd="~/x/nf-core"}})`, `get().keymaps.lint == false`, `get().keymaps.run == "<localleader>r"`, `get().nf_core.cache_ttl == 86400`; after `setup({keymaps=false})`, `get().keymaps == false`.
  - `util_spec`: `expand_cmd("~/a/nf-core modules")` → `{vim.fn.expand("~/a/nf-core"), "modules"}`; `launch_dir` returns the temp dir when a temp dir with `.nextflow/history` is the cwd, and `nil` for an empty temp dir; `run_async({"definitely-not-a-tool"}, {}, cb)` does not call `cb`.
- [ ] **Step 3:** Run `make test` → FAIL (modules missing).
- [ ] **Step 4:** Implement `config.lua` (`vim.tbl_deep_extend("force", …)`; a `false` value for `keymaps` replaces the table) and `util.lua`.
- [ ] **Step 5:** `make test` → PASS.
- [ ] **Step 6:** Commit `chore: scaffold plugin, test harness, config and util`.

### Task 2: Filetype detection

**Files:** Create `lua/nextflow/filetype.lua`, `ftdetect/nextflow.lua`; Test `tests/filetype_spec.lua`

**Interfaces:**
- Produces: `filetype.setup()` (idempotent) — rules from spec G0, `vim.treesitter.language.register("groovy","nextflow")`.

- [ ] **Step 1: Failing tests** (temp project dir with `nextflow.config` and `conf/`): `vim.filetype.match({filename=<dir>/main.nf})=="nextflow"`, `nextflow.config`→`nextflow`, `<dir>/conf/base.config`→`nextflow`, `/tmp/other/foo.config` (no nextflow.config above) ≠ `nextflow`, `x/tests/main.nf.test`→`groovy`, `nf-test.config`→`groovy`, `vim.treesitter.language.get_lang("nextflow")=="groovy"`.
- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement (port the `vim.filetype.add` block from `~/.config/nvim/lua/plugins/nextflow.lua`); `ftdetect/nextflow.lua` is one line.
- [ ] **Step 4:** `make test` → PASS. **Step 5:** Commit `feat: filetype detection`.

### Task 3: Language server

**Files:** Create `lua/nextflow/lsp.lua`; Test `tests/lsp_spec.lua`

**Interfaces:**
- Consumes: `config.get()`, `util.notify`, `util.scratch`.
- Produces:
  - `lsp.resolve_cmd(opts?: {cache_dir?: string}) -> string[]|nil` — order from spec G0 (`cache_dir` default `~/.nextflow/lsp`; newest by semver in the path; jar only if `java` executable; then Mason bin `stdpath("data")/mason/bin/nextflow-language-server` if executable).
  - `lsp.setup()` — if `config.get().lsp.enable`: `vim.lsp.config("nextflow_ls", {cmd=<config cmd or resolve_cmd()>, filetypes={"nextflow"}, root_markers={"nextflow.config","main.nf",".git"}, settings=<config>})` then `vim.lsp.enable("nextflow_ls")`; if no cmd resolves, notify once `"Nextflow language server not found (see :checkhealth nextflow)"`. Always registers `vim.lsp.commands["nextflow.previewDag"]` and `["nextflow.previewConfig"]` and the code-lens refresh autocmd.
  - `lsp.dag_markdown(name: string|nil, mermaid: string) -> string[]` — lines `# DAG: <name or "<entry>">`, blank, ```` ```mermaid ````, mermaid lines, ```` ``` ````.

- [ ] **Step 1: Failing tests**: with a temp `cache_dir` containing `v26.04/nextflow-language-server-26.04.2-macos-arm64/bin/nextflow-lsp` and `v26.10/nextflow-language-server-26.10.2-macos-arm64/bin/nextflow-lsp` (both `chmod +x`) and `PATH` without `nextflow-lsp`, `resolve_cmd({cache_dir=d})[1]` ends with `26.10.2-macos-arm64/bin/nextflow-lsp`; with only `v26.04/v26.04.1.jar` and `v26.04/v26.04.2.jar` → `{"java","-jar",<…v26.04.2.jar>}`; `dag_markdown(nil, "flowchart TB\n  a")` → `{"# DAG: <entry>","","```mermaid","flowchart TB","  a","```"}`.
- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement, porting `lsp_commands`/`exec_server` from the user's current config, keeping the `vim.NIL` normalisation for the DAG name and the filename sanitising; previewConfig passes `{uri, name, {}, qualifiedName or vim.NIL}`. DAG: write `dag_markdown` to `vim.fn.tempname().."_<name>_dag.md"`, `vsplit` it, run `:MarkdownPreview` only if `config.get().dag.open_preview` and the command exists.
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5: Headless check** against the copy of the plugin's example pipeline used earlier (or `~/Projects/NextflowTutorialWorkshop`): a script that loads the repo on rtp, calls `require("nextflow").setup()` — implement a minimal `init.lua` here if Task 4 has not created it — opens `main.nf`, waits for `nextflow_ls`, and prints one code lens title. Expected: `Preview DAG`.
- [ ] **Step 6:** Commit `feat: language server setup and code-lens commands`.

### Task 4: Terminal, run, lint, commands, keymaps, setup

**Files:** Create `lua/nextflow/{terminal,run,lint,commands,keymaps,init}.lua`, `plugin/nextflow.lua`; Test `tests/lint_spec.lua`, `tests/commands_spec.lua`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `terminal.open(cmd: string, cwd: string)` — `botright` split sized `terminal.height` of `vim.o.lines`, `jobstart(cmd,{term=true,cwd=cwd})`, buffer-local `q` closes it after the job ends.
  - `run.run(buf)`, `run.rerun(buf)` — port of the current `M.run/M.rerun` (prompt default `config.run.default_args`, remembered for the session).
  - `lint.parse(json_text: string, root: string) -> (items: table[], summary: table)` — quickfix items `{filename=<root>/<filename>, lnum, col, text, type="E"|"W"}`; tolerates text before the JSON object.
  - `lint.lint(buf)` — `run_async({nextflow,"lint","-o","json","."})`, `setqflist`, summary notification, `copen` if any.
  - `commands.subcommands: table<string, {run: fun(args: string[], bang: boolean), complete?: fun(): string[]}>`; `commands.dispatch(fargs: string[], bang: boolean)`; `commands.complete(arglead, cmdline) -> string[]`. Task 4 registers `run`, `rerun`, `lint`, `format`, `dag` (`vim.lsp.codelens.run()`), `log` (`terminal.open("nextflow log", root)`), `health` (`checkhealth nextflow`). Later tasks add their own entries **in their own module** by calling `commands.register(name, spec)`; `commands.lua` requires those modules lazily inside `dispatch` (a fixed list `{"history","tasks","nftest","params","nfcore"}` whose `register_commands()` is called once). Every "registers subcommand …" line in Tasks 5–9 means: that module exports `register_commands()` which calls `commands.register(...)`.
  - `keymaps.setup()` — FileType autocmd for `nextflow` and `*.nf.test` groovy buffers: sets `commentstring="// %s"`, maps each non-false `config.keymaps` entry to the matching subcommand (key name = subcommand, `test_file`→`test file`, `test_nearest`→`test nearest`, `test_all`→`test all`, `test_update`→`test update`), desc `"Nextflow: <subcommand>"`; adds which-key group if which-key is loaded (pcall).
  - `init.setup(opts)` — `config.setup(opts)`, `filetype.setup()`, `lsp.setup()`, `keymaps.setup()`; re-applies keymaps to already-open Nextflow buffers.
  - `plugin/nextflow.lua` — `:Nextflow` user command (`nargs="*"`, `bang=true`, `complete=commands.complete`), guarded by `vim.g.loaded_nextflow`.

- [ ] **Step 1: Failing tests**: `lint.parse` on `tests/fixtures/lint.json` (copy of the real output seen earlier: two errors, `broken.nf:3:1 "Unexpected input: '}'"` and `main.nf:87:14 …`), with root `/r` → 2 items, first `{filename="/r/broken.nf", lnum=3, col=1, type="E"}`, `summary.errors==2`; same JSON prefixed by a log line still parses. `commands.complete("", "Nextflow ")` contains `"lint"` and `"run"`; `commands.complete("t", "Nextflow t")` contains `"tasks"` and `"test"` once Tasks 6–7 exist (assert only `lint`/`run` now).
- [ ] **Step 2:** `make test` → FAIL. **Step 3:** Implement. **Step 4:** `make test` → PASS.
- [ ] **Step 5: Headless check**: in the example pipeline, `:Nextflow lint` fills the quickfix list with `main.nf:87`.
- [ ] **Step 6:** Commit `feat: run, lint, :Nextflow command and keymaps`.

### Task 5: History and resume picker (F2)

**Files:** Create `lua/nextflow/history.lua`, `tests/fixtures/history`; Test `tests/history_spec.lua`

**Interfaces:**
- Consumes: `util.launch_dir`, `util.notify`, `terminal.open`, `commands.register`.
- Produces:
  - `history.parse(text: string) -> Entry[]` newest first; `Entry = {date, duration, run_name, status, revision, session_id, command}` (fields trimmed; malformed lines skipped).
  - `history.read(launch_dir: string|nil) -> Entry[]|nil, err: string|nil` — err `"No Nextflow runs found (no .nextflow/history)"` when absent.
  - `history.resume_command(entry: Entry) -> string`.
  - `history.label(entry: Entry) -> string` — `"<date>  <run_name>  <status>  <duration>  <command>"`.
  - `history.pick_resume(buf)`; registers subcommand `resume`.
  - Used by Task 6: `history.read`.

- [ ] **Step 1: Failing tests** (fixture = the three real lines seen in `~/Projects/NextflowTutorialWorkshop/.nextflow/history` plus one malformed line):
  - `parse` → 3 entries, `[1].run_name=="adoring_poitras"`, `[1].session_id=="e5e1cd4c-5353-4caf-8bdf-e7ad3e6bc512"`, `[1].command=="nextflow run nf-core/rarevariantburden -r dev -profile test,docker --outdir results"`.
  - `resume_command({command="nextflow run main.nf --x 1", session_id="S"})` == `"nextflow run main.nf --x 1 -resume S"`.
  - `… --x 1 -resume"` → `"… --x 1 -resume S"`; `… -resume 66820406-49b4-4872-814f-044a096a3f72 --x 1` → `"… --x 1 -resume S"`; `… -resume happy_mccarthy` → `"… -resume S"`.
  - **Review Focus 1:** `"nextflow run -resume main.nf --x 1"` → `"nextflow run main.nf --x 1 -resume S"`.
  - **Review Focus 3:** `read("/nonexistent")` → `nil, "No Nextflow runs found (no .nextflow/history)"`; `read(nil)` same.
- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement. `resume_command` tokenises on whitespace, drops `-resume` and the following token only if it matches a UUID (`^%x+%-%x+%-%x+%-%x+%-%x+$`) or a run name (`^%l+_%l+$`), then appends `-resume <session_id>`. `pick_resume`: `vim.ui.select(entries,{prompt="Resume which run?",format_item=label})` → `vim.ui.input({prompt="Command: ",default=resume_command(e)})` → `terminal.open(cmd, launch_dir)`.
- [ ] **Step 4:** `make test` → PASS. **Step 5:** Commit `feat: resume picker from .nextflow/history`.

### Task 6: Task explorer and failed shortcut (F1)

**Files:** Create `lua/nextflow/tasks.lua`, `tests/fixtures/nextflow_log.tsv`; Test `tests/tasks_spec.lua`

**Interfaces:**
- Consumes: `history.read`, `util.run_async`, `util.launch_dir`, `config.get().nextflow.cmd`, `commands.register`.
- Produces:
  - `tasks.FIELDS = "status,exit,name,hash,duration,workdir"`.
  - `tasks.parse(stdout: string) -> Task[]` — `Task={status,exit,name,hash,duration,workdir}`; blank lines skipped.
  - `tasks.sort(list: Task[]) -> Task[]` — stable: `FAILED` first, then `ABORTED`, then the rest in original order.
  - `tasks.label(t: Task) -> string` — `"<✗|!|✓|↺> [<exit>] <name>  <duration>  <hash>"` (✗ FAILED, ! ABORTED, ✓ COMPLETED, ↺ CACHED).
  - `tasks.files(workdir: string) -> {label: string, path: string}[]` — existing ones of `.command.err, .command.out, .command.log, .command.sh, .command.run, .exitcode` in that order, then `{label="open work directory", path=workdir}`; `{}` if the dir is missing.
  - `tasks.pick(buf, run_name?: string)`, `tasks.open_failed(buf)`; registers `tasks` (completion = run names from history) and `failed`.

- [ ] **Step 1: Failing tests** (fixture: 4 tab-separated lines — COMPLETED, FAILED (exit 1), CACHED, ABORTED (exit `-`), workdirs under a temp dir created in the test):
  - `parse` → 4 tasks, second `.status=="FAILED"`, `.exit=="1"`.
  - `sort` order: FAILED, ABORTED, COMPLETED, CACHED.
  - `files(<dir with .command.err and .command.sh>)` → labels `{".command.err",".command.sh","open work directory"}`.
  - **Review Focus 2:** `parse("")` → `{}`; `files("/no/such/dir")` → `{}`.
- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement. `pick`: resolve run (arg or newest history entry) → `run_async({nextflow,"log",run,"-f",FIELDS}, {cwd=launch_dir})` → non-zero exit: notify stderr; empty list: notify `"No tasks recorded for <run>"`; else `vim.ui.select(sort(list))` → `files(t.workdir)` empty → notify `"Work directory missing: <dir>"`, else select → `vsplit <path>` (directory path opens with `:edit`). `open_failed`: newest run, first FAILED task; open `.command.err`, or `.command.log` if err is empty; none failed → notify `"No failed tasks in <run>"`.
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5: Headless check** in `~/Projects/NextflowTutorialWorkshop` (cwd): `tasks.parse` of the real `nextflow log adoring_poitras -f …` output yields > 0 tasks; `:Nextflow failed` notifies `No failed tasks in adoring_poitras`.
- [ ] **Step 6:** Commit `feat: task explorer and failed-task shortcut`.

### Task 7: nf-test integration (F3)

**Files:** Create `lua/nextflow/nftest.lua`, `tests/fixtures/sample.nf.test`; Test `tests/nftest_spec.lua`

**Interfaces:**
- Consumes: `terminal.open`, `util.run_async`, `util.root`, `config.get().nf_test.cmd`, `commands.register`.
- Produces:
  - `nftest.alt_path(path: string) -> string` — rules from spec F3; a `.nf.test` outside a `tests/` dir maps to the same dir's `.nf`.
  - `nftest.enclosing_test(lines: string[], row: integer) -> (name: string|nil, ordinal: integer|nil)` — nearest `test("<name>")`/`test('<name>')` at or above `row` whose block contains `row` (brace counting); ordinal = 1-based index among all tests in the file.
  - `nftest.parse_list(stdout: string) -> {path: string, hash: string, name: string}[]` from lines `[<path>@<hash>] <name>`.
  - `nftest.root(buf) -> string` — dir with `nf-test.config`, else `util.root`.
  - `nftest.run(buf, mode: "file"|"nearest"|"all"|"update")`, `nftest.alt(buf)`; registers `test` (completion `file nearest all update`) and `alt`.

- [ ] **Step 1: Failing tests**:
  - `alt_path("/p/modules/x/main.nf")=="/p/modules/x/tests/main.nf.test"`; reverse; `"/p/foo.nf"↔"/p/tests/foo.nf.test"`; `"/p/a.nf.test"=="/p/a.nf"`.
  - `sample.nf.test` = the two-test file used during design (tests `first`, `second`): row inside `second` → `"second", 2`.
  - **Review Focus 4:** row on the `name "Test ECHO_X"` line → `nil`; `parse_list` of two lines with the same name `dup` returns both, in order (caller picks by ordinal).
  - `parse_list("  [tests/main.nf.test@93d49ea1] second\n")` → `{{path="tests/main.nf.test",hash="93d49ea1",name="second"}}`.
- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement. `file`/`update`: `nf-test test <file>` (+ `--update-snapshot`); on a `.nf` buffer use its `alt_path` if it exists, else notify `"No test file for <name>"`. `all`: `nf-test test` at `nftest.root`. `nearest`: `enclosing_test` → nil → notify `"Cursor is not inside a test(); running the whole file"` and run file; else `run_async({nf-test,"list","--silent",file})` → pick the entry whose name matches and, if several, the one at `ordinal` → `nf-test test <path>@<hash>`. `alt`: `edit` target (unwritten buffer if missing, notify `"New file: <path>"`).
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5: Headless check** with the two-test project from design (`nf-test init` dir): `nearest` on `second` launches a terminal whose command ends with `@93d49ea1` (assert the string passed to `terminal.open` by stubbing it).
- [ ] **Step 6:** Commit `feat: nf-test runs and alternate-file jump`.

### Task 8: Parameters from nextflow_schema.json (F4)

**Files:** Modify `lua/nextflow/init.lua` (call `params.setup()`); Create `lua/nextflow/params.lua`, `tests/fixtures/schema_defs.json` (nf-core style: `$defs` + `allOf`, params `input` (required, `format: file-path`), `outdir`, `genome` with `enum`), `tests/fixtures/schema_flat.json` (top-level `properties` only); Test `tests/params_spec.lua`

**Interfaces:**
- Consumes: `util`, `commands.register`.
- Produces:
  - `params.find_schema(buf) -> string|nil` — `<root>/nextflow_schema.json` via `vim.fs.root(buf, "nextflow_schema.json")`.
  - `params.load(path) -> table|nil` (cached by path + mtime).
  - `params.lookup(schema: table, name: string) -> table|nil` — searches top-level `properties`, every `$defs.*.properties`, and every `definitions.*.properties`.
  - `params.flatten(schema: table) -> table` — `{"$schema"="http://json-schema.org/draft-07/schema#", type="object", properties=<merged>, required=<union of group required>}`.
  - `params.format_entry(name, entry) -> string[]` markdown: `` `params.<name>` `` (type), description, help_text, default, enum, pattern, "required" flag.
  - `params.word_at(line: string, col: integer) -> string|nil` — name of `params.<name>` under 0-based `col`.
  - `params.show(buf)` — float via `vim.lsp.util.open_floating_preview(lines,"markdown")`; not in schema → notify `"params.<name> is not in nextflow_schema.json"`; no schema → notify `"No nextflow_schema.json found"`.
  - `params.attach(client, buf)` — LspAttach handler for `yamlls`/`jsonls` when the file name matches `^params.*%.ya?ml$` or `^params.*%.json$` and a schema exists: write `flatten(schema)` to `stdpath("cache")/nextflow.nvim/schemas/<sha256(schema path)>.json`; yamlls: `settings.yaml.schemas[<cache file uri>] = <buffer path>`; jsonls: append `{fileMatch={<buffer path>}, url=<cache file uri>}` to `settings.json.schemas`; then `client:notify("workspace/didChangeConfiguration",{settings=client.settings})`. Registers the autocmd in `params.setup()` (called from `init.setup`) and subcommand `param`.

- [ ] **Step 1: Failing tests**: `lookup(defs,"genome").enum` contains `"GRCh38"`; `lookup(flat,"input")` non-nil; **Review Focus 5:** `lookup(defs,"nope")==nil`, `lookup(flat,"nope")==nil`; `flatten(defs).properties.outdir` non-nil and `"input"` ∈ `flatten(defs).required`; `word_at("  x = params.kmer_size + 1", 15)=="kmer_size"`, `word_at("x = 1", 2)==nil`; `format_entry("genome", …)` contains a line with `GRCh38`.
- [ ] **Step 2:** `make test` → FAIL. **Step 3:** Implement. **Step 4:** `make test` → PASS.
- [ ] **Step 5: Headless check** in a temp copy of an nf-core-style project (`nextflow_schema.json` from `tests/fixtures/schema_defs.json`) with the user's full config: open `params.yml` containing `genome: foo`, wait for yamlls, expect a diagnostic mentioning the enum (proves the attach path end-to-end). If yamlls does not report it, record why in the commit message and keep the hover feature.
- [ ] **Step 6:** Commit `feat: schema-aware params (hover doc, params-file validation)`.

### Task 9: nf-core modules (F6)

**Files:** Create `lua/nextflow/nfcore.lua`; Test `tests/nfcore_spec.lua`

**Interfaces:**
- Consumes: `util.expand_cmd`, `util.run_async`, `util.root`, `terminal.open`, `config.get().nf_core`, `commands.register`.
- Produces:
  - `nfcore.cache_path() -> string` — `stdpath("cache")/nextflow.nvim/remote_modules.json`.
  - `nfcore.cache_fresh(path: string, ttl: integer, now?: integer) -> boolean`.
  - `nfcore.parse_remote(json: string) -> string[]` (sorted).
  - `nfcore.parse_local(json: string) -> string[]` — shape verified in Step 1.
  - `nfcore.pick_remote(buf, force: boolean)` — actions `info` (terminal: `<nf-core> modules info <m>`), `install` (terminal: `<nf-core> modules install <m> -d <root>`).
  - `nfcore.pick_local(buf)` — actions `info`, `update` (`modules update <m> -d <root>`), `remove` (`modules remove <m> -d <root>`), `open main.nf` (`<root>/modules/nf-core/<m>/main.nf`).
  - Registers `modules` (`:Nextflow modules`, `:Nextflow modules!` forces refresh, `:Nextflow modules local`).

- [ ] **Step 1: Verify** the local-list JSON shape: in a temp dir run `~/Projects/.venv/bin/nf-core pipelines create --name demo --description d --author a` (or any nf-core pipeline checkout), then `nf-core modules list local --json -d <dir>`; save the output as `tests/fixtures/modules_local.json`.
- [ ] **Step 2: Failing tests**: `parse_remote('["b","a/x"]')=={"a/x","b"}`; `parse_local(<fixture>)` contains `"fastqc"` (or whatever the fixture holds); `cache_fresh` true for mtime `now-10` with ttl 86400, false for `now-90000`, false for a missing file.
- [ ] **Step 3:** `make test` → FAIL. **Step 4:** Implement (remote list: fresh cache → read; else `run_async({...nf_core, "modules","list","remote","--json"})`, notify `"Fetching nf-core module list…"`, write cache). **Step 5:** `make test` → PASS.
- [ ] **Step 6: Headless check** with `nf_core.cmd="~/Projects/.venv/bin/nf-core"`: `pick_remote` with `vim.ui.select` stubbed receives > 2000 items.
- [ ] **Step 7:** Commit `feat: nf-core module pickers`.

### Task 10: Health, docs, rollout

**Files:** Create `lua/nextflow/health.lua`, `README.md`, `doc/nextflow.txt`; Modify `~/.config/nvim/lua/plugins/nextflow.lua` (replace contents)

**Interfaces:**
- Consumes: everything.
- Produces: `health.check()` — sections: Neovim ≥ 0.11 (error if not); LSP cmd (`lsp.resolve_cmd` or config; warn + install hint if nil; report Java ≥ 17 when jar); `nextflow` (version via `nextflow -version` sync is acceptable in health), `nf-test`, `nf-core` (configured cmd) — warn if missing; groovy treesitter parser (`vim.treesitter.language.add("groovy")`); `:MarkdownPreview` presence (info only).

- [ ] **Step 1:** Implement `health.lua`; run `nvim --headless "+checkhealth nextflow" "+w! /tmp/h.txt" +qa` → file shows OK for Neovim, LSP cmd, nextflow, nf-test, and nf-core once configured.
- [ ] **Step 2:** README: features (with keymap table from spec), requirements, install with lazy.nvim (`ft={"nextflow","groovy"}, cmd="Nextflow", opts={}`) and note that `ftdetect/` keeps detection working while lazy-loaded, groovy parser instruction, configuration defaults block, `:Nextflow` subcommands, health. `doc/nextflow.txt` mirrors it; run `:helptags doc` → no errors.
- [ ] **Step 3:** Replace the user's `~/.config/nvim/lua/plugins/nextflow.lua` with:
  `{ dir = "~/Projects/nextflow.nvim", ft = { "nextflow", "groovy" }, cmd = "Nextflow", opts = { nf_core = { cmd = "~/Projects/.venv/bin/nf-core" } } }` and `{ "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "groovy" } } }`.
- [ ] **Step 4: End-to-end headless check** with the user's full config in the example pipeline: filetype `nextflow`, `nextflow_ls` attached with the native cmd, code lens `Preview DAG`, `\l` fills quickfix, `:Nextflow` completion lists every subcommand (`alt dag failed format health lint log modules param rerun resume run tasks test`).
- [ ] **Step 5:** `make test` → all PASS. Commit `docs: health check, README, help` (plugin repo only; the user's nvim config is not a git repo).
