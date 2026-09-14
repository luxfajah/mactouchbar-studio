#!/bin/bash
cd "$(dirname "$0")/mac-companion" || exit 1
python3 mac_deck_server.py
