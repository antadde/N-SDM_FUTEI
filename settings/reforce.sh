# Define paths
directory_path="/cluster/project/eawag/p01002/nsdm_save/outputs/nsdm-project/d8_ensembles/reg/covariate"
csv_file="/cluster/work/eawag/p01002/nsdm/scripts/nsdm-project/main/settings/forced.csv"
output_csv="/cluster/work/eawag/p01002/nsdm/scripts/nsdm-project/main/settings/forced2.csv"

# Extract folder names into a temporary list
find "$directory_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; > folder_list.txt

# Extract lines from forced.csv that are not in the folder names and save them
grep -vFf folder_list.txt "$csv_file" > "$output_csv"

# Clean up temporary file
rm folder_list.txt
