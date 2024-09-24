#!/bin/bash

# Exit on any error
set -e

# Function to clean up on script exit (optional)
cleanup() {
  if [ $? -ne 0 ]; then
    echo "An error occurred. Cleaning up and exiting."
  fi
}

# Set trap to call the cleanup function on script exit
trap cleanup EXIT

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

# Function to submit jobs
submit_job() {
  local job_name=$1
  local mem=$2
  local time=$3
  local cpus=$4
  local ntasks=$5
  local job_command=$6
  local array_flag=$7
  local log_dir=$8   # New parameter for log directory

  # Create timestamp
  local timestamp=$(date +%Y%m%d_%H%M%S)

  # Customize output and error filenames
  if [ -z "$array_flag" ]; then
    # No array job, standard log filenamesblue
    local output_file="${log_dir}/${job_name}_$timestamp.out"
    local error_file="${log_dir}/${job_name}_$timestamp.err"
  else
    # Array job, log filenames include job and array task IDs
    local output_file="${log_dir}/${job_name}_%A_%a_$timestamp.out"
    local error_file="${log_dir}/${job_name}_%A_%a_$timestamp.err"
  fi

  echo "Submitting $job_name job..."
  if [ -z "$array_flag" ]; then
    # Standard job submission
    sbatch --wait --job-name="$job_name" \
           --output="$output_file" \
           --error="$error_file" \
           --mem-per-cpu="$mem" --time="$time" --cpus-per-task="$cpus" --ntasks="$ntasks" --wrap="$job_command"
  else
    # Array job submission
    sbatch --wait --job-name="$job_name" \
           --output="$output_file" \
           --error="$error_file" \
           --mem-per-cpu="$mem" --time="$time" --cpus-per-task="$cpus" --ntasks="$ntasks" --array="$array_flag" --wrap="$job_command"
  fi

  # Check if the job submission was successful
  if [[ $? -eq 0 ]]; then
    echo "$job_name completed successfully."
  else
    echo "Error: $job_name submission failed."
    exit 1
  fi
}

# Function to count the number of items
count_items() {
  local list=$1
  echo $(( $(grep -o "'" <<< "$list" | wc -l) / 2 ))
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
rm -r "$wp/tmp/$project/*" 2>/dev/null || true

# Create required directories if they don't already exist
mkdir -p "$svp/outputs/$project/" 2>/dev/null || true
mkdir -p "$sop/outputs/$project/" 2>/dev/null || true
mkdir -p "$sop/tmp/$project/" 2>/dev/null || true
mkdir -p "$wp/tmp/$project/settings/tmp/" 2>/dev/null || true
mkdir -p "$wp/tmp/$project/sacct/" 2>/dev/null || true

# Set directory permissions (make them writable by all users)
echo "Setting permissions for project directories..."
chmod -R 777 "$wp/data/$project" 2>/dev/null || true
chmod -R 777 "$wp/scripts/$project" 2>/dev/null || true
chmod -R 777 "$wp/tmp/$project" 2>/dev/null || true

# Clean up old log files from the mainPRE script if they exist
echo "Cleaning existing log files from mainPRE..."
rm "$wp/scripts/$project/main/0_mainPRE/logs/"*.err 2>/dev/null || true
rm "$wp/scripts/$project/main/0_mainPRE/logs/"*.out 2>/dev/null || true

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
# ln -s "$FOCAL_OUTPUT_BASE_DIR" "$wp/data/$project/covariates/reg/lulc/agg11" 2>/dev/null || true
echo "Focal layers linked."

# Display welcome message with project and session ID
echo "Welcome to this new $project run, Session ID: $ssl_id"

# PRE_A Job
PRE_A_m=$(get_value "pre_A_m")  # Memory
PRE_A_t=$(get_value "pre_A_t")  # Time
PRE_A_c=$(get_value "pre_A_c")  # Cores

pre_A_job() {
  local job_name="pre_A"
  local log_dir="./0_mainPRE/logs"
  local job_command="export OMP_NUM_THREADS=1; Rscript ./0_mainPRE/pre_A.R"
  submit_job "$job_name" "$PRE_A_m" "$PRE_A_t" "$PRE_A_c" 1 "$job_command" "" "$log_dir"
}
pre_A_job

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
  Rscript ./0_mainPRE/nsdm_update.R >/dev/null 2>&1 || true
  if [[ $? -eq 0 ]]; then
    echo "N-SDM settings updated successfully."
  else
    echo "Error: Failed to update N-SDM settings for run $i."
    exit 1
  fi

 # Retrieve the number of species to model in this run
  n_spe="$(cat "$wp/tmp/$project/settings/tmp/n_spe.txt")"
  echo "Number of species to be modeled in this run: $n_spe"

# Retrieve modelling algorithms, nesting methods, scenarios, and periods using get_value
mod_algo=$(get_value "mod_algo")  # Modelling algorithms evaluated
n_algo=$(count_items "$mod_algo") # Number of modelling algorithms

nest_met=$(get_value "nesting_methods")  # Nesting methods evaluated
n_nesting=$(count_items "$nest_met")     # Number of nesting methods

scenars=$(get_value "proj_scenarios")    # Projection scenarios evaluated
n_scenarios=$(count_items "$scenars")    # Number of projection scenarios

periods=$(get_value "proj_periods")      # Projection periods evaluated
n_periods=$(count_items "$periods")      # Number of projection periods

END_A_a=$n_spe

# Define file patterns to clean
file_patterns=("*.err" "*.out")

# Define log_dirs
log_dirs=(
  "$wp/scripts/$project/main/1_mainGLO/"
  "$wp/scripts/$project/main/2_mainREG/"
  "$wp/scripts/$project/main/3_mainFUT/"
  "$wp/scripts/$project/main/4_mainEND/"
  "$wp/scripts/$project/main/5_aggregator/"
)

# Loop through directories and file patterns to remove log files
for dir in "${log_dirs[@]}"; do
    for pattern in "${file_patterns[@]}"; do
      find "$dir" -type f -name "$pattern" -exec rm -f {} \; 2>/dev/null || true
    done
done


# Clean scratch output folder if requested
clear_sop=$(get_value "clear_sop")
if [ "$clear_sop" = "TRUE" ]; then
    echo "Clearing scratch output and temporary directories..."
    rm -r $sop/outputs/$project/* 2>/dev/null || true
    rm -r $sop/tmp/$project/* 2>/dev/null || true
fi

# Retrieve n_levels and do_proj values from settings.csv
n_levels=$(get_value "n_levels")  # Number of levels of analyses
do_proj=$(get_value "do_proj")    # Do future analyses?

# PRE_B Job
cd $wp/scripts/$project/main
PRE_B_m=$(get_value "pre_B_m")
PRE_B_t=$(get_value "pre_B_t")
PRE_B_c=$(get_value "pre_B_c")

pre_B_job() {
  local job_name="pre_B"
  local log_dir="./logs"
  local job_command="export OMP_NUM_THREADS=1; Rscript pre_B.R"
  mkdir -p "$log_dir"
  submit_job "$job_name" "$PRE_B_m" "$PRE_B_t" "$PRE_B_c" 1 "$job_command" "" "$log_dir"
}
cd "$wp/scripts/$project/main/0_mainPRE"
pre_B_job

# GLOBAL level
cd "$wp/scripts/$project/main"
# GLO_A job
GLO_A_m=$(get_value "glo_A_m")
GLO_A_t=$(get_value "glo_A_t")
GLO_A_c=$(get_value "glo_A_c")
GLO_A_a=$n_spe

glo_A_job() {
  local job_name="glo_A"
  local log_dir="./logs"
  local array_flag="[1-$GLO_A_a]"
  local job_command="export OMP_NUM_THREADS=1; Rscript glo_A.R \$SLURM_ARRAY_TASK_ID"
  mkdir -p "$log_dir"
  submit_job "$job_name" "$GLO_A_m" "$GLO_A_t" "$GLO_A_c" 1 "$job_command" "$array_flag" "$log_dir"
}

# GLO_B job
GLO_B_m=$(get_value "glo_B_m")
GLO_B_t=$(get_value "glo_B_t")
GLO_B_c=$(get_value "glo_B_c")
GLO_B_a=$((n_spe * n_algo))

glo_B_job() {
  local job_name="glo_B"
  local log_dir="./logs"
  local array_flag="[1-$GLO_B_a]"
  local job_command="export OMP_NUM_THREADS=1; Rscript glo_B.R \$SLURM_ARRAY_TASK_ID"
  mkdir -p "$log_dir"
  submit_job "$job_name" "$GLO_B_m" "$GLO_B_t" "$GLO_B_c" 1 "$job_command" "$array_flag" "$log_dir"
}

# GLO_C job
GLO_C_m=$(get_value "glo_C_m")
GLO_C_t=$(get_value "glo_C_t")
GLO_C_c=$(get_value "glo_C_c")
GLO_C_a=$n_spe

glo_C_job() {
  local job_name="glo_C"
  local log_dir="./logs"
  local array_flag="[1-$GLO_C_a]"
  local job_command="export OMP_NUM_THREADS=1; Rscript glo_C.R \$SLURM_ARRAY_TASK_ID"
  mkdir -p "$log_dir"
  submit_job "$job_name" "$GLO_C_m" "$GLO_C_t" "$GLO_C_c" 1 "$job_command" "$array_flag" "$log_dir"
}

# Run all GLO jobs
cd "$wp/scripts/$project/main/1_mainGLO"
glo_A_job
glo_B_job
glo_C_job

if [ $n_levels -gt 1 ]; then 
    ## REGIONAL level
    cd "$wp/scripts/$project/main"
    # REG_A job
    REG_A_m=$(get_value "reg_A_m")
    REG_A_t=$(get_value "reg_A_t")
    REG_A_c=$(get_value "reg_A_c")
    REG_A_a=$n_spe

    reg_A_job() {
      local job_name="reg_A"
      local log_dir="./logs"
      local array_flag="[1-$REG_A_a]"
      local job_command="export OMP_NUM_THREADS=1; Rscript reg_A.R \$SLURM_ARRAY_TASK_ID"
      mkdir -p "$log_dir"
      submit_job "$job_name" "$REG_A_m" "$REG_A_t" "$REG_A_c" 1 "$job_command" "$array_flag" "$log_dir"
    }

    # REG_B job
    REG_B_m=$(get_value "reg_B_m")
    REG_B_t=$(get_value "reg_B_t")
    REG_B_c=$(get_value "reg_B_c")
    REG_B_a=$((n_spe * n_algo * n_nesting))

    reg_B_job() {
      local job_name="reg_B"
      local log_dir="./logs"
      local array_flag="[1-$REG_B_a]"
      local job_command="export OMP_NUM_THREADS=1; Rscript reg_B.R \$SLURM_ARRAY_TASK_ID"
      mkdir -p "$log_dir"
      submit_job "$job_name" "$REG_B_m" "$REG_B_t" "$REG_B_c" 1 "$job_command" "$array_flag" "$log_dir"
    }

    # REG_C job
    REG_C_m=$(get_value "reg_C_m")
    REG_C_t=$(get_value "reg_C_t")
    REG_C_c=$(get_value "reg_C_c")
    REG_C_a=$((n_spe * n_nesting))

    reg_C_job() {
      local job_name="reg_C"
      local log_dir="./logs"
      local array_flag="[1-$REG_C_a]"
      local job_command="export OMP_NUM_THREADS=1; Rscript reg_C.R \$SLURM_ARRAY_TASK_ID"
      mkdir -p "$log_dir"
      submit_job "$job_name" "$REG_C_m" "$REG_C_t" "$REG_C_c" 1 "$job_command" "$array_flag" "$log_dir"
    }

    # Run all REG jobs
	cd "$wp/scripts/$project/main/2_mainREG"
    reg_A_job
    reg_B_job
    reg_C_job
fi

if [ $do_proj = "TRUE" ]; then
    ## Projections
    cd "$wp/scripts/$project/main"
    # FUT_A job
    FUT_A_m=$(get_value "fut_A_m")
    FUT_A_t=$(get_value "fut_A_t")
    FUT_A_c=$(get_value "fut_A_c")
    FUT_A_a=$((n_spe * n_scenarios))

    fut_A_job() {
      local job_name="fut_A"
      local log_dir="./logs"
      local array_flag="[1-$FUT_A_a]"
      local job_command="export OMP_NUM_THREADS=1; Rscript fut_A.R \$SLURM_ARRAY_TASK_ID"
      mkdir -p "$log_dir"
      submit_job "$job_name" "$FUT_A_m" "$FUT_A_t" "$FUT_A_c" 1 "$job_command" "$array_flag" "$log_dir"
    }

    # FUT_B job
    FUT_B_m=$(get_value "fut_B_m")
    FUT_B_t=$(get_value "fut_B_t")
    FUT_B_c=$(get_value "fut_B_c")
    FUT_B_a=$n_spe

    fut_B_job() {
      local job_name="fut_B"
      local log_dir="./logs"
      local array_flag="[1-$FUT_B_a]"
      local job_command="export OMP_NUM_THREADS=1; Rscript fut_B.R \$SLURM_ARRAY_TASK_ID"
      mkdir -p "$log_dir"
      submit_job "$job_name" "$FUT_B_m" "$FUT_B_t" "$FUT_B_c" 1 "$job_command" "$array_flag" "$log_dir"
    }

    # Run all FUT jobs
	cd "$wp/scripts/$project/main/3_mainFUT"
    fut_A_job
    fut_B_job

    if [ $n_levels -gt 1 ]; then
        cd "$wp/scripts/$project/main"
        # FUT_C job
        FUT_C_m=$(get_value "fut_C_m")
        FUT_C_t=$(get_value "fut_C_t")
        FUT_C_c=$(get_value "fut_C_c")
        FUT_C_a=$((n_spe * n_nesting * sim_combs))

        fut_C_job() {
          local job_name="fut_C"
          local log_dir="./logs"
          local array_flag="[1-$FUT_C_a]"
          local job_command="export OMP_NUM_THREADS=1; Rscript fut_C.R \$SLURM_ARRAY_TASK_ID"
          mkdir -p "$log_dir"
          submit_job "$job_name" "$FUT_C_m" "$FUT_C_t" "$FUT_C_c" 1 "$job_command" "$array_flag" "$log_dir"
        }

        # FUT_D job
        FUT_D_m=$(get_value "fut_D_m")
        FUT_D_t=$(get_value "fut_D_t")
        FUT_D_c=$(get_value "fut_D_c")
        FUT_D_a=$((n_spe * n_nesting))

        fut_D_job() {
          local job_name="fut_D"
          local log_dir="./logs"
          local array_flag="[1-$FUT_D_a]"
          local job_command="export OMP_NUM_THREADS=1; Rscript fut_D.R \$SLURM_ARRAY_TASK_ID"
          mkdir -p "$log_dir"
          submit_job "$job_name" "$FUT_D_m" "$FUT_D_t" "$FUT_D_c" 1 "$job_command" "$array_flag" "$log_dir"
        }

        # Run all FUT jobs
		cd "$wp/scripts/$project/main/3_mainFUT"
        fut_C_job
        fut_D_job
    fi
fi

## END
cd "$wp/scripts/$project/main"
END_A_m=$(get_value "end_A_m")
END_A_t=$(get_value "end_A_t")
END_A_c=$(get_value "end_A_c")
END_A_a=$n_spe

end_A_job() {
  local job_name="end_A"
  local log_dir="./logs"
  local array_flag="[1-$END_A_a]"
  local job_command="export OMP_NUM_THREADS=1; Rscript end_A.R \$SLURM_ARRAY_TASK_ID"
  mkdir -p "$log_dir"
  submit_job "$job_name" "$END_A_m" "$END_A_t" "$END_A_c" 1 "$job_command" "$array_flag" "$log_dir"
}
cd "$wp/scripts/$project/main/4_mainEND"
end_A_job

# END_B script
sacct --starttime $dt -u $own --format JobID,JobName,Elapsed,NCPUs,TotalCPU,CPUTime,ReqMem,MaxRSS,MaxDiskRead,MaxDiskWrite,State,ExitCode > $wp/tmp/$project/sacct/"${ssl_id}_${i}_sacct.txt"
Rscript end_B.R >/dev/null 2>&1 || true
if [[ $? -eq 0 ]]; then
  echo "END_B achieved successfully."
else
  echo "Error: END_B command failed."
  exit 1
fi

# Permissions
chmod -R 777 $wp/scripts/$project/main

# Find and sync relevant model files
cd "$sop/outputs/$project/"
find d2_models/ -name '*glm.rds' -o -name '*gam.rds' -o -name '*rf.rds' -o -name '*max.rds' -o -name '*gbm.rds' -o -name '*esm.rds' > $wp/tmp/$project/settings/tmp/modfiles.txt
rsync -a --files-from=$wp/tmp/$project/settings/tmp/modfiles.txt . $svp/outputs/$project

# Generate exclusion list and sync excluding files
echo $(awk -F ";" '$1 == "rsync_exclude" { print $2}' $wp/scripts/$project/main/settings/settings.csv) | sed 's/,/\n/g' > $wp/tmp/$project/settings/tmp/exclfiles.txt
rsync -a --exclude-from="$wp/tmp/$project/settings/tmp/exclfiles.txt" $sop/outputs/$project/ $svp/outputs/$project

echo "Outputs synced to saving location."
done

# Aggregations
aggregation_job() {
    local NCP=$1
    local job_name="agg_$NCP"
    local log_dir="./logs"
    local species_list_path="$wp/scripts/$project/main/5_aggregator/groups/${NCP}.txt"
    local output_path="$svp/outputs/$project/NCPs/${NCP}"
    local job_command="python aggregator.py \"$species_list_path\" \"$input_path\" \"$output_path\" \"$reference_raster_path\" \"$SCENARIOS\" \"$PERIODS\" \"$NCP\""
    
    mkdir -p "$output_path"
    mkdir -p "$log_dir"
    
    # Inform that the aggregation for this NCP is starting
    echo "Starting aggregation for NCP group: $NCP"
    
    # Submit the aggregation job using submit_job
    submit_job "$job_name" "4G" "01:00:00" 4 1 "$job_command" "" "$log_dir"

    # Inform that the job for this NCP has been submitted
    echo "Aggregation job for NCP group $NCP has been submitted."
}

# Aggregations
cd "$wp/scripts/$project/main/5_aggregator/"

# Inform that we are starting the aggregation process
echo "Starting the aggregation process..."

# Get list of group NCPs by removing file extensions from files in the groups folder
NCPS=($(ls "$wp/scripts/$project/main/5_aggregator/groups" | sed 's/\.[^.]*$//'))

# Extract SCENARIOS from the simulation_combis.txt file
SCENARIOS=$(awk -F'_' '{print $1}' "$wp/scripts/$project/main/auxil/simulation_combis.txt")

# Define the time periods from 2020 to 2060, incrementing by 5
PERIODS=$(seq 2020 5 2060)

# Define paths
reference_raster_path="$wp/scripts/$project/main/5_aggregator/reference_raster.tif"
input_path="$svp/outputs/$project/d15_ensembles-fut/reg/covariate"

# Loop through each NCP group and submit jobs
for NCP in "${NCPS[@]}"; do
    aggregation_job "$NCP"
done

# Inform that nsdm.sh is completed
echo "Finished."