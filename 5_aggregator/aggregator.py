import os
import sys
import numpy as np
import rasterio
import glob
from rasterio.enums import Resampling

# Retrieve the arguments passed from the Bash script
species_list_path = sys.argv[1]
input_path = sys.argv[2]
output_path = sys.argv[3]
reference_raster_path = sys.argv[4]
scenarios = sys.argv[5].split()  # Split the SCENARIOS into a list
periods = sys.argv[6].split()  # Split the PERIODS into a list
NCP = sys.argv[7]

# Loop over SCENARIOS and PERIODS
for SCENARIO in scenarios:
    for PERIOD in periods:
        # Identify TIFF files to be processed
        species_list = open(species_list_path).read().splitlines()
        tiff_files = [file for species in species_list for file in glob.glob(f"{input_path}/{SCENARIO}/{PERIOD}/{species}/{species.replace(' ', '.')}*.tif")]

        # Read the reference raster to get the mask values
        with rasterio.open(reference_raster_path) as ref_src:
            ref_raster = ref_src.read(1)
            ref_nodata = ref_src.nodata
            profile = ref_src.profile
        
        # Initialize variables for the sum of rasters and the count of rasters
        sum_raster = np.zeros_like(ref_raster, dtype=np.float32)  # Use float32 for more efficient storage
        count_raster = np.zeros_like(ref_raster, dtype=np.float32)

        # Iterate over each TIFF file
        for tiff_file in tiff_files:
            print(f"Processing file: {tiff_file}")
            with rasterio.open(tiff_file) as src:
                raster = src.read(1, masked=True)  # Read the first band as a masked array
                # Add the valid values to the sum_raster and update the count_raster
                sum_raster += raster.filled(0)  # Treat masked values as 0 for summing
                count_raster += ~raster.mask  # Increment count where data is valid

        # Compute the average raster
        average_raster = np.divide(sum_raster, count_raster, out=np.zeros_like(sum_raster), where=(count_raster != 0))

        # Round the average raster to the nearest integer and convert to float32
        average_raster_rounded = np.round(average_raster).astype(np.float32)  # Use float32 to accommodate NaN

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
            dtype=rasterio.float32,  # Use float32 to accommodate NaN
            crs=ref_src.crs,
            transform=ref_src.transform,
            nodata=np.nan,  # Use NaN for nodata in float32
            compress='lzw',  # Apply LZW compression
            tiled=True  # Enable tiling
        ) as dst:
            dst.write(average_raster_rounded, 1)

        print(f"Average raster saved to {output_path_file} with compression and optimized data type")