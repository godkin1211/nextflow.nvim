# nextflow.nvim — Design

Date: 2026-11-18
Status: draft, awaiting approval

## 1. Intent

Turn the Nextflow setup currently living in the user's Neovim config
(`~/.config/nvim/lua/plugins/nextflow.lua`) into a standalone, shareable Neovim
plugin, and add the features that remove the most friction from day-to-day
Nextflow work in the editor — above all, debugging failed runs without leaving
Neovim.

Who it is for: the user first (macOS arm64, LazyVim, Nextflow 26.10, nf-test
0.9.5, nf-core 4.2.1 in `~/Projects/.venv`), then other Neovim users in the
bioinformatics community. Nothing comparable exists today (no dedicated Neovim
Nextflow plugin was found; nvim-lspconfig only ships a `nextflow_ls` entry whose
default `cmd` usually does not work).

## 2. Goals

### G0 — Core (port of what already works in the user's config)
- Filetype detection: `*.nf` → `nextflow`; `nextflow.config` → `nextflow`;
  any `*.config` with a `nextflow.config` in an ancestor dir → `nextflow`
  (lowest priority); `*.nf.test` and `nf-test.config` → `groovy`.
- Treesitter: register the `groovy` parser for the `nextflow` filetype
  (the plugin does not install parsers; README tells users to install `groovy`).
- Language server: resolve `cmd` in this order — `nextflow-lsp` on PATH →
  newest native bundle `~/.nextflow/lsp/*/nextflow-language-server-*/bin/nextflow-lsp`
  → newest cached jar `~/.nextflow/lsp/*/v*.jar` (needs Java 17+) → Mason's
  `nextflow-language-server` if installed → user-provided `cmd`. Configure via
  `vim.lsp.config("nextflow_ls", …)` + `vim.lsp.enable`. Default settings as in
  the current config (warnings mode, extended completion, telemetry off, excludes).
- Client-side commands invoked by server code lenses:
  `nextflow.previewDag` (Mermaid → temp markdown → `:MarkdownPreview` if
  available, else just open the file) and `nextflow.previewConfig`
  (scratch buffer). Code lens refresh on attach / BufEnter / InsertLeave / write.
- `nextflow lint -o json .` → quickfix list (async).
- Run / re-run in a terminal split at the project root, args prompted
  (default `-resume`).
- Formatting is the LSP's; `:Nextflow format` calls `vim.lsp.buf.format`.

### F1 — Task explorer (debug failed runs)
- `:Nextflow tasks [run_name]`: run defaults to the newest entry in
  `.nextflow/history`. Tasks come from
  `nextflow log <run> -f status,exit,name,hash,duration,workdir` (async).
- Shown with `vim.ui.select`, **failed tasks first**, then the rest in log
  order; each line: status marker, exit code, process name, duration, hash.
- Choosing a task opens a second `vim.ui.select` of what exists in its work dir:
  `.command.err`, `.command.out`, `.command.log`, `.command.sh`, `.command.run`,
  `.exitcode`, and "open work directory". Selection opens in a split.
- `:Nextflow failed`: shortcut — newest run, first failed task, opens
  `.command.err` directly (falls back to `.command.log` if err is empty).
  If none failed, say so.

### F2 — Resume picker
- `:Nextflow resume`: list `.nextflow/history` entries newest first
  (date, run name, status, duration, command).
- On selection, build `<original command with any existing -resume [id] removed> -resume <sessionId>`,
  offer it in `vim.ui.input` for editing, then run it in the terminal at the
  launch directory (the directory that holds `.nextflow/`).
- History format (verified): 7 tab-separated fields —
  date, duration, run name, status, revision, session id, command.

### F3 — nf-test integration
- `:Nextflow test file` — `nf-test test <current .nf.test>`.
- `:Nextflow test all` — `nf-test test` at the nf-test root
  (dir with `nf-test.config`, else project root).
- `:Nextflow test nearest` — run only the test enclosing the cursor
  (mechanism to be verified by the builder, see §7; if nf-test cannot target a
  single test, this falls back to the file and says so).
- `:Nextflow test update` — current file with `--update-snapshot`.
- `:Nextflow alt` — jump between a script and its test:
  `<dir>/main.nf` ↔ `<dir>/tests/main.nf.test` (nf-core layout), and
  `<dir>/foo.nf` ↔ `<dir>/tests/foo.nf.test`; if the target does not exist,
  offer to create it (empty buffer at that path, not written).

### F4 — Parameters from `nextflow_schema.json`
The language server already completes `params.<name>` with types from the
`params {}` block (verified), so the plugin does **not** add a completion source
for `.nf` files. Instead:
- Params files: for `params*.{yml,yaml,json}` (and any file passed via
  `-params-file` is out of scope) inside a project that has
  `nextflow_schema.json`, attach that schema to **yamlls** / **jsonls** by
  pushing it into the client's settings (`yaml.schemas` / `json.schemas`) and
  sending `workspace/didChangeConfiguration`. Never writes modelines into the
  user's files.
- `:Nextflow param` (and a keymap): for the `params.<name>` under the cursor,
  show the schema entry (description, help_text, type, default, enum, pattern,
  required) in a floating window. Works in `.nf` and `.config` buffers.

### F6 — nf-core modules
- `nf-core` command resolution: `opts.nf_core.cmd` → `nf-core` on PATH.
  The user's config sets `cmd = "~/Projects/.venv/bin/nf-core"`.
- `:Nextflow modules`: list remote modules via
  `nf-core modules list remote --json` (cached under
  `stdpath("cache")/nextflow.nvim/`, refreshed after 24 h or with
  `:Nextflow modules!`). `vim.ui.select` → action menu:
  **info** (`nf-core modules info <m>` output in a scratch buffer),
  **install** (`nf-core modules install <m> -d <pipeline root>` in the terminal,
  because it can prompt).
- `:Nextflow modules local`: modules installed in the current pipeline
  (`nf-core modules list local --json -d <root>`) → actions: info, update,
  remove (both in the terminal), open its `main.nf`.

### Cross-cutting
- One user command: `:Nextflow <subcommand>` with completion.
- Buffer-local keymaps (on by default, configurable or `false`) under
  `<localleader>` for `nextflow` buffers and `*.nf.test` buffers.
- `:checkhealth nextflow`: Neovim version, resolved LSP cmd (+ Java if jar),
  `nextflow`, `nf-test`, `nf-core`, groovy parser, markdown-preview presence.
- `require("nextflow").setup(opts)`; also works with lazy.nvim `opts = {}`.

## 3. Non-goals (this round)
Seqera Platform integration, terminal (ASCII) DAG rendering, statusline run
progress (ideas 5, 7, 8); snacks/fzf-lua/telescope pickers with previews;
nf-core module creation/lint/patch; Windows support; installing the language
server or treesitter parsers.

## 4. Anti-goals
- Blocking the editor: every CLI call (`nextflow log`, `lint`, `nf-core …`)
  runs through `vim.system` asynchronously.
- Hard dependencies on LazyVim, Snacks, Mason, or any picker plugin.
- Modifying user files implicitly (no modelines, no auto-writes).
- Silent failure: missing tools produce one clear notification naming the tool.

## 5. Constraints
- Neovim ≥ 0.11 (`vim.lsp.config/enable`, `vim.system`, `client:request`).
- macOS and Linux paths for the native server bundle.
- `nextflow lint` needs Nextflow ≥ 25.04; history/log work on older versions.
- Pure Lua; no build step.

## 6. Approaches considered (picker / UI)
| Option | What | Trade-off |
|---|---|---|
| A | snacks.picker with live preview, `vim.ui.select` fallback | best debugging UX, two code paths |
| **B (chosen by the user)** | `vim.ui.select` only | simplest, zero deps; no live preview, mitigated by the two-step task → file menu and `:Nextflow failed` |
| C | snacks + fzf-lua + telescope | most inclusive, ~2× code for v1 |

`vim.ui.select` is still rendered by whatever the user has installed
(in the user's LazyVim, Snacks overrides it), so B looks native everywhere.

Other calls made (the builder's / Claude's, not the user's):
- Run list from `.nextflow/history` (fast, stable format); task list from
  `nextflow log -f` (official, gives absolute work dirs even with `-w`).
- nf-core: shell out to the official CLI rather than re-implementing install
  (keeps `modules.json` correct); remote list cached.
- Terminal: built-in `:terminal` in a bottom split (no Snacks).

### Calls settled during review (Claude's)
- **Which `.nextflow/history`**: the launch directory is found by looking for
  `.nextflow/history` in the cwd first, then upward from the current buffer;
  if both exist and differ, the cwd wins. Runs are often launched from a parent
  dir (e.g. `nextflow run CLI/main.nf`), which is why the cwd comes first.
- **`nextflow log` failure** (cache deleted, run from another dir): one
  notification with the stderr; no partial menu.
- **Default buffer-local keymaps** (`<localleader>` = `\` in LazyVim):
  `r` run, `R` re-run, `s` resume picker, `l` lint, `f` format,
  `d` code lens (DAG/config), `e` last failed task's `.command.err`,
  `k` task explorer, `t` test file, `n` test nearest, `T` test all,
  `u` update snapshots, `a` alternate script/test, `p` param doc,
  `m` nf-core modules. Each is overridable or disable-able via `opts.keymaps`.
- **License**: MIT (matches the Neovim plugin ecosystem norm); the user can
  change it before publishing.

## 7. Left to the builder
- How nf-test targets a single test (hash suffix, line number, or not at all)
  for `test nearest`; verify against nf-test 0.9.5 and document.
- Whether yamlls/jsonls accept nf-core's draft 2020-12 schema (`$defs` +
  `allOf`) as-is; if not, flatten it into a temp draft-07 schema in the cache.
- Exact JSON shape of `nf-core modules list remote/local --json`.
- Module layout and tests: suggested `lua/nextflow/{init,config,filetype,lsp,
  terminal,run,lint,history,tasks,nftest,params,nfcore,health,util}.lua`,
  `plugin/nextflow.lua`, `doc/nextflow.txt`, `README.md`; pure-logic parts
  (history parsing, `-resume` rewriting, alt-file paths, log parsing, schema
  lookup) unit-tested with plenary busted; LSP/CLI pieces checked headlessly
  against `~/Projects/NextflowTutorialWorkshop` and the plugin's example pipeline.

## 8. Rollout in the user's config
- New repo at `~/Projects/nextflow.nvim` (git).
- `~/.config/nvim/lua/plugins/nextflow.lua` becomes a lazy.nvim spec:
  `{ dir = "~/Projects/nextflow.nvim", ft = { "nextflow", "groovy" }, cmd = "Nextflow", opts = { nf_core = { cmd = "~/Projects/.venv/bin/nf-core" } } }`
  plus the existing `nvim-treesitter` `ensure_installed = { "groovy" }`.
  Filetype detection must not depend on lazy-loading (lives in `plugin/`
  or `ftdetect/`, or the spec uses `lazy = false` — builder's call).
