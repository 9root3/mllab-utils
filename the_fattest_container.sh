#!/bin/bash

# Get the list of containers with their sizes
docker ps -as --format "table {{.ID}}\t{{.Names}}\t{{.Size}}" | sort -rh -k3