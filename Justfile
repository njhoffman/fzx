default:
    @just --list

# run the bats test suite
test *ARGS:
    bats {{ ARGS }} test

# print the resolved fzf command for a module
dry-run MODULE *ARGS:
    bin/fzx -m {{ MODULE }} --dry-run {{ ARGS }}
