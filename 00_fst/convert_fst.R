# Project name
project<-gsub("/main","",gsub(".*scripts/","",getwd()))

# Set permissions for new files
Sys.umask(mode="000")

# Load and retrieve main settings
settings<-read.csv2("./settings/settings.csv")
parameters<-settings$parameter
values<-settings$value
for(i in 1:length(parameters)){
if(grepl(pattern="NULL", values[i])){
do.call("<-",list(parameters[i], NULL))
} else {
if(grepl(pattern=paste0(c("c\\('|paste", ":20"), collapse="|"), values[i])){
do.call("<-",list(parameters[i], eval(parse(text=values[i]))))
} else {
 if(is.na(as.numeric(values[i]))) {
do.call("<-",list(parameters[i], values[i]))
 } else {
do.call("<-",list(parameters[i], as.numeric(values[i])))
}
}
}
}

# Additional settings
ssl_id<-readLines(paste0(w_path,"tmp/",project,"/settings/tmp/ssl_id.txt"))
cov_path<-paste0(w_path,"data/",project,"/covariates/")
spe_glo<-list.files(paste0(w_path,"data/",project,"/species/glo"), full.names=T, pattern=".rds")
if(n_levels>1) spe_reg<-list.files(paste0(w_path,"data/",project,"/species/reg"), full.names=T, pattern=".rds")
param_grid<-paste0(w_path,"scripts/",project,"/main/settings/", param_grid)
if(length(expert_table)>0) expert_table<-paste0(w_path,"scripts/",project,"/main/settings/", expert_table)
if(length(forced_species)>0) forced_species<-paste0(w_path,"scripts/",project,"/main/settings/", forced_species)

# Check and refine masks
if(n_levels>1) mask_reg<-paste0(w_path,"data/",project,"/masks/", mask_reg)
if(length(mask_pred)>0) mask_pred<-paste0(w_path,"data/",project,"/masks/", mask_pred)

# Save settings
rm(settings, parameters, values, i)
save.image(paste0(w_path,"tmp/",project,"/settings/nsdm-settings.RData"))

print(paste0("N-SDM settings defined"))

### =========================================================================
### B- Prepare covariate data
### =========================================================================
# Set lib path
.libPaths(lib_path)

# Load nsdm package
require(nsdm)
library(pbmcapply)

rds_f=rev(readLines("/cluster/work/eawag/p01002/nsdm/scripts/nsdm-project/main/main.txt"))

result <- pbmclapply(rds_f, function(x){
    fst_f <- sub("\\.rds$", ".fst", x)
    
    if (file.exists(fst_f)) {
        message(paste("File already exists:", fst_f))
        return(NULL)
    } else {
        message(paste("Creating file:", fst_f))
        # If fst file does not exist, create it
        r <- readRDS(x)
        r_df <- if (!is.data.frame(r)) as.data.frame(r) else r  # Convert to data frame only if necessary
        write.fst(r_df, fst_f, compress = 75)
    }
}, mc.cores = 10)
