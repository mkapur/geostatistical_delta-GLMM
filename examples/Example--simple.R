
# setwd("C:/Users/James.Thorson/Desktop/Project_git/geostatistical_delta-GLMM/examples/")

# Install TMB
# Must be installed from: https://github.com/kaskr/adcomp

# Install INLA
# Must be installed from: http://www.r-inla.org/download

# Install geostatistical delta-GLMM package
devtools::install_github("nwfsc-assess/geostatistical_delta-GLMM") # This is the developement version.  Please check GitHub for the latest release number.
devtools::install_github("james-thorson/utilities") # This is the developement version.  Please check GitHub for the latest release number.

# Load libraries
library(TMB)
library(INLA)
library(SpatialDeltaGLMM)
library(ThorsonUtilities)

# This is where all runs will be located
DateFile = paste(getwd(),'/',Sys.Date(),'/',sep='')
  dir.create(DateFile)

###############
# Settings
###############

  Data_Set = c("WCGBTS_canary_rockfish", "EBS_pollock", "GOA_Pcod", "Sim")[3]
  Sim_Settings = list("Species_Set"=1:100, "Nyears"=10, "Nsamp_per_year"=600, "Depth_km"=-1, "Depth_km2"=-1, "Dist_sqrtkm"=0, "SigmaO1"=0.5, "SigmaO2"=0.5, "SigmaE1"=0.5, "SigmaE2"=0.5, "SigmaVY1"=0.05, "Sigma_VY2"=0.05, "Range1"=1000, "Range2"=500, "SigmaM"=1)
  Version = "geo_index_v3g"
  n_x = c(250, 500, 1000, 2000)[2] # Number of stations
  FieldConfig = c("Omega1"=1, "Epsilon1"=1, "Omega2"=1, "Epsilon2"=1) # 1=Presence-absence; 2=Density given presence
  CovConfig = c("SST"=0, "RandomNoise"=0) # DON'T USE DURING REAL-WORLD DATA FOR ALL SPECIES (IT IS UNSTABLE FOR SOME)
  Q_Config = c("Pass"=0)
  VesselConfig = c("Vessel"=0, "VesselYear"=0)
  ObsModel = 2  # 0=normal (log-link); 1=lognormal; 2=gamma; 4=ZANB; 5=ZINB; 11=lognormal-mixture; 12=gamma-mixture
  Kmeans_Config = list( "randomseed"=1, "nstart"=100, "iter.max"=1e3 )     # Samples: Do K-means on trawl locs; Domain: Do K-means on extrapolation grid

# Save options for future records
  Record = bundlelist( c("Data_Set","Sim_Settings","Version","n_x","FieldConfig","CovConfig","Q_Config","VesselConfig","ObsModel","Kmeans_Config") )
  capture.output( Record, file=paste0(DateFile,"Record.txt"))
                                                   
# Decide on strata for use when calculating indices
  # In this case, it will calculate a coastwide index, and also a separate index for each state (although the state lines are approximate)
if( Data_Set %in% c("WCGBTS_canary_rockfish","Sim")){
  strata.limits <- data.frame(matrix(ncol=5, byrow=TRUE, dimnames=list(NULL, c("STRATA","NLat","SLat","MinDepth","MaxDepth")), c(
    NA,        49.0, 32.0,  55,       1280,
    NA,        42.0, 32.0,  55,       1280,
    NA,        46.0, 42.0,  55,       1280,
    NA,        49.0, 46.0,  55,       1280
  )))
  strata.limits[,'STRATA'] = c("Coastwide","CA","OR","WA")
}
if( Data_Set %in% c("EBS_pollock","GOA_Pcod)){
  strata.limits <- data.frame(matrix(ncol=5, byrow=TRUE, dimnames=list(NULL, c("STRATA","NLat","SLat","MinDepth","MaxDepth")), c(
    NA,        Inf, -Inf,  -Inf,       Inf
  )))
  strata.limits[,'STRATA'] = c("All_areas")
}

# Compile TMB software
  #TmbDir = system.file("executables", package="SpatialDeltaGLMM")
  TmbDir = "C:/Users/James.Thorson/Desktop/Project_git/geostatistical_delta-GLMM/inst/executables/"
  setwd( TmbDir )
  compile( paste(Version,".cpp",sep="") )
      

################
# Prepare data
# (THIS WILL VARY FOR DIFFERENT DATA SETS) 
################

# Get extrapolation data
  if( Data_Set %in% c("WCGBTS_canary_rockfish", "Sim")){
    Return = Prepare_WCGBTS_Extrapolation_Data_Fn( strata.limits=strata.limits )
    Data_Extrap = Return[["Data_Extrap"]]
    a_el = Return[["a_el"]]
  }
  if( Data_Set %in% c("EBS_pollock")){
    Return = Prepare_EBS_Extrapolation_Data_Fn( strata.limits=strata.limits )
    Data_Extrap = Return[["Data_Extrap"]]
    a_el = Return[["a_el"]]
  }
  if( Data_Set %in% c("GOA_Pcod")){
    Return = Prepare_GOA_Extrapolation_Data_Fn( strata.limits=strata.limits )
    Data_Extrap = Return[["Data_Extrap"]]
    a_el = Return[["a_el"]]
  }

# Read or simulate trawl data
  if(Data_Set=="WCGBTS_canary_rockfish"){
    data( WCGBTS_Canary_example )
    Data_Geostat = data.frame( "Catch_KG"=WCGBTS_Canary_example[,'HAUL_WT_KG'], "Year"=as.numeric(sapply(WCGBTS_Canary_example[,'PROJECT_CYCLE'],FUN=function(Char){strsplit(as.character(Char)," ")[[1]][2]})), "Vessel"=WCGBTS_Canary_example[,"VESSEL"], "AreaSwept_km2"=WCGBTS_Canary_example[,"AREA_SWEPT_HA"]/1e2, "Lat"=WCGBTS_Canary_example[,'BEST_LAT_DD'], "Lon"=WCGBTS_Canary_example[,'BEST_LON_DD'], "Pass"=WCGBTS_Canary_example[,'PASS']-1.5)
  }
  if(Data_Set=="EBS_pollock"){
    data( EBS_pollock_data )
    Data_Geostat = data.frame( "Catch_KG"=EBS_pollock_data[,'catch'], "Year"=EBS_pollock_data[,'year'], "Vessel"="missing", "AreaSwept_km2"=0.01, "Lat"=EBS_pollock_data[,'lat'], "Lon"=EBS_pollock_data[,'long'], "Pass"=0)
  }
  if(Data_Set=="GOA_Pcod"){
    data( GOA_pacific_cod )
    Data_Geostat = data.frame( "Catch_KG"=GOA_pacific_cod[,'catch'], "Year"=GOA_pacific_cod[,'year'], "Vessel"="missing", "AreaSwept_km2"=0.01, "Lat"=GOA_pacific_cod[,'lat'], "Lon"=GOA_pacific_cod[,'long'], "Pass"=0)
  }
  if(Data_Set=="Sim"){ #names(Sim_Settings)
    Sim_DataSet = Geostat_Sim(Sim_Settings=Sim_Settings, MakePlot=TRUE)
    Data_Geostat = Sim_DataSet[['Data_Geostat']]
    True_Index = Sim_DataSet[['True_Index']]
  }
  Year_Set = sort(unique(Data_Geostat[,'Year']))

# Convert to an Eastings-Northings coordinate system
  tmpUTM = Convert_LL_to_UTM_Fn( Lon=Data_Geostat[,'Lon'], Lat=Data_Geostat[,'Lat'] )                                                         #$
  Data_Geostat = cbind( Data_Geostat, 'E_km'=tmpUTM[,'X'], 'N_km'=tmpUTM[,'Y'])

# Calculate k-means centroids (but only once for all species)
  Kmeans = Calc_Kmeans(n_x=n_x, loc_orig=Data_Geostat[,c("E_km", "N_km")], randomseed=Kmeans_Config[["randomseed"]], nstart=Kmeans_Config[["nstart"]], iter.max=Kmeans_Config[["iter.max"]], DirPath=DateFile)
  loc_x = Kmeans$centers
  Data_Geostat = cbind( Data_Geostat, "knot_i"=Kmeans$cluster )

# Calc design matrix and areas
  PolygonList = Calc_Polygon_Areas_and_Polygons_Fn( loc_x=loc_x, Data_Extrap=Data_Extrap, Covariates=c("none"), a_el=a_el)
  X_xj = PolygonList[["X_xj"]]
  a_xl = PolygonList[["a_xl"]]
  NN_Extrap = PolygonList[["NN_Extrap"]]

# Make catchability matrix (Q_i)
  if( sum(Q_Config)==0 ){
    Q_ik = matrix(0, ncol=1, nrow=nrow(Data_Geostat))
  }else{
    Q_ik = as.matrix(Data_Geostat[,names(Q_Config)[which(Q_Config==1)],drop=FALSE])
  }

# Make mesh and info for anisotropy
  MeshList = Calc_Anisotropic_Mesh(loc_x=loc_x)

################
# Make and Run TMB model
# (THIS WILL BE SIMILAR FOR EVERY DATA SET) 
################

  # Make TMB data list
  TmbData = Data_Fn("Version"=Version, "FieldConfig"=FieldConfig, "ObsModel"=ObsModel, "b_i"=Data_Geostat[,'Catch_KG'], "a_i"=Data_Geostat[,'AreaSwept_km2'], "v_i"=as.numeric(Data_Geostat[,'Vessel'])-1, "s_i"=Data_Geostat[,'knot_i']-1, "t_i"=Data_Geostat[,'Year']-min(Data_Geostat[,'Year']), "a_xl"=a_xl, "X_xj"=X_xj, "Q_ik"=Q_ik, "MeshList"=MeshList)

  # Make TMB object
  TmbList = Build_TMB_Fn(TmbData, TmbDir=TmbDir, Version=Version, VesselConfig=VesselConfig)
  Obj = TmbList[["Obj"]]
  
  # Run first time -- marginal likelihood
  Start_time = Sys.time()
  Obj$fn(Obj$par)
  # Run first time -- gradient with respect to fixed effects
  Obj$gr(Obj$par)

  # Run model
  Opt = nlminb(start=Obj$par, objective=Obj$fn, gradient=Obj$gr, lower=TmbList[["Lower"]], upper=TmbList[["Upper"]], control=list(eval.max=1e4, iter.max=1e4, trace=1))  # , rel.tol=1e-20
  Opt[["final_diagnostics"]] = data.frame( "Name"=names(Opt$par), "Lwr"=TmbList[["Lower"]], "Est"=Opt$par, "Upr"=TmbList[["Upper"]], "Gradient"=Obj$gr(Opt$par) )
  Opt[["total_time_to_run"]] = Sys.time() - Start_time
  capture.output( Opt, file=paste0(DateFile,"Opt.txt"))
    
  # Reports
  Report = Obj$report()                                      
  Sdreport = sdreport(Obj)
  
  # Save stuff
  Save = list("Opt"=Opt, "Report"=Report, "Sdreport"=Sdreport, "ParHat"=Obj$env$parList(Opt$par))
  save(Save, file=paste0(DateFile,"Save.RData"))
  capture.output( Opt, file=paste0(DateFile,"Opt.txt"))
  capture.output( Sdreport, file=paste0(DateFile,"Sdreport.txt"))
  file.copy( from=paste0(system.file("executables", package="SpatialDeltaGLMM"),"/",Version,".cpp"), to=paste0(DateFile,Version,".cpp"), overwrite=TRUE)
  
################
# Make diagnostic plots
################

  # Plot Anisotropy  
  if( TmbData$Options_vec['Aniso']==1 ){
    PlotAniso_Fn( FileName=paste0(DateFile,"Aniso.png"), Report=Report )
  }

  # Plot surface
  Dim = c("Nrow"=ceiling(sqrt(length(Year_Set)))); Dim = c(Dim,"Ncol"=ceiling(length(Year_Set)/Dim['Nrow']))
  par( mfrow=Dim )
  if(Data_Set %in% c("WCGBTS_canary_rockfish","Sim")){
    PlotDF = cbind( Data_Extrap[,c('Lat','Lon')], 'x2i'=NN_Extrap$nn.idx, 'Include'=which(Data_Extrap[,'propInWCGBTS']>0))
    Map = list("state",c("Oregon","Washington","California"))
    Xlim=c(-126,-117); Ylim=c(32,49)
    MapSizeRatio = c("Height(in)"=4,"Width(in)"=1.55)
    Rotate = 20
  }
  if(Data_Set=="EBS_pollock"){
    PlotDF = cbind( Data_Extrap[,c('Lat','Lon')], 'x2i'=NN_Extrap$nn.idx, 'Include'=(Data_Extrap[,'EBS_STRATUM']!=0))
    PlotDF = PlotDF[which(PlotDF[,'Lon']<0),]
    MappingDetails = list("world", NULL)
    Xlim = c(-180,-158); Ylim=c(54,63)
    MapSizeRatio = c("Height(in)"=4,"Width(in)"=5)
    Rotate = 0
  }
  PlotResultsOnMap_Fn(MappingDetails=MappingDetails, Report=Report, PlotDF=PlotDF, MapSizeRatio=MapSizeRatio, Xlim=Xlim, Ylim=Ylim, FileName=paste0(DateFile,"Field_"), Year_Set=Year_Set, Rotate=Rotate, mfrow=Dim, mar=c(0,0,2,0), oma=c(3.5,3.5,0,0))
                                                                                                                           
  # Covariate effect
  PlotCov_Fn(Report=Report, NN_Extrap=NN_Extrap, X_xj=X_xj, FileName=paste0(DateFile,"Cov_"))
  
  # Time series measures
  Timeseries_Fn(Report=Report, Year_Set=Year_Set, FileName=paste0(DateFile,"Summaries.png"))
  
  # Positive catch rate Q-Q plot
  Q = QQ_Fn( TmbData=TmbData, Report=Report, FileName_PP=paste0(DateFile,"Posterior_Predictive.jpg"), FileName_Phist=paste0(DateFile,"Posterior_Predictive-Histogram.jpg"), FileName_QQ=paste0(DateFile,"Q-Q_plot.jpg"), FileName_Qhist=paste0(DateFile,"Q-Q_hist.jpg"))

  # Vessel effects
  Return = Vessel_Fn(TmbData=TmbData, Sdreport=Sdreport, FileName_VYplot=paste0(DateFile,"VY-effect.jpg"))

  # Plot index
  PlotIndex_Fn( DirName=DateFile, TmbData=TmbData, Sdreport=Sdreport, Year_Set=Year_Set, strata.limits=strata.limits )
  