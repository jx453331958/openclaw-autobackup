#!/bin/bash

# Build the application
echo "Building openclaw-autobackup..."
go build -o openclaw-autobackup

# Start the server
echo "Starting openclaw-autobackup..."
./openclaw-autobackup
