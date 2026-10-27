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
