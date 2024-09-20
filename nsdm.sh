#!/bin/bash

##########################
## nsdm.sh
## Core N-SDM script
## Date: 20-05-2022
## Author: Antoine Adde (antoine.adde@eawag.ch)
## Updated: 20-09-2024
##########################

# Function to retrieve values from the settings.csv file
get_value() {
  local key=$1
  awk -F ";" -v search_key="$key" '$1 == search_key { print $2 }' ./settings/settings.csv
}

# Load required modules
echo "Loading required modules..."
module load stack/2024-06
module load sqlite
module load python

# Dynamically load modules from settings.csv
module load "$(get_value "module_r")"
module load "$(get_value "module_proj")"
module load "$(get_value "module_perl")"
module load "$(get_value "module_curl")"
module load "$(get_value "module_geos")"
module load "$(get_value "module_gdal")"

echo "Modules loaded successfully."

# Retrieve main paths from settings.csv
echo "Retrieving main paths..."
wp=$(get_value "w_path")    # Working path
sop=$(get_value "scr_path")  # Scratch output path
svp=$(get_value "svp_path")  # Saving output path

# Retrieve project name
echo "Retrieving project name..."
project=$(get_value "project")
echo "Project name: $project"

# General definitions from settings.csv
echo "Retrieving general HPC definitions..."
own=$(get_value "sess_own")  # Session account
acc=$(get_value "account")   # HPC account
part=$(get_value "partition") # HPC partition

# Clean and/or create necessary directories
echo "Setting up output directories..."

# Remove old temporary files, if any
rm -r "$wp/tmp/$project/*" 2>/dev/null

# Create required directories if they don't already exist
mkdir -p "$svp/outputs/$project/" 2>/dev/null
mkdir -p "$sop/outputs/$project/" 2>/dev/null
mkdir -p "$sop/tmp/$project/" 2>/dev/null
mkdir -p "$wp/tmp/$project/settings/tmp/" 2>/dev/null
mkdir -p "$wp/tmp/$project/sacct/" 2>/dev/null

# Set directory permissions (make them writable by all users)
echo "Setting permissions for project directories..."
chmod -R 777 "$wp/data/$project" 2>/dev/null
chmod -R 777 "$wp/scripts/$project" 2>/dev/null
chmod -R 777 "$wp/tmp/$project" 2>/dev/null

# Clean up old log files from the mainPRE script if they exist
echo "Cleaning existing log files from mainPRE..."
rm "$wp/scripts/$project/main/0_mainPRE/"*.err 2>/dev/null
rm "$wp/scripts/$project/main/0_mainPRE/"*.out 2>/dev/null

# Generate a unique identifier for this N-SDM session
echo "Generating unique N-SDM session identifier..."
ssl_id=$(openssl rand -hex 3)
echo "$ssl_id" > "$wp/tmp/$project/settings/tmp/ssl_id.txt"
echo "Session ID: $ssl_id"

# Retrieve simulation settings
echo "Retrieving simulation settings..."
LULCC_M_SIM_CONTROL_TABLE="$wp/scripts/$project/main/auxil/simulation_control.csv"

# Create a file with simulation combinations and count the number of combinations
awk -F "," 'NR>1 {print $3"_"$11}' "$LULCC_M_SIM_CONTROL_TABLE" > "$wp/scripts/$project/main/auxil/simulation_combis.txt"

# Count the number of simulation combinations
sim_combs=$(wc -l < "$wp/scripts/$project/main/auxil/simulation_combis.txt")
echo "Total number of simulation combinations: $sim_combs"

# Link focal layers to N-SDM data folder
echo "Linking focal layers to N-SDM data folder..."
# ln -s "$FOCAL_OUTPUT_BASE_DIR" "$wp/data/$project/covariates/reg/lulc/agg11" 2>/dev/null
echo "Focal layers linked."

###############################
## Core N-SDM script - Species Occurrence Data
###############################
# Display welcome message with project and session ID
echo "Welcome to this new $project run, Session ID: $ssl_id"

# Retrieve memory, time, and cores for pre_A
pre_A_m=$(get_value "pre_A_m")  # Memory
pre_A_t=$(get_value "pre_A_t")  # Time
pre_A_c=$(get_value "pre_A_c")  # Cores

# Run the pre_A job
echo "Starting pre_A job..."
sbatch --wait --mem-per-cpu="$pre_A_m" --time="$pre_A_t" --cpus-per-task="$pre_A_c" --ntasks=1 ./0_mainPRE/job_pre_A.sh

# Check the exit status of sbatch command
if [[ $? -eq 0 ]]; then
  species_count=$(cat "$wp/tmp/$project/settings/tmp/n_spe.txt")
  echo "N-SDM settings defined, and species occurrence data for $species_count species disaggregated."
else
  echo "Error: Species occurrence data disaggregation job failed."
  exit 1
fi

# Loop over species runs to prevent scratch path saturation
spe_runs="$(cat $wp/tmp/$project/settings/tmp/spe_runs.txt)"

# Iterate through each run
for i in $(seq 1 "$spe_runs"); do
  # Save the current run ID
  echo "$i" > "$wp/tmp/$project/settings/tmp/run_id.txt"
  echo "Starting N-SDM run $i out of $spe_runs runs"

  # Retrieve current time/date for logging
  dt=$(date +"%FT%T")
  echo "Run $i started at $dt"

  # Update N-SDM settings using the R script
  cd "$wp/scripts/$project/main/" || exit 1  # Exit if directory change fails
  Rscript ./0_mainPRE/nsdm_update.R 1>/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    echo "N-SDM settings updated successfully."
  else
    echo "Error: Failed to update N-SDM settings for run $i."
    exit 1
  fi

  # Retrieve the number of species to model in this run
  n_spe="$(cat "$wp/tmp/$project/settings/tmp/n_spe.txt")"
  echo "Number of species to be modeled in this run: $n_spe"


  # Extract modelling algorithms, nesting methods, scenarios, and periods from settings.csv
  # Helper function to count the number of items in a list (assumes single quotes around items)
count_items() {
  local list=$1
  echo $(( $(grep -o "'" <<< "$list" | wc -l) / 2 ))
}
# Retrieve modelling algorithms, nesting methods, scenarios, and periods using get_value
mod_algo=$(get_value "mod_algo")  # Modelling algorithms evaluated
n_algo=$(count_items "$mod_algo") # Number of modelling algorithms

nest_met=$(get_value "nesting_methods")  # Nesting methods evaluated
n_nesting=$(count_items "$nest_met")     # Number of nesting methods

scenars=$(get_value "proj_scenarios")    # Projection scenarios evaluated
n_scenarios=$(count_items "$scenars")    # Number of projection scenarios

periods=$(get_value "proj_periods")      # Projection periods evaluated
n_periods=$(count_items "$periods")      # Number of projection periods

# Define sections and retrieve values
PRE_B_m=$(get_value "pre_B_m")
PRE_B_t=$(get_value "pre_B_t")
PRE_B_c=$(get_value "pre_B_c")

GLO_A_m=$(get_value "glo_A_m")
GLO_A_t=$(get_value "glo_A_t")
GLO_A_c=$(get_value "glo_A_c")

GLO_B_m=$(get_value "glo_B_m")
GLO_B_t=$(get_value "glo_B_t")
GLO_B_c=$(get_value "glo_B_c")

GLO_C_m=$(get_value "glo_C_m")
GLO_C_t=$(get_value "glo_C_t")
GLO_C_c=$(get_value "glo_C_c")

REG_A_m=$(get_value "reg_A_m")
REG_A_t=$(get_value "reg_A_t")
REG_A_c=$(get_value "reg_A_c")

REG_B_m=$(get_value "reg_B_m")
REG_B_t=$(get_value "reg_B_t")
REG_B_c=$(get_value "reg_B_c")

REG_C_m=$(get_value "reg_C_m")
REG_C_t=$(get_value "reg_C_t")
REG_C_c=$(get_value "reg_C_c")

FUT_A_m=$(get_value "fut_A_m")
FUT_A_t=$(get_value "fut_A_t")
FUT_A_c=$(get_value "fut_A_c")

FUT_B_m=$(get_value "fut_B_m")
FUT_B_t=$(get_value "fut_B_t")
FUT_B_c=$(get_value "fut_B_c")

FUT_C_m=$(get_value "fut_C_m")
FUT_C_t=$(get_value "fut_C_t")
FUT_C_c=$(get_value "fut_C_c")

FUT_D_m=$(get_value "fut_D_m")
FUT_D_t=$(get_value "fut_D_t")
FUT_D_c=$(get_value "fut_D_c")

END_A_m=$(get_value "end_A_m")
END_A_t=$(get_value "end_A_t")
END_A_c=$(get_value "end_A_c")

# Calculate array extents
GLO_A_a=$n_spe
GLO_B_a=$((n_spe * n_algo))
GLO_C_a=$n_spe

REG_A_a=$n_spe
REG_B_a=$((n_spe * n_algo * n_nesting))
REG_C_a=$((n_spe * n_nesting))

FUT_A_a=$((n_spe * n_scenarios))
FUT_B_a=$n_spe
FUT_C_a=$((n_spe * n_nesting * sim_combs))
FUT_D_a=$((n_spe * n_nesting))

END_A_a=$n_spe

# Define directories and file patterns to clean
log_dirs=(
  "$wp/scripts/$project/main/0_mainPRE"
  "$wp/scripts/$project/main/1_mainGLO"
  "$wp/scripts/$project/main/2_mainREG"
  "$wp/scripts/$project/main/3_mainFUT"
  "$wp/scripts/$project/main/4_mainEND"
)

# Define file patterns to clean
file_patterns=("*.err" "*.out")

# Loop through directories and file patterns to remove log files
for dir in "${log_dirs[@]}"; do
  for pattern in "${file_patterns[@]}"; do
    rm "$dir/$pattern" 2>/dev/null
  done
done

# Clean scratch output folder if requested
clear_sop=$(get_value "clear_sop")
# Safely check if clear_sop is TRUE and remove directories
if [ "$clear_sop" = "TRUE" ]; then
  if [ -n "$sop" ] && [ -n "$project" ]; then
    echo "Clearing scratch output and temporary directories..."
    rm -r "$sop/outputs/$project/*" 2>/dev/null
    rm -r "$sop/tmp/$project/*" 2>/dev/null
  else
    echo "Error: sop or project variables are not set. Skipping cleanup."
  fi
fi

# Start running jobs
## n_levels of analyses (1=GLO; 2=GLO+REG)?
n_levels=$(awk -F ";" '$1 == "n_levels" { print $2}' ./settings/settings.csv)

## Do future analyses?
do_proj=$(awk -F ";" '$1 == "do_proj" { print $2}' ./settings/settings.csv)

## PRE_B
cd $wp/scripts/$project/main/0_mainPRE
sbatch --wait --mem-per-cpu=$pre_B_m --time=$pre_B_t --cpus-per-task=$pre_B_c --ntasks=1 job_pre_B.sh
echo PRE modelling datasets generated

## GLO level
cd $wp/scripts/$project/main/1_mainGLO
sbatch --wait --mem-per-cpu=$glo_A_m --time=$glo_A_t --cpus-per-task=$glo_A_c --ntasks=1 --array [1-$glo_A_a] job_glo_A.sh
echo GLO data preparation and covariate selection done
sbatch --wait --mem-per-cpu=$glo_B_m --time=$glo_B_t --cpus-per-task=$glo_B_c --ntasks=1 --array [1-$glo_B_a] job_glo_B.sh
echo GLO modelling done
sbatch --wait --mem-per-cpu=$glo_C_m --time=$glo_C_t --cpus-per-task=$glo_C_c --ntasks=1 --array [1-$glo_C_a] job_glo_C.sh
echo GLO ensembling done

if [ $n_levels -gt 1 ]
then 
## REG level
cd $wp/scripts/$project/main/2_mainREG
sbatch --wait --mem-per-cpu=$reg_A_m --time=$reg_A_t --cpus-per-task=$reg_A_c --ntasks=1 --array [1-$reg_A_a] job_reg_A.sh
echo REG data preparation and covariate selection done
sbatch --wait --mem-per-cpu=$reg_B_m --time=$reg_B_t --cpus-per-task=$reg_B_c --ntasks=1 --array [1-$reg_B_a] job_reg_B.sh
echo REG modelling done
sbatch --wait --mem-per-cpu=$reg_C_m --time=$reg_C_t --cpus-per-task=$reg_C_c --ntasks=1 --array [1-$reg_C_a] job_reg_C.sh
echo REG ensembling and scale nesting done
fi

## FUT projections
if [ $do_proj = "TRUE" ]
then
cd $wp/scripts/$project/main/3_mainFUT
sbatch --wait --mem-per-cpu=$fut_A_m --time=$fut_A_t --cpus-per-task=$fut_A_c --ntasks=1 --array [1-$fut_A_a] job_fut_A.sh
echo individual FUT GLO predictions done
sbatch --wait --mem-per-cpu=$fut_B_m --time=$fut_B_t --cpus-per-task=$fut_B_c --ntasks=1 --array [1-$fut_B_a] job_fut_B.sh
echo FUT GLO ensembling done
if [ $n_levels -gt 1 ]
then
sbatch --wait --mem-per-cpu=$fut_C_m --time=$fut_C_t --cpus-per-task=$fut_C_c --ntasks=1 --array [1-$fut_C_a] job_fut_C.sh
echo individual FUT REG predictions done
sbatch --wait --mem-per-cpu=$fut_D_m --time=$fut_D_t --cpus-per-task=$fut_D_c --ntasks=1 --array [1-$fut_D_a] job_fut_D.sh
echo FUT REG ensembling and scale nesting done
fi
fi

## END analyses
cd $wp/scripts/$project/main/4_mainEND
sbatch --wait --mem-per-cpu=$end_A_m --time=$end_A_t --cpus-per-task=$end_A_c --ntasks=1 --array [1-$end_A_a] job_end_A.sh
echo Final evaluation done
sacct --starttime $dt -u $own --format JobID,JobName,Elapsed,NCPUs,TotalCPU,CPUTime,ReqMem,MaxRSS,MaxDiskRead,MaxDiskWrite,State,ExitCode > $wp/tmp/$project/sacct/"${ssl_id}_${i}_sacct.txt"
Rscript end_B.R 1>/dev/null 2>&1
echo Sacct outputs analysis done

# Permissions
chmod -R 777 $wp/scripts/$project/main

# rsync to saving location before cleaning scratch folder
cd $sop/outputs/$project/
find d2_models/ -name '*glm.rds' -o -name '*gam.rds' -o -name '*rf.rds' -o -name '*max.rds' -o -name '*gbm.rds' -o -name '*esm.rds' > $wp/tmp/$project/settings/tmp/modfiles.txt
rsync -a --files-from=$wp/tmp/$project/settings/tmp/modfiles.txt . $svp/outputs/$project
echo $(awk -F ";" '$1 == "rsync_exclude" { print $2}' $wp/scripts/$project/main/settings/settings.csv) | sed 's/,/\n/g' > $wp/tmp/$project/settings/tmp/exclfiles.txt
rsync -a --exclude-from="$wp/tmp/$project/settings/tmp/exclfiles.txt" $sop/outputs/$project/ $svp/outputs/$project
echo Main outputs sync to saving location
done

# Aggregations
cd $wp/scripts/$project/main/5_aggregator/

# Get list of group NCPs by removing file extensions from files in the groups folder
NCPS=($(ls "$wp/scripts/$project/main/5_aggregator/groups" | sed 's/\.[^.]*$//'))

# Extract SCENARIOS from the simulation_combis.txt file
SCENARIOS=$(awk -F'_' '{print $1}' "$wp/scripts/$project/main/auxil/simulation_combis.txt")

# Define the time periods from 2020 to 2060, incrementing by 5
PERIODS=$(seq 2020 5 2060)

# Define paths
reference_raster_path=$wp/scripts/$project/main/5_aggregator/reference_raster.tif
input_path=$svp/outputs/$project/d15_ensembles-fut/reg/covariate

# Loop through each NCP group
for NCP in "${NCPS[@]}"; do
    # Define the species list path for the current NCP
    species_list_path=$wp/scripts/$project/main/5_aggregator/groups/${NCP}.txt
	
	# Define the output path
	output_path=$svp/outputs/$project/NCPs/${NCP}
	mkdir -p $output_path
	
	# Create a temporary SLURM batch script for the current NCP
    sbatch_script=$(mktemp)
    
    # Write the SLURM script content to the temporary file
    cat <<EOT > $sbatch_script
#!/bin/bash
#SBATCH --job-name=agg_${NCP}       # Job name
#SBATCH --output=slurm-%j.out # Standard output and error log
#SBATCH --error=slurm-%j.err
#SBATCH --time=01:00:00             # Set a time limit
#SBATCH --cpus-per-task=4           # Number of CPUs per task
#SBATCH --mem-per-cpu=4G                   # Memory per job

# Load required modules if necessary (e.g., Python)
module load python

# Call the Python script with updated variables
python aggregator.py "$species_list_path" "$input_path" "$output_path" "$reference_raster_path" "$SCENARIOS" "$PERIODS" "$NCP"
EOT

    # Submit the job to SLURM
    sbatch $sbatch_script

    # Optionally remove the temp script after submission (to avoid clutter)
    rm $sbatch_script
done

echo Finished
