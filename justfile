set dotenv-load := true
set positional-arguments := true

_default:
    @just --list --unsorted

# Open or attach a tmux session for this project.
tmux:
    tmux new-session -A -s hetzbot
