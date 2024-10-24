#############################################################################
## _aggplots
## NCP plots
## Date: 20-05-2024
## Author: Nathan Kulling and Antoine Adde 
#############################################################################

# Capture the command line arguments
args <- commandArgs(trailingOnly = TRUE)

# Assign the passed arguments to variables
lib_path <- args[1]
output_path <- args[2]
plot_output_path <- args[3]

# Set permissions for new files
Sys.umask(mode="000")

# Set lib path
.libPaths(lib_path)  # Ensure 'lib_path' is defined before this point

# Load required packages
require(terra)
require(dplyr)
require(ggplot2)

# 0) File access -----------------------------------------------------------
dt <- data.frame(list.files(output_path, full.names = TRUE))
colnames(dt) <- "fullpath"

# 1) Files arrangement ----------------------------------------------------
# Create a df of paths, NCP, scenario and period
dt$basename <- basename(dt$fullpath)

# Extract NCP, scenario, and period from basename using vectorized operations
dt$NCP <- sapply(strsplit(dt$basename, "_"), function(x) x[1])
dt$scenario <- sapply(strsplit(dt$basename, "_"), function(x) x[2])
dt$period <- sapply(strsplit(dt$basename, "_"), function(x) x[3])

# 2) Summing raster values -------------------------------------------------
sum_values <- vector("list", nrow(dt))  # Predefine a list to store results

for (i in seq_len(nrow(dt))) {
  r <- rast(dt$fullpath[i])
  sum_cells <- sum(values(r), na.rm = TRUE)
  
  # Append the sum to the data frame along with the NCP, scenario, and period
  sum_values[[i]] <- data.frame(
    NCP = dt$NCP[i],
    scenario = dt$scenario[i],
    period = dt$period[i],
    sum_cells = sum_cells
  )
}

# Combine results into a single data frame
sum_df <- bind_rows(sum_values)

# 3) Plotting -------------------------------------------------------------
# Plot 1: Line plot by scenario with color groups
plot1 <- ggplot(sum_df, aes(x = period, y = sum_cells, color = as.factor(scenario), group = as.factor(scenario))) +
  geom_line(linewidth = 1) +
  labs(title = "",
       x = "Period",
       y = "HSV sum",
       color = "Scenario") +
  theme_bw()

# Save plot 1
ggsave(file.path(plot_output_path, "/plot1.png"), plot = plot1, width = 10, height = 6)

# Plot 2: Facet grid plot by scenario
plot2 <- ggplot(sum_df, aes(x = period, y = sum_cells, group = as.factor(scenario))) +
  geom_line(linewidth = 1, color = "coral") +  
  labs(title = "",
       x = "Period",
       y = "HSV sum") +
  theme_bw() +
  facet_wrap(~ scenario, ncol = 4)

# Save plot 2
ggsave(file.path(plot_output_path, "/plot2.png"), plot = plot2, width = 12, height = 8)
