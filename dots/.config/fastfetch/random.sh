#!/bin/bash

IMAGES_DIR="$HOME/.config/fastfetch/files"

RANDOM_IMAGES=$(find "$IMAGES_DIR" -type f | shuf -n 1)

fastfetch --logo file --logo "$RANDOM_IMAGES"
