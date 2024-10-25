#############################################################################
## 3_mainFUT
## D: ensembling, nesting and mapping regional-level projections
## Date: 20-05-2022
## Author: Antoine Adde 
#############################################################################

### =========================================================================
### A- Preparation
### =========================================================================
project<-gsub("/main/3_mainFUT","",gsub(".*scripts/","",getwd()))

# Load nsdm settings
load(paste0(gsub("scripts","tmp",gsub("/main/3_mainFUT","",getwd())),"/settings/nsdm-settings.RData"))

# Set permissions for new files
Sys.umask(mode="000")

# Set your working directory
setwd(w_path)

# Set lib path
.libPaths(lib_path)

# Load nsdm package
require(nsdm)

### =========================================================================
### B- Definitions
### =========================================================================
# SBATCH param
ncores<-as.numeric(Sys.getenv('SLURM_CPUS_PER_TASK'))
args<-eval(parse(text=args))
task_id <- as.numeric(args[1])
part_start <- as.numeric(args[2])
part_end <- as.numeric(args[3])

# Target species
species<-readRDS(paste0(w_path,"tmp/",project,"/settings/tmp/species-list-run.rds"))

# Target RCP for future predictions
scenars<-proj_scenarios

# Scale-nesting methods for combining GLO and REG predictions
nesting_methods<-nesting_methods

# Target simulations for future predictions
simus<-readLines(paste0(w_path,"scripts/",project,"/main/auxil/simulation_combis.txt"))[part_start:part_end]

# SBATCH array
array<-expand.grid(nesting=nesting_methods, species=species)
ispi_name <- array[task_id,"species"]
nesting_method <- array[task_id,"nesting"]
scenars_lulc<-unique(do.call(rbind,strsplit(as.character(simus), "_"))[,1])

# Target period for future predictions
pers<-proj_periods

# for(scenar_lulc in scenars_lulc){
# for (per in pers){

# cat(paste('Ready for mapping and ensembling', scenar_lulc, per, 'future REG predictions obtained for', ispi_name, 'under', nesting_method, 'nesting method...\n', sep=" "))

# ### =========================================================================
# ### C- Save prediction raster
# ### =========================================================================
# for(i in 1:length(mod_algo)){
# # Load raw prediction data
# model_name<-mod_algo[i]
# pred_path<-paste0(scr_path,"/outputs/",project,"/d13_preds-fut/reg/",nesting_method,"/",scenar_lulc,"/",per)
# full_pred_path<-paste0(paste(pred_path, ispi_name, model_name, sep="/"))
# pred_file<-list.files(full_pred_path, pattern=".rds", full.names=TRUE)
# pred<-readRDS(pred_file)

# # Predict 
# map_i<-nsdm.map(template=pred$template,
                # nona_ix=pred$nona_ix, 
                # species_name=ispi_name,
				# model_name=model_name,
				# level="reg",
				# scenar_name=scenar_lulc,
				# period_name=per,
				# nesting_name=nesting_method,
                # pred=pred$ndata_bck) 

# # Save
# nsdm.savemap(maps=map_i, species_name=ispi_name, model_name=model_name, format="rds", save_path=paste0(scr_path,"/outputs/",project,"/d14_maps-fut/reg/",nesting_method,"/",scenar_lulc,"/",per))
# cat(paste0(model_name,' predictions saved \n'))
# }

# ### =========================================================================
# ### D- Ensemble predictions
# ### =========================================================================
# ensemble_reg<-nsdm.ensemble(model_names= mod_algo, # models for ensembling
                           # species_name=ispi_name,
						   # level="reg",
						   # scenar_name=scenar_lulc,
				           # period_name=per,
				           # nesting_name=nesting_method,
                           # map_path=paste0(scr_path,"/outputs/",project,"/d14_maps-fut/reg/",nesting_method,"/",scenar_lulc,"/",per),
                           # score_path=paste0(scr_path,"/outputs/",project,"/d3_evals/reg/", nesting_method),
                           # weighting=do_weighting,
                           # weight_metric=weight_metric,
                           # discthre=disc_thre)
						   
# # File paths for each combination
# file_paths_maps <- file.path(scr_path, "outputs", project, "d14_maps-fut/reg", nesting_method, scenar_lulc, per, ispi_name)
# file_paths_preds <- file.path(scr_path, "outputs", project, "d13_preds-fut/reg", nesting_method, scenar_lulc, per, ispi_name)

# # Remove intermediate pred and map files
# unlink(file_paths_preds, recursive = TRUE, force = TRUE)
# unlink(file_paths_maps, recursive = TRUE, force = TRUE)

# nsdm.savemap(maps=ensemble_reg$ensemble, species_name=ispi_name, format="tif", model_name=NULL, save_path=paste0(scr_path,"/outputs/",project,"/d15_ensembles-fut/reg/",nesting_method,"/",scenar_lulc,"/",per))
# nsdm.savemap(maps=ensemble_reg$ensemble_cv, species_name=ispi_name, model_name=NULL, save_path=paste0(scr_path,"/outputs/",project,"/d16_ensembles-cv-fut/reg/",nesting_method,"/",scenar_lulc,"/",per))

### =========================================================================
### E- Combine REG and GLO predictions
### =========================================================================
# E.1 "Multiply" nesting
# if(nesting_method=="multiply"){
  # # response
  # ensemble_glo<-readRDS(list.files(paste0(scr_path,"/outputs/",project,"/d15_ensembles-fut/glo/",scenar_lulc,"/",per,"/",ispi_name), pattern=".rds", full.names = TRUE))
  # ensemble_nested<-sqrt(ensemble_glo*ensemble_reg$ensemble)
  # names(ensemble_nested)<-names(ensemble_reg$ensemble)
  # # # cv
  # ensemble_glo_cv<-readRDS(list.files(paste0(scr_path,"/outputs/",project,"/d16_ensembles-cv-fut/glo/",scenar_lulc,"/",per,"/",ispi_name), pattern=".rds", full.names = TRUE))
  # ensemble_nested_cv<-raster::mean(raster::stack(ensemble_reg$ensemble_cv, ensemble_glo_cv))
  # names(ensemble_nested_cv)<-names(ensemble_reg$ensemble_cv)
  # # Save
# nsdm.savemap(map=ensemble_nested, species_name=ispi_name, save_path=paste0(scr_path,"/outputs/",project,"/d17_nested-ensembles-fut/",nesting_method,"/",scenar_lulc,"/",per))
# # df_ensemble_nested<-as.data.frame(ensemble_nested)
# # fwrite(df_ensemble_nested, paste0(scr_path,"/outputs/",project,"/d17_nested-ensembles-fut/",nesting_method,"/",scenar_lulc,"/",per,"/",ispi_name,"/",ispi_name,"_reg_",nesting_method,"_",scenar_lulc,"_",per, "_ensemble.csv"))


# # nsdm.savemap(map=ensemble_nested_cv, species_name=ispi_name, save_path=paste0(scr_path,"/outputs/",project,"/d18_nested-ensembles-cv-fut/",nesting_method,"/",scenar_lulc,"/",per))
# # df_ensemble_nested_cv<-as.data.frame(ensemble_nested_cv)
# # fwrite(df_ensemble_nested_cv, paste0(scr_path,"/outputs/",project,"/d18_nested-ensembles-cv-fut/",nesting_method,"/",scenar_lulc,"/",per,"/",ispi_name,"/",ispi_name,"_reg_",nesting_method,"_",scenar_lulc,"_",per, "_ensemble_cv.csv"))
# } 

# E.2 "Covariate" nesting
# if(nesting_method=="covariate"){
# ensemble_nested<-ensemble_reg$ensemble
# ensemble_nested_cv<-ensemble_reg$ensemble_cv
# # Save
# nsdm.savemap(map=ensemble_nested, species_name=ispi_name, save_path=paste0(scr_path,"/outputs/",project,"/d17_nested-ensembles-fut/",nesting_method,"/",scenar_lulc,"/",per))
# # df_ensemble_nested<-as.data.frame(ensemble_nested)
# # fwrite(df_ensemble_nested, paste0(scr_path,"/outputs/",project,"/d17_nested-ensembles-fut/",nesting_method,"/",scenar_lulc,"/",per,"/",ispi_name,"/",ispi_name,"_reg_",nesting_method,"_",scenar_lulc,"_",per, "_ensemble.csv"))

# # nsdm.savemap(map=ensemble_nested_cv, species_name=ispi_name, save_path=paste0(scr_path,"/outputs/",project,"/d18_nested-ensembles-cv-fut/",nesting_method,"/",scenar_lulc,"/",per))
# # df_ensemble_nested_cv<-as.data.frame(ensemble_nested_cv)
# # fwrite(df_ensemble_nested_cv, paste0(scr_path,"/outputs/",project,"/d18_nested-ensembles-cv-fut/",nesting_method,"/",scenar_lulc,"/",per,"/",ispi_name,"/",ispi_name,"_reg_",nesting_method,"_",scenar_lulc,"_",per, "_ensemble_cv.csv"))
# }

# }
# }

# cat(paste0('GLO and REG predictions nested and saved \n'))
# cat(paste0('Finished!\n'))

# Define a function to process a single scenar_lulc
process_scenar_lulc <- function(scenar_lulc) {
  for (per in pers) {
    cat(paste('Ready for mapping and ensembling', scenar_lulc, per, 'future REG predictions obtained for', ispi_name, 'under', nesting_method, 'nesting method...\n', sep=" "))
    
    ### =========================================================================
    ### C- Save prediction raster
    ### =========================================================================
    for(i in 1:length(mod_algo)){
      # Load raw prediction data
      model_name<-mod_algo[i]
      pred_path<-paste0(scr_path,"/outputs/",project,"/d13_preds-fut/reg/",nesting_method,"/",scenar_lulc,"/",per)
      full_pred_path<-paste0(paste(pred_path, ispi_name, model_name, sep="/"))
      pred_file<-list.files(full_pred_path, pattern=".rds", full.names=TRUE)
      pred<-readRDS(pred_file)

      # Predict 
      map_i<-nsdm.map(template=pred$template,
                      nona_ix=pred$nona_ix, 
                      species_name=ispi_name,
                      model_name=model_name,
                      level="reg",
                      scenar_name=scenar_lulc,
                      period_name=per,
                      nesting_name=nesting_method,
                      pred=pred$ndata_bck) 

      # Save
      nsdm.savemap(maps=map_i, species_name=ispi_name, model_name=model_name, format="rds", save_path=paste0(scr_path,"/outputs/",project,"/d14_maps-fut/reg/",nesting_method,"/",scenar_lulc,"/",per))
      cat(paste0(model_name,' predictions saved \n'))
    }

    ### =========================================================================
    ### D- Ensemble predictions
    ### =========================================================================
    ensemble_reg<-nsdm.ensemble(model_names= mod_algo, # models for ensembling
                               species_name=ispi_name,
                               level="reg",
                               scenar_name=scenar_lulc,
                               period_name=per,
                               nesting_name=nesting_method,
                               map_path=paste0(scr_path,"/outputs/",project,"/d14_maps-fut/reg/",nesting_method,"/",scenar_lulc,"/",per),
                               score_path=paste0(scr_path,"/outputs/",project,"/d3_evals/reg/", nesting_method),
                               weighting=do_weighting,
                               weight_metric=weight_metric,
                               discthre=disc_thre)

    # File paths for each combination
    file_paths_maps <- file.path(scr_path, "outputs", project, "d14_maps-fut/reg", nesting_method, scenar_lulc, per, ispi_name)
    file_paths_preds <- file.path(scr_path, "outputs", project, "d13_preds-fut/reg", nesting_method, scenar_lulc, per, ispi_name)

    # Remove intermediate pred and map files
    unlink(file_paths_preds, recursive = TRUE, force = TRUE)
    unlink(file_paths_maps, recursive = TRUE, force = TRUE)

    nsdm.savemap(maps=ensemble_reg$ensemble, species_name=ispi_name, format="tif", model_name=NULL, save_path=paste0(scr_path,"/outputs/",project,"/d15_ensembles-fut/reg/",nesting_method,"/",scenar_lulc,"/",per))
  }
}

# Use mclapply to parallelize the function over scenars_lulc
mclapply(scenars_lulc, process_scenar_lulc, mc.cores = ncores)
