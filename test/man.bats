#!/usr/bin/env bats
# the man module with stubbed man, tldr and nvim (calls logged) and a fixture tldr pages directory

load test_helper

MAN="$(readlink -f "$BATS_TEST_DIRNAME/../modules/man")"

setup() {
  setup_fzx
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls" PAGES="$BATS_TEST_TMPDIR/tldr"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$PAGES/pages.en/common" "$PAGES/pages.en/linux" "$PAGES/pages.en/osx"
  cat > "$BATS_TEST_TMPDIR/bin/man" << 'STUB'
#!/usr/bin/env bash
printf 'man %s\n' "$*" >> "$CALLS"
if [[ "$1" == -k ]]; then
  printf '%s\n' 'ls (1)               - list directory contents' \
    'gzip, gunzip (1)     - compress or expand files' \
    'openssl (1ssl)       - OpenSSL command line program' \
    'mount (8)            - mount a filesystem' \
    'printf (3)           - formatted output conversion' \
    'printf (1)           - format and print data' \
    'passwd (5)           - the password file' \
    'ls (1)               - list directory contents'
  exit 0
fi
# the zsh mode's pages: fixtures in $ZSHMAN (zsh_pages)
[[ "$1" == -- ]] && shift
if [[ "$1" == -w ]]; then
  [[ -n "${ZSHMAN:-}" && -f "$ZSHMAN/$2" ]] && { printf '%s\n' "$ZSHMAN/$2"; exit 0; }
  exit 16
fi
[[ -n "${ZSHMAN:-}" && -f "$ZSHMAN/${1:-}" ]] && { cat "$ZSHMAN/$1"; exit 0; }
printf 'PAGE %s\n' "$*"
STUB
  cat > "$BATS_TEST_TMPDIR/bin/tldr" << 'STUB'
#!/usr/bin/env bash
printf 'tldr %s\n' "$*" >> "$CALLS"
case "$1" in
  --show-paths) printf 'Cache dir:        /x\nPages dir:        %s/\n' "$PAGES" ;;
  --list) printf 'tar\nzip\n' ;;
  *) printf 'TLDR %s\n' "${@: -1}" ;;
esac
STUB
  printf '#!/usr/bin/env bash\nprintf "nvim %%s\\n" "$*" >> "$CALLS"\n' > "$BATS_TEST_TMPDIR/bin/nvim"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  printf '# tar\n\n> Archiving utility.\n> More.\n' > "$PAGES/pages.en/common/tar.md"
  printf '# tar\n\n> The linux tar.\n' > "$PAGES/pages.en/linux/tar.md"
  printf '# apt\n\n> Debian package manager.\n' > "$PAGES/pages.en/linux/apt.md"
  printf '# brew\n\n> macOS packages.\n' > "$PAGES/pages.en/osx/brew.md"
}

src() { FZX_MODE="$1" "$MAN/source.sh"; }

@test "commands: sections 1 and 8 (1ssl too), names of a shared line apart, each page once, short names first" {
  run src commands
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "ls(1) gzip(1) mount(8) gunzip(1) printf(1) openssl(1ssl) " ]
  [[ "${lines[0]}" == "ls(1)"$'\t'"ls "*"1 "*"list directory contents" ]]
}

@test "all: every section; FZX_MAN_SECTIONS picks the commands sections" {
  run src all
  [[ "$output" == *"printf(3)"* && "$output" == *"passwd(5)"* ]]
  [ "${#lines[@]}" -eq 8 ]
  mkdir -p "$FZX_CONFIG_DIR/modules/man"
  echo 'FZX_MAN_SECTIONS=(5)' > "$FZX_CONFIG_DIR/modules/man/config.sh"
  run src commands
  [ "$output" = "passwd(5)"$'\t'"$(printf '%-28s %-8s %s' passwd 5 'the password file')" ]
}

@test "tldr: descriptions from the pages, common before the platform, other platforms left out" {
  run src tldr
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "apt tar " ]
  [[ "$output" == *"tar"*common*"Archiving utility." ]]
  [[ "$output" != *"linux tar"* ]]
}

@test "tldr: without a pages directory, tealdeer's list" {
  FZX_MAN_TLDR_PAGES="$BATS_TEST_TMPDIR/none" run src tldr
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "tar zip " ]
}

@test "preview: the page by section at the preview's width, a tldr page, nothing for no id" {
  FZF_PREVIEW_COLUMNS=50 run "$MAN/preview.sh" 'printf(3)'
  [[ "$output" == *"PAGE 3 -- printf"* ]]
  FZX_MODE=tldr run "$MAN/preview.sh" tar
  [ "$output" = "TLDR tar" ]
  run "$MAN/preview.sh" ''
  [ -z "$output" ]
}

@test "actions: open each page in turn, nvim the first with :Man; tldr pages as their file" {
  "$MAN/actions.sh" open 'ls(1)' 'mount(8)'
  grep -qx 'man 1 -- ls' "$CALLS"
  grep -qx 'man 8 -- mount' "$CALLS"
  "$MAN/actions.sh" nvim 'printf(3)' 'ls(1)'
  grep -qx 'nvim -c Man 3 printf -c only' "$CALLS"
  FZX_MODE=tldr "$MAN/actions.sh" nvim apt
  grep -qx "nvim -R -- $PAGES/pages.en/linux/apt.md" "$CALLS"
  run "$MAN/actions.sh" bogus x
  [ "$status" -eq 2 ]
}

@test "under fzx: enter opens, alt-n nvim, names lead the ranking" {
  stub_fzf
  run "$FZX" -m man
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind enter)" == *'_cb action open'* ]]
  [[ "$(fzf_bind alt-n)" == *'_cb action nvim'* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --tiebreak=begin,index "* ]]
}

# zsh_pages: fixture zsh manual pages as man prints them (7-column entries, text at 14) in $ZSHMAN
zsh_pages() {
  export ZSHMAN="$BATS_TEST_TMPDIR/zshman"
  mkdir -p "$ZSHMAN"
  cat > "$ZSHMAN/zshoptions" << 'PAGE'
NAME
       zshoptions - zsh options

SPECIFYING OPTIONS
       HISTSIZE is not an entry here: this section is not read.
              Indented text.

DESCRIPTION OF OPTIONS
   Changing Directories
       AUTO_CD (-J)
              If a command is issued that can't be executed, perform the cd command.  More text.

       CD_SILENT
              Never print the working directory after a cd.

   Zle
       EMACS  If ZLE is loaded, turning on this option has the effect of `bindkey -e'.  More.

       lowercase_name
              Not an option name.

OPTION ALIASES
       BRACE_EXPAND
              NO_IGNORE_BRACES (ksh and bash compatibility)
PAGE
  cat > "$ZSHMAN/zshbuiltins" << 'PAGE'
SHELL BUILTIN COMMANDS
       . file [ arg ... ]
              Read commands from file and execute them.

       bindkey
              See the section `Zle Builtins' in zshzle(1).

       sched  See the section `The zsh/sched Module' in zshmodules(1).

       set [ {+|-}options | {+|-}o [ option_name ] ] ... [ {+|-}A [ name ] ]
           [ arg ... ]
              Set the options for the shell and/or set the positional parameters.  More.
PAGE
  cat > "$ZSHMAN/zshparam" << 'PAGE'
PARAMETERS SET BY THE SHELL
       status <S> <Z>
              Same as ?.

PARAMETERS USED BY THE SHELL
       path <S> <Z> (PATH <S>)
              An array (colon-separated list) of directories to search for commands.  When set.
PAGE
  cat > "$ZSHMAN/zshzle" << 'PAGE'
ZLE BUILTINS
       The ZLE module contains three related builtin commands.  The
       bindkey command manipulates keymaps and key bindings.

       bindkey [ options ] -l [ -L ] [ keymap ... ]
       bindkey [ options ] -d
              bindkey's options can be divided into three categories:

STANDARD WIDGETS
       accept-line (^J ^M) (^J ^M) (^J ^M)
              Finish editing the buffer.  Normally this executes it.

       vi-change-whole-line (unbound) (S) (unbound)
              Kill the current line.
PAGE
}

@test "zsh: the manual's entries with their kind and first sentence; inline tags, synopses, pointers" {
  zsh_pages
  run src zsh
  [ "$status" -eq 0 ]
  local ids
  ids="$(printf '%s\n' "$output" | cut -f1 | sort | paste -sd' ')"
  [ "$ids" = "zshbuiltins:. zshbuiltins:sched zshbuiltins:set zshoptions:AUTO_CD zshoptions:CD_SILENT zshoptions:EMACS zshparam:path zshparam:status zshzle:accept-line zshzle:bindkey zshzle:vi-change-whole-line" ]
  [[ "$output" == *$'zshoptions:AUTO_CD\tAUTO_CD '*" option      If a command is issued that can't be executed, perform the cd command."* ]]
  [[ "$output" == *$'zshoptions:EMACS\t'*"If ZLE is loaded, turning on this option has the effect of \`bindkey -e'."* ]]
  [[ "$output" == *$'zshbuiltins:set\t'*"builtin     Set the options for the shell and/or set the positional parameters."* ]]
  [[ "$output" == *$'zshzle:bindkey\t'*"zle builtin bindkey's options can be divided into three categories:"* ]]
  [[ "$output" == *$'zshparam:status\t'*"parameter   Same as ?."* ]]
}

@test "zsh: the index is cached by the pages' files and times; a changed page builds it again" {
  zsh_pages
  src zsh > /dev/null
  : > "$CALLS"
  src zsh > /dev/null
  run grep -cx 'man zshoptions' "$CALLS"
  [ "$output" = 0 ]
  [ "$(find "$FZX_CACHE_DIR/man" -name 'zsh-*.tsv' | wc -l)" -eq 1 ]
  touch -d '2001-01-01' "$ZSHMAN/zshoptions"
  src zsh > /dev/null
  grep -qx 'man zshoptions' "$CALLS"
  [ "$(find "$FZX_CACHE_DIR/man" -name 'zsh-*.tsv' | wc -l)" -eq 1 ]
}

@test "zsh: the preview is the entry's text alone; a sentence starting with the name is not the entry" {
  zsh_pages
  FZX_MODE=zsh run "$MAN/preview.sh" zshoptions:AUTO_CD
  [ "${lines[0]}" = "AUTO_CD (-J)" ]
  [[ "$output" == *"perform the cd command"* && "$output" != *CD_SILENT* ]]
  FZX_MODE=zsh run "$MAN/preview.sh" zshzle:bindkey
  [ "${lines[0]}" = "bindkey [ options ] -l [ -L ] [ keymap ... ]" ]
  [[ "$output" != *"keymaps and key bindings"* && "$output" == *"three categories"* ]]
  FZX_MODE=zsh run "$MAN/preview.sh" zshbuiltins:sched
  [[ "${lines[0]}" == "sched  See the section"* ]]
  [ "${#lines[@]}" -eq 1 ]
}

@test "zsh: open runs less at the entry's line (no \$ in the + command), nvim searches at VimEnter" {
  zsh_pages
  printf '#!/usr/bin/env bash\nprintf "less %%s\\n" "$*" >> "$CALLS"\ncat > /dev/null\n' > "$BATS_TEST_TMPDIR/bin/less"
  chmod +x "$BATS_TEST_TMPDIR/bin/less"
  FZX_MODE=zsh "$MAN/actions.sh" open zshoptions:AUTO_CD 'zshbuiltins:.'
  grep -qxF 'less -R -j3 +/^ {7}AUTO_CD\b' "$CALLS"
  grep -qxF 'less -R -j3 +/^ {7}\. ' "$CALLS"
  FZX_MODE=zsh "$MAN/actions.sh" nvim zshoptions:CD_SILENT
  grep -qxF "nvim -c Man zshoptions -c only -c autocmd VimEnter * ++once call search('^\\s\\{7}\\VCD_SILENT\\m\\>')" "$CALLS"
}

@test "zsh: in the menu where the zsh pages are installed, counting the entries" {
  load_libs log
  source "$MAN/manifest.sh"
  run man::applicable man:zsh
  [ "$status" -ne 0 ]
  zsh_pages
  man::applicable man:zsh
  [ "$(man::summary man:zsh)" = "11 entries" ]
}
