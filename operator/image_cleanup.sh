#!/bin/bash

# List images and iterate over each
sudo ctr -n k8s.io images ls | awk 'NR > 1 {print $1}' | while read -r image; do
    echo "Deleting image: $image"
    sudo ctr -n k8s.io images rm "$image"
done

echo "Cleanup completed."
