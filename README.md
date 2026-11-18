# nextflow.nvim

Nextflow support for Neovim: language server, lint, run/resume, a task explorer
for debugging failed runs, nf-test, `nextflow_schema.json`-aware params, and
nf-core module pickers. Pure Lua, no picker dependency (`vim.ui.select`).

## Features

- **Filetypes**: `*.nf`, `nextflow.config` and project `*.config` → `nextflow`
  (highlighted with the groovy treesitter parser); `*.nf.test`, `nf-test.config` → `groovy`.
- **Language server** (`nextflow_ls`), auto-detected: `nextflow-lsp` on PATH →
  newest native bundle in `~/.nextflow/lsp` → newest cached jar (Java 17+) → Mason.
  Code lenses **Preview DAG** (Mermaid, opened with `:MarkdownPreview` if you have it)
  and **Preview config** work.
- **Lint**: `nextflow lint` → quickfix list (async).
- **Run / re-run** in a terminal split, args prompted (default `-resume`).
- **Resume picker**: pick any run from `.nextflow/history` and resume *that* session.
- **Task explorer**: tasks of a run, failed first; open `.command.err/.out/.log/.sh/.run`
  of any task. `:Nextflow failed` jumps straight to the first failed task's error.
- **nf-test**: test file / test under the cursor / all / update snapshots; jump
  between a script and its test.
- **Params**: hover docs for `params.<name>` from `nextflow_schema.json`; params
  files (`params*.yml|yaml|json`) are validated against the schema by yamlls/jsonls.
- **nf-core modules**: browse/install remote modules, info/update/remove/open installed ones.

## Requirements

- Neovim ≥ 0.11
- `nextflow` (lint needs ≥ 25.04); optional: `nf-test`, `nf-core`
- The Nextflow language server (the VS Code extension downloads it to `~/.nextflow/lsp`,
  or install `nextflow-language-server` with Mason, or set `lsp.cmd`)
- Treesitter `groovy` parser for highlighting (`:TSInstall groovy`)
- Optional: yamlls / jsonls for params-file validation, markdown-preview.nvim for DAGs

## Install (lazy.nvim)

```lua
{
  "<you>/nextflow.nvim",
  ft = { "nextflow", "groovy" },
  cmd = "Nextflow",
  opts = {},
},
{ "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "groovy" } } },
```

Filetype detection lives in `ftdetect/`, so it keeps working while the plugin is lazy-loaded;
opening a `params*.yml|json` file first also works (the plugin loads when yamlls/jsonls attaches).
Without lazy.nvim, call `require("nextflow").setup({})`.

## Commands

`:Nextflow <subcommand>` (with completion):

| Subcommand | What it does |
|---|---|
| `run` / `rerun` | `nextflow run .` in a terminal (args prompted) / repeat the last run |
| `resume` | pick a run from `.nextflow/history`, resume its session |
| `lint` | `nextflow lint` → quickfix |
| `format` | format with the language server |
| `dag` | run the code lens under the cursor (Preview DAG / config) |
| `log` | `nextflow log` in a terminal |
| `tasks [run]` | task explorer (default: newest run) |
| `failed` | open the first failed task's `.command.err` |
| `test [file\|nearest\|all\|update]` | nf-test |
| `alt` | script ↔ test file |
| `param` | schema docs for `params.<name>` under the cursor |
| `modules`, `modules!`, `modules local` | nf-core modules (`!` refreshes the cached list) |
| `health` | `:checkhealth nextflow` |

## Keymaps

Buffer-local in `nextflow` buffers and `*.nf.test` files (`<localleader>` is `\` in LazyVim):

| Key | Action | Key | Action |
|---|---|---|---|
| `r` | run | `t` | test file |
| `R` | re-run | `n` | test nearest |
| `s` | resume picker | `T` | test all |
| `l` | lint | `u` | update snapshots |
| `f` | format | `a` | alternate script/test |
| `d` | code lens (DAG/config) | `p` | param docs |
| `e` | last failed task's error | `m` | nf-core modules |
| `k` | task explorer | | |

Set `keymaps = false` to disable all, or any entry to `false` / another key.

## Configuration

Defaults:

```lua
require("nextflow").setup({
  lsp = {
    enable = true,
    cmd = nil, -- string[]; nil = auto-detect (PATH → ~/.nextflow/lsp native → jar → Mason)
    settings = {
      nextflow = {
        errorReportingMode = "warnings", -- off | errors | warnings | paranoid
        completion = { extended = true, maxItems = 100 },
        formatting = { harshilAlignment = false, maheshForm = false, sortDeclarations = false },
        files = { exclude = { ".git", ".lineage", ".nextflow", ".nf-test", ".pixi", ".venv", "work" } },
      },
    },
  },
  keymaps = {
    run = "<localleader>r", rerun = "<localleader>R", resume = "<localleader>s",
    lint = "<localleader>l", format = "<localleader>f", dag = "<localleader>d",
    failed = "<localleader>e", tasks = "<localleader>k",
    test_file = "<localleader>t", test_nearest = "<localleader>n",
    test_all = "<localleader>T", test_update = "<localleader>u",
    alt = "<localleader>a", param = "<localleader>p", modules = "<localleader>m",
  },
  terminal = { height = 0.35 },          -- fraction of the screen
  run = { default_args = "-resume" },
  nextflow = { cmd = "nextflow" },
  nf_test = { cmd = "nf-test" },
  nf_core = { cmd = "nf-core", cache_ttl = 86400 }, -- e.g. cmd = "~/venv/bin/nf-core"
  dag = { open_preview = true },          -- run :MarkdownPreview on DAG files
})
```

A `cmd` string is split on spaces; for a path containing spaces use a list,
e.g. `nextflow = { cmd = { "~/My Tools/nextflow" } }`.

## Health

`:checkhealth nextflow` reports Neovim, the resolved language server (and Java for the jar),
`nextflow` / `nf-test` / `nf-core` versions, the groovy parser and markdown-preview.

## Development

```sh
make test   # plenary.nvim busted; PLENARY_DIR=/path/to/plenary.nvim to override
```

## License

MIT
