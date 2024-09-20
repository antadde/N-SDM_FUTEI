#!/bin/bash

# Base directory to search
base_dir="/cluster/work/eawag/p01002/Future-EI-Output/1080_configs/focal_output/ch/lulc/agg11/future/pixel"

# Output file
output_file="file_report.csv"

# Print headers to the output file
echo "RDS File,FST Exists,RDS Size (Bytes),FST Size (Bytes)" > $output_file

# Find all .rds files in the directory and subdirectories
find "$base_dir" -type f -name "*.rds" | while read rds_file; do
    # Check if a corresponding .fst file exists
    fst_file="${rds_file%.rds}.fst"
    if [[ -f "$fst_file" ]]; then
        fst_exists="yes"
        fst_size=$(stat --printf="%s" "$fst_file")
    else
        fst_exists="no"
        fst_size=""
    fi

    # Get the size of the .rds file
    rds_size=$(stat --printf="%s" "$rds_file")

    # Write the details to the output file
    echo "$rds_file,$fst_exists,$rds_size,$fst_size" >> $output_file
done

# Print completion message
echo "Table generated in $output_file"
