#!/bin/bash

# Base directory to search
base_dir="/cluster/work/eawag/p01002/Future-EI-Output/1080_configs/focal_output/ch/lulc/agg11/future/pixel"

# Output file to store the list of .rds files without a corresponding .fst file
output_file="/cluster/work/eawag/p01002/nsdm/scripts/nsdm-project/main.txt"

# Initialize the output file
> "$output_file"

# Find all .rds files in the directory and its subdirectories
find "$base_dir" -type f -name "*.rds" | while read -r rds_file; do
  # Replace .rds with .fst to get the expected .fst file name
  fst_file="${rds_file%.rds}.fst"
  
  # Check if the corresponding .fst file exists
  if [ ! -f "$fst_file" ]; then
    echo "$rds_file" >> "$output_file"
  fi
done

echo "List of .rds files without a corresponding .fst file saved to $output_file"
