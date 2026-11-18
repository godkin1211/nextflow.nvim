; extends

; Nextflow process bodies: a `script:` / `shell:` label followed by a string.
; The language follows the shebang (python, Rscript, perl); bash otherwise.
; `${...}` interpolations stay groovy; the pieces around them are parsed as one document.

(closure
  (label (identifier) @_label)
  .
  (string (string_content) @injection.content) @_body
  (#any-of? @_label "script" "shell")
  (#lua-match? @_body "^[\"']+%s*#![%w/._ -]*python")
  (#set! injection.language "python")
  (#set! injection.combined))

(closure
  (label (identifier) @_label)
  .
  (string (string_content) @injection.content) @_body
  (#any-of? @_label "script" "shell")
  (#lua-match? @_body "^[\"']+%s*#![%w/._ -]*Rscript")
  (#set! injection.language "r")
  (#set! injection.combined))

(closure
  (label (identifier) @_label)
  .
  (string (string_content) @injection.content) @_body
  (#any-of? @_label "script" "shell")
  (#lua-match? @_body "^[\"']+%s*#![%w/._ -]*perl")
  (#set! injection.language "perl")
  (#set! injection.combined))

(closure
  (label (identifier) @_label)
  .
  (string (string_content) @injection.content) @_body
  (#any-of? @_label "script" "shell")
  (#not-lua-match? @_body "^[\"']+%s*#![%w/._ -]*python")
  (#not-lua-match? @_body "^[\"']+%s*#![%w/._ -]*Rscript")
  (#not-lua-match? @_body "^[\"']+%s*#![%w/._ -]*perl")
  (#set! injection.language "bash")
  (#set! injection.combined))
