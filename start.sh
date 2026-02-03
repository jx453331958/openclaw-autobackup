#!/bin/bash
cd "$(dirname "$0")"
set -a
source .env
set +a
exec ./openclaw-autobackup
