#!/usr/bin/env bash
# music menu entries, where mpc reaches an MPD

music::manifest() {
  fzx::entry music "Music: the play queue"
  fzx::entry music:artists "Music: artists"
  fzx::entry music:albums "Music: albums"
  fzx::entry music:playlists "Music: playlists"
}

music::applicable() {
  command -v mpc > /dev/null && command mpc status > /dev/null 2>&1
}

# music::summary <target>: what plays, the library's size, how many playlists
music::summary() {
  case "$1" in
    music) command mpc status '%state%: %currenttime%/%totaltime%, %songpos% of %length%' 2> /dev/null ;;
    music:artists) command mpc stats 2> /dev/null | command awk '/^Artists:/ { print $2 " artists" }' ;;
    music:albums) command mpc stats 2> /dev/null | command awk '/^Albums:/ { a = $2 } /^Songs:/ { s = $2 } END { print a " albums, " s " songs" }' ;;
    music:playlists) command mpc lsplaylists 2> /dev/null | command awk 'END { print NR " playlists" }' ;;
  esac
}
