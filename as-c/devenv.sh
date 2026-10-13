#!/bin/bash

session="ocdev"

SESSIONEXISTS=$(tmux list-sessions | grep $session)
if [ "$SESSIONEXISTS" = "" ]
then
	
tmux new-session -d -s $session

# Man Dev window
tmux rename-window -t 0 'Main'
tmux send-keys -t 'Main' 'export BUILD_BASE=..' C-m
tmux split-window -h
tmux send-keys -t 'Main' 'emacs src/parser.c' C-m

# Emulator window
tmux new-window -t $session:1 -n '65C816 Emulator'
tmux send-keys -t '65C816 Emulator' '../bin/em16 first' C-m

# Oberon code viewer window
tmux new-window -t $session:2 -n 'Oberon'
tmux send-keys -t 'Oberon' 'cd ../oberon ; emacs ORP.Mod' C-m

fi

# Attach
tmux attach-session -t $session:0

