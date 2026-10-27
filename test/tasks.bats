#!/usr/bin/env bats
# the tasks module over fixture repositories (a stub ghq lists them); runners are stubs that log their calls

load test_helper

TASKS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/tasks")"

setup() {
  setup_fzx
  ROOT="$BATS_TEST_TMPDIR/ghq"
  A="$ROOT/github.com/me/alpha"
  B="$ROOT/github.com/me/beta"
  STUBS="$BATS_TEST_TMPDIR/bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$A" "$B/.cargo" "$STUBS"
  git -C "$A" init -q && git -C "$B" init -q
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nfind "%s" -mindepth 3 -maxdepth 3 -type d | sort\n' "$CALLS" "$ROOT" > "$STUBS/ghq"
  for runner in make pnpm npm cargo poe; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s in %%s\\n" "%s" "$*" "$PWD" >> "%s"\n' "$runner" "$CALLS" > "$STUBS/$runner"
  done
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"

  cat > "$A/Makefile" << 'EOF'
VERSION := 1.0
CC ?= gcc
.PHONY: build test

## compile everything
build: deps
	$(CC) -o app main.c
	@echo built

test: build ## run the tests
	./app --test

%.o: %.c
	$(CC) -c $<

lint fmt:
	true
EOF
  printf '{\n  "dependencies": { "build": "1.0" },\n  "scripts": {\n    "dev": "vite",\n    "build": "vite build"\n  }\n}\n' > "$A/package.json"
  touch "$A/pnpm-lock.yaml"
  cat > "$B/pyproject.toml" << 'EOF'
[project]
name = "beta"

[tool.poe.tasks]
serve = { cmd = "python -m http.server", help = "serve the docs" }
check = "ruff check ."

[tool.pdm.scripts]
_private = "x"
EOF
  printf '[alias]\nxt = "test --workspace"\n' > "$B/.cargo/config.toml"
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
src() { FZX_MODE="$1" "$TASKS/source.sh" | plain; }
act() { FZX_MODE="$1" "$TASKS/actions.sh" "${@:2}"; }

@test "scan: make targets (docs from ## either place; no patterns, specials or variables), npm scripts, toml" {
  run "$TASKS/source.sh" --scan "$A"
  [ "${lines[0]}" = "$A"$'\t'make$'\t'build$'\t'"compile everything" ]
  [ "${lines[1]}" = "$A"$'\t'make$'\t'test$'\t'"run the tests" ]
  [ "${lines[2]}" = "$A"$'\t'make$'\t'lint$'\t' ]
  [ "${lines[3]}" = "$A"$'\t'make$'\t'fmt$'\t' ]
  [ "${lines[4]}" = "$A"$'\t'npm$'\t'dev$'\t'vite ]
  [ "${lines[5]}" = "$A"$'\t'npm$'\t'build$'\t'"vite build" ]
  [ "${#lines[@]}" -eq 6 ]
  run "$TASKS/source.sh" --scan "$B"
  [ "${lines[0]}" = "$B"$'\t'cargo$'\t'xt$'\t'"test --workspace" ]
  [ "${lines[1]}" = "$B"$'\t'poe$'\t'serve$'\t'"serve the docs" ]
  [ "${lines[2]}" = "$B"$'\t'poe$'\t'check$'\t'"ruff check ." ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "scan: just recipes with their docs, private ones left out" {
  command -v just > /dev/null && command -v jq > /dev/null || skip "just or jq not installed"
  printf '# start the server\nserve port="8080":\n    echo {{port}}\n\n_hidden:\n    true\n' > "$B/justfile"
  run "$TASKS/source.sh" --scan "$B"
  [[ "$output" == *"$B"$'\t'just$'\t'serve$'\t'"start the server"* ]]
  [[ "$output" != *_hidden* ]]
}

@test "modes: selected is this repository's tasks and the picks; repos the chosen projects; projects marks" {
  cd "$A"
  run src selected
  [ "${#lines[@]}" -eq 6 ]
  [[ "${lines[0]}" == "$A|make|build"$'\t'"alpha:build"$'\t'"⌂ alpha:build"*"make"*"compile everything" ]]
  # pick a task of beta: it joins selected, marked
  act all pick "$B|poe|serve"
  run src selected
  [[ "${lines[6]}" == "$B|poe|serve"$'\t'"beta:serve"$'\t'"● beta:serve"* ]]
  run src repos
  [[ "$output" == -$'\t'-$'\t'"no projects chosen"* ]]
  act projects run "$B"
  run src repos
  [ "${#lines[@]}" -eq 3 ]
  run src projects
  [[ "${lines[0]}" == "$A"$'\t'"$A"$'\t'"⌂ alpha"*"4 make, 2 npm"* ]]
  [[ "${lines[1]}" == "$B"$'\t'"$B"$'\t'"● beta"*"1 cargo, 2 poe"* ]]
  # picking again takes it out
  act all pick "$B|poe|serve"
  act projects pick "$B"
  [ ! -s "$FZX_STATE_DIR/tasks/selected" ] && [ ! -s "$FZX_STATE_DIR/tasks/projects" ]
  cd "$BATS_TEST_TMPDIR"
  run src selected
  [[ "$output" == -$'\t'-$'\t'"no tasks here and none picked"* ]]
}

@test "index: scanned once and served; past the ttl served stale and scanned again in the background" {
  cd "$BATS_TEST_TMPDIR"
  run src all
  [ "${#lines[@]}" -eq 9 ]
  run src all
  [ "$(grep -c '^list' "$CALLS")" -eq 1 ]
  printf 'serve:\n\ttrue\n' > "$B/Makefile"
  touch -d '2 hours ago' "$FZX_CACHE_DIR/tasks/index"
  run src all
  [ "${#lines[@]}" -eq 9 ]
  local i
  for i in $(seq 50); do grep -q $'\tmake\tserve' "$FZX_CACHE_DIR/tasks/index" && break; sleep 0.1; done
  run src all
  [ "${#lines[@]}" -eq 10 ]
  act all rescan
  [ ! -e "$FZX_CACHE_DIR/tasks/index" ]
}

@test "run: from the repository, with the lockfile's package manager; arguments appended, names quoted" {
  act all run "$A|npm|build" < /dev/null
  grep -qx "pnpm run build in $A" "$CALLS"
  act all run "$A|make|test" < /dev/null
  grep -qx "make test in $A" "$CALLS"
  act all run "$B|cargo|xt" < /dev/null
  act all run "$B|poe|check" < /dev/null
  grep -qx "cargo xt in $B" "$CALLS" && grep -qx "poe check in $B" "$CALLS"
  rm "$A/pnpm-lock.yaml"
  load_libs log
  source "$TASKS/actions.sh"
  local cmd
  tasks::command "$A" npm 'build:prod; rm -rf x' cmd
  [ "$cmd" = 'npm run build:prod\;\ rm\ -rf\ x' ]
  # the - row of an empty list does nothing
  act selected run - < /dev/null
}

@test "locate and preview: the make rule with its recipe, the script (not the dependency), the toml entry" {
  load_libs log
  source "$TASKS/actions.sh"
  run tasks::locate "$A" make build
  [ "$output" = "$A/Makefile 6" ]
  run tasks::locate "$A" npm build
  [ "$output" = "$A/package.json 5" ]
  run tasks::locate "$B" poe check
  [ "$output" = "$B/pyproject.toml 6" ]
  run env NO_COLOR=1 FZX_MODE=all "$TASKS/preview.sh" "$A|make|build"
  [ "${lines[0]}" = "alpha:build  make" ]
  [ "${lines[2]}" = '$ make build' ]
  [[ "$output" == *$'build: deps\n\t$(CC) -o app main.c\n\t@echo built' ]]
  run env NO_COLOR=1 FZX_MODE=projects "$TASKS/preview.sh" "$A"
  [ "${#lines[@]}" -eq 1 ]
  "$TASKS/source.sh" > /dev/null
  run env NO_COLOR=1 FZX_MODE=projects "$TASKS/preview.sh" "$A"
  [[ "${lines[1]}" == "make  build  compile everything" ]]
}

@test "under fzx: enter runs, ctrl-t picks, alt-enter asks for arguments; menu summary" {
  stub_fzf
  cd "$A"
  run "$FZX" -m tasks
  [[ "$(fzf_bind enter)" == *"_cb action run {+1}"* ]]
  [[ "$(fzf_bind ctrl-t)" == *"_cb action pick {+1}"* ]]
  [[ "$(fzf_bind alt-enter)" == *"_cb action args {+1}"* ]]
  load_libs log config menu
  fzx::menu_entries tasks "$TASKS"
  [ "$(tasks::summary tasks)" = "6 here, 0 picked" ]
}

@test "Taskfile: read with go-task only; a task command that is taskwarrior is never called" {
  command -v jq > /dev/null || skip "jq not installed"
  printf 'version: 3\ntasks:\n  up:\n    desc: start it\n' > "$B/Taskfile.yml"
  # taskwarrior answers --version with a bare number
  printf '#!/usr/bin/env bash\nprintf "taskwarrior %%s\\n" "$*" >> "%s"\n[[ "$1" == --version ]] && echo 3.1.0\n' "$CALLS" > "$STUBS/task"
  chmod +x "$STUBS/task"
  run "$TASKS/source.sh" --scan "$B"
  [[ "$output" != *$'\ttask\t'* ]]
  [ "$(grep -c '^taskwarrior' "$CALLS")" -eq 1 ] && grep -qx 'taskwarrior --version' "$CALLS"
  printf '#!/usr/bin/env bash\nprintf "go-task %%s\\n" "$*" >> "%s"\n[[ "$1" == --list-all ]] || [[ "$3" == --list-all ]] && echo %s\n' "$CALLS" "'{\"tasks\":[{\"name\":\"up\",\"desc\":\"start it\"}]}'" > "$STUBS/go-task"
  chmod +x "$STUBS/go-task"
  run "$TASKS/source.sh" --scan "$B"
  [[ "$output" == *"$B"$'\t'task$'\t'up$'\t'"start it"* ]]
  load_libs log
  source "$TASKS/actions.sh"
  local cmd
  tasks::command "$B" task up cmd
  [ "$cmd" = "go-task up" ]
}
