import os
import sys
import numpy as np
import rasterio
import glob
from rasterio.enums import Resampling
from multiprocessing import Pool, cpu_count

# Function to process each scenario and period
def process_scenario_period(args):
    SCENARIO, PERIOD, species_list_path, input_path, output_path, reference_raster_path, NCP = args
    
    # Identify TIFF files to be processed
    species_list = open(species_list_path).read().splitlines()
    tiff_files = [file for species in species_list for file in glob.glob(f"{input_path}/{SCENARIO}/{PERIOD}/{species}/{species.replace(' ', '.')}*.tif")]

    if not tiff_files:
        print(f"No TIFF files found for SCENARIO: {SCENARIO}, PERIOD: {PERIOD}. Skipping...")
        return

    # Read the reference raster to get the mask values
    with rasterio.open(reference_raster_path) as ref_src:
        ref_raster = ref_src.read(1)
        ref_nodata = ref_src.nodata
        profile = ref_src.profile

    # Initialize variables for the sum of rasters and the count of rasters
    sum_raster = np.zeros_like(ref_raster, dtype=np.float32)
    count_raster = np.zeros_like(ref_raster, dtype=np.float32)

    # Iterate over each TIFF file
    for tiff_file in tiff_files:
        print(f"Processing file: {tiff_file}")
        with rasterio.open(tiff_file) as src:
            raster = src.read(1, masked=True)
            sum_raster += raster.filled(0)
            count_raster += ~raster.mask

    # Compute the average raster
    average_raster = np.divide(sum_raster, count_raster, out=np.zeros_like(sum_raster), where=(count_raster != 0))

    # Round the average raster to the nearest integer and convert to float32
    average_raster_rounded = np.round(average_raster).astype(np.float32)

    # Apply the NoData mask
    nodata_mask = (ref_raster == ref_nodata)
    average_raster_rounded[nodata_mask] = np.nan

    # Define the output path for the average raster
    output_filename = f"{NCP}_{SCENARIO}_{PERIOD}.tif"
    output_path_file = os.path.join(output_path, output_filename)

    # Save the rounded average raster to a new TIFF file with compression
    with rasterio.open(
        output_path_file,
        'w',
        driver='GTiff',
        height=average_raster_rounded.shape[0],
        width=average_raster_rounded.shape[1],
        count=1,
        dtype=rasterio.float32,
        crs=ref_src.crs,
        transform=ref_src.transform,
        nodata=np.nan,
        compress='lzw',
        tiled=True
    ) as dst:
        dst.write(average_raster_rounded, 1)

    print(f"Output saved to {output_path_file}")

# Retrieve the arguments passed from the Bash script
species_list_path = sys.argv[1]
input_path = sys.argv[2]
output_path = sys.argv[3]
reference_raster_path = sys.argv[4]
scenarios = sys.argv[5].split()  # Split the SCENARIOS into a list
periods = sys.argv[6].split()  # Split the PERIODS into a list
NCP = sys.argv[7]

# Prepare arguments for parallel processing
args_list = [(SCENARIO, PERIOD, species_list_path, input_path, output_path, reference_raster_path, NCP) for SCENARIO in scenarios for PERIOD in periods]

# Set up the multiprocessing pool
num_processes = min(cpu_count(), len(args_list))  # Use all available CPUs or limit to the number of tasks

# Run the parallel processing
if __name__ == "__main__":
    with Pool(processes=num_processes) as pool:
        pool.map(process_scenario_period, args_list)