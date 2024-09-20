#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10
#SBATCH --time=8:00:00
#SBATCH --mem-per-cpu=30G
#SBATCH --job-name=fst_conv
#SBATCH --output=fst_rev2.out
#SBATCH --error=fst_rev2.err

module load stack/2024-06
module load r/4.3.2
module load perl/5.38.0-4lrahtt
module load curl/8.4.0-s6dtj75
module load proj
module load gdal
module load geos
module load sqlite

export OMP_NUM_THREADS=1

Rscript convert_fst.R