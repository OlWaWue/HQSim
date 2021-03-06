library("R2jags")
library('ggplot2')
library('readxl')
library('writexl')
library('shiny')
library('shinyjs')
library('shinyBS')
library('shinyTime')
library('shinythemes')
library('gridExtra')
library('PerformanceAnalytics')
library('lubridate')
library('DT')
library('scales')
library('kableExtra')
library('rmarkdown')

##
#  --- Define global variables here ---
##

# ---- Labels for selectInput ---------

GLOB_PATHOGENS <- c("MRSA"=1, 
                    "Unidentified"=2, 
                    "Mixed infection"=3)

GLOB_RECOMMENDATIONS <- c("Continue on this dose"=1, 
                          "Adapt Dosing Strategy"=2)

GLOB_ADAPT_FOR <- c("Cmin in therapeutic range"=1)

GLOB_ADAPT_WHAT <- c("Dose"=1, 
                     "Interdose Interval"=2,
                     "All of those"=4)

# ---- color scheme and plot theme ---

main_plot_col <- "#E95420"

limit_plot_col <-"#990000"
text_plot_col <- "grey20"
cont_plot_col <- "lightgrey"
backg_plot_col <-"white"
line_plot_col <- "gray"
plot_grid_col <- "gray"


plot_theme <- theme(axis.text.x = element_text(colour=text_plot_col,size=12,angle=0,hjust=.5,vjust=.5,face="plain"),
                    axis.text.y = element_text(colour=text_plot_col,size=12,angle=0,hjust=1,vjust=0,face="plain"),  
                    axis.title.x = element_text(colour=text_plot_col,size=14,angle=0,hjust=.5,vjust=0,face="bold"),
                    axis.title.y = element_text(colour=text_plot_col,size=14,angle=90,hjust=0.5,vjust=2,face="bold"), 
                    legend.position = "bottom", legend.justification = c(0,1), legend.text=element_text(size=13),
                    panel.background = element_rect(fill = backg_plot_col, colour = cont_plot_col), panel.border = element_blank(), panel.grid.major = element_line(colour = plot_grid_col, linetype = 2),
                    panel.grid.minor = element_line(colour = plot_grid_col, linetype = 2), axis.line = element_line(colour = line_plot_col))

# ---- Parameters for popPK Model

THETAS = c(0.765,  ## THETA1 -  ka (1/h)
           605, ## THETA2 - volume of central compartment (L)
           9.89, ## THETA3 - Clearance
           0.746,  ## THETA4 - oral bioavailability
           0.445,  ## THETA5 - t_lag
           1070)  ## THETA6 - additional Volume of distribution under MTX (L)

PARAMS = c(0)     ## MTX yes or no

OMEGAS = c(sqrt(0.94),       # Omega  - ka
           sqrt(0.25),       # Omega  - VD
           sqrt(0.127))      # Omega  - Cl

SIGMA = c(sqrt(0.044) , sqrt(365))  # Sigma 

##
 # ---- End definition of global variables
##

##
#  ---- Begin Definition of global available functions
##

# ---- Analytical solution of 2cmt model with zero order infusion 


pk_2cmt_infusion <- function(theta, CLCR, WT, DIAL, eta, dosing_events, times){
  
  dosing_time <- dosing_events[,1]
  amt <- dosing_events[,2]
  t_inf <- dosing_events[,3]
  
  
  
  
  
  
  
  IPRED <- vector()
  
  ## Individuelle parameter ebenfalls in vektoren überführen
  for(x in 1:length(times)){
    
    Cl <- theta[1]*( (CLCR[x]/120)^theta[5]) * (theta[6]^DIAL[x])*exp(eta[1])
    V1 <- theta[2]*(WT[x]/70) * (theta[7]^DIAL[x])*exp(eta[2])
    V2 <- theta[3] * exp(eta[3])
    Q <- theta[4]
    
    k=Cl/V1
    k12 = Q/V1
    k21 = Q/V2
    
    
    beta = 0.5 * (k12 + k21 + k - sqrt((k12 + k21 + k)^2 - 4 * k21 * k))
    
    alpha = (k21 * k) / beta
    
    A = 1/V1 *(alpha-k21)/(alpha-beta)
    B = 1/V1 *(beta-k21)/(beta-alpha)
    
    t=times[x]
    if(t==0) {
      temp_ipred =0
    } else{     
      
      
      
      doses_prior_to_t <- NULL
      
      for(i in 1:length(dosing_time)){
        if (dosing_time[i]<t){
          doses_prior_to_t <- c(doses_prior_to_t, i)
        }
        
      }
      
      
      temp_delta_td <- dosing_time[length(doses_prior_to_t)]
      
      temp_delta_tinf <- t_inf[length(doses_prior_to_t)]
      
      temp_amt <- amt[length(doses_prior_to_t)]
      
      
      Di <- amt[doses_prior_to_t] 
      Di <- Di[-length(amt[doses_prior_to_t])]
      
      # Di = amt[dosing_time<t][-length(amt[dosing_time<t])]
      
      temp_delta_tdi <- dosing_time[doses_prior_to_t]
      temp_delta_tdi <- temp_delta_tdi[-length(temp_delta_tdi)]
      
      
      tinf_i <- t_inf[doses_prior_to_t]
      tinf_i <- tinf_i[-length(amt[doses_prior_to_t])]
      
      
      temp_ipred <- ifelse((t-temp_delta_td)<=temp_delta_tinf,
                           sum( ( Di/tinf_i *(A/alpha * (1-exp(-alpha*tinf_i )) * exp(-alpha*(t-temp_delta_tdi-tinf_i ) ) + B/beta  * (1-exp(-beta*tinf_i ))  * exp(-beta*(t-temp_delta_tdi-tinf_i ) )) ) ) + ( temp_amt /temp_delta_tinf * (A/alpha * (1-exp(-alpha*(t-temp_delta_td))) + B/beta * (1-exp(-beta*(t-temp_delta_td))))),
                           sum( amt[dosing_time<t]/t_inf[dosing_time<t] * (A/alpha * (1-exp(-alpha*t_inf[dosing_time<t])) * exp(-alpha*(t-dosing_time[dosing_time<t]-t_inf[dosing_time<t])) + B/beta * (1-exp(-beta*t_inf[dosing_time<t]))  * exp(-beta*(t-dosing_time[dosing_time<t]-t_inf[dosing_time<t]))) )
      )  
    }
    IPRED[x] <- temp_ipred
  }
  
  dat <- data.frame(times=times, IPRED=IPRED, CL_i=Cl, Vc_i=V1, Vp_i=V2, Q_i=Q, CLCR=CLCR, WT=WT, DIAL=DIAL)
  
  return(dat)
}


pk_2cmt_infusion_dep <- function(theta, params, eta, dosing_events, times){
  

  
  dosing_time <- dosing_events[,1]
  amt <- dosing_events[,2]
  t_inf <- dosing_events[,3]
  
  WT <- params[1]
  CrCL <- params[2]
  DIAL <- params[3]
  
  
  Cl <- theta[1]*( (CrCL/120)^theta[5]) * (theta[6]^DIAL)*exp(eta[1])
  V1 <- theta[2]*(WT/70) * (theta[7]^DIAL)*exp(eta[2])
  V2 <- theta[3] * exp(eta[3])
  Q <- theta[4]
  
  k=Cl/V1
  k12 = Q/V1
  k21 = Q/V2
  
  
  beta = 0.5 * (k12 + k21 + k - sqrt((k12 + k21 + k)^2 - 4 * k21 * k))
  
  alpha = (k21 * k) / beta
  
  A = 1/V1 *(alpha-k21)/(alpha-beta)
  B = 1/V1 *(beta-k21)/(beta-alpha)
  
  IPRED <- vector()
  
  for(x in 1:length(times)){
    
    t=times[x]
    if(t==0) {
      temp_ipred =0
    } else{     
      
      
      
      doses_prior_to_t <- NULL
      
      for(i in 1:length(dosing_time)){
        if (dosing_time[i]<t){
          doses_prior_to_t <- c(doses_prior_to_t, i)
        }
        
      }
      
      
      temp_delta_td <- dosing_time[length(doses_prior_to_t)]
      
      temp_delta_tinf <- t_inf[length(doses_prior_to_t)]
      
      temp_amt <- amt[length(doses_prior_to_t)]
      
      
      Di <- amt[doses_prior_to_t] 
      Di <- Di[-length(amt[doses_prior_to_t])]
      
      # Di = amt[dosing_time<t][-length(amt[dosing_time<t])]
      
      temp_delta_tdi <- dosing_time[doses_prior_to_t]
      temp_delta_tdi <- temp_delta_tdi[-length(temp_delta_tdi)]
      
      
      tinf_i <- t_inf[doses_prior_to_t]
      tinf_i <- tinf_i[-length(amt[doses_prior_to_t])]
      
      
      temp_ipred <- ifelse((t-temp_delta_td)<=temp_delta_tinf,
                           sum( ( Di/tinf_i *(A/alpha * (1-exp(-alpha*tinf_i )) * exp(-alpha*(t-temp_delta_tdi-tinf_i ) ) + B/beta  * (1-exp(-beta*tinf_i ))  * exp(-beta*(t-temp_delta_tdi-tinf_i ) )) ) ) + ( temp_amt /temp_delta_tinf * (A/alpha * (1-exp(-alpha*(t-temp_delta_td))) + B/beta * (1-exp(-beta*(t-temp_delta_td))))),
                           sum( amt[dosing_time<t]/t_inf[dosing_time<t] * (A/alpha * (1-exp(-alpha*t_inf[dosing_time<t])) * exp(-alpha*(t-dosing_time[dosing_time<t]-t_inf[dosing_time<t])) + B/beta * (1-exp(-beta*t_inf[dosing_time<t]))  * exp(-beta*(t-dosing_time[dosing_time<t]-t_inf[dosing_time<t]))) )
      )  
    }
    IPRED[x] <- temp_ipred
  }
  
  dat <- data.frame(times=times, IPRED=IPRED, CL_i=Cl, Vc_i=V1, Vp_i=V2, Q_i=Q)
  
  return(dat)
}

### PK Model oral 1cmt with lag time
pk_1cmt_oral <- function(theta, params, eta, dosing_events, times){
  
  dosing_time <- dosing_events[,1]
  amt <- dosing_events[,2]*0.775 ## Convert Sulfate to free base
  
  has_mtx <- params[1]
  
  Cl <- theta[3]*exp(eta[3])
  Vd <- (theta[2]+(theta[6]*has_mtx))*exp(eta[2])
  ka <- theta[1]*exp(eta[1])
  F_oral <- theta[4]
  t_lag <- theta[5]
  
  k <- Cl/Vd
  
  IPRED <- vector()
  
  for(t in 1:length(times)){
    temp_conc <- c(nrow = length(amt))
    for(i in 1:length(amt)) {
      
      temp_conc[i] <- ifelse((times[t]-dosing_time[i]) < t_lag, 0, F_oral*amt[i]*ka/(Vd*(ka-k))*(exp(-k*(times[t]-dosing_time[i]-t_lag))-exp(-ka*(times[t]-dosing_time[i]-t_lag))))
      
    }
    IPRED[t] <- sum(temp_conc) * 1000
  }
  

  
  dat <- data.frame(times=times, IPRED=IPRED, CL_i=Cl, Vc_i=Vd, Ka_i=ka, MTX=has_mtx)
  
  return(dat)
}

# ---- Process a NONMEM like dataset and perform mcmc 

process_data_set <- function(pk_data = data.frame(time=c(0,4,6,12,30,50),
                                                  amt=c(100,".",".",100,".","."),
                                                  conc=c(".", 2, 3, ".", 1.5, 0.72),
                                                  evid=c(1, 0, 0, 1, 0, 0)),
                             n.burn=100, n.iter=2600, n.thin = 10, n.chain=4,
                             thetas  = THETAS,
                             omegas = OMEGAS,
                             covariates,
                             TIME = seq(0, 72, by=0.1), SIGMAS= SIGMA, time_reference) {
  
  
  
  # --- inner function to generate individual PK plot data
  
  do_plot <- function(jags_result, time_reference){
    

    df <- data.frame(eta1=jags_result$BUGSoutput$sims.list$eta1,
                     eta2=jags_result$BUGSoutput$sims.list$eta2,
                     eta3=jags_result$BUGSoutput$sims.list$eta3)
    
    
    ## remove burnin iterations

    
    mcmc_se <- list()
    
    mcmc_ind_pars <- data.frame()
    
    ## Simulate with the etas obtained by sampling from the posterior distribution
    
    withProgress(message = "Processing MCMC results", max = nrow(df), {
      for (i in 1:nrow(df)) {
        
          
          temp_dat <- pk_1cmt_oral(theta = thetas,
                                       params=c(covariates$MTX[1]),
                                       eta = c(df$eta1[i], df$eta2[i], df$eta3[i]),
                                       dosing_events = dosing_events,
                                       times=TIME)
          mcmc_se[[i]] <- temp_dat$IPRED
        
          mcmc_ind_pars <- rbind(mcmc_ind_pars, c(ka=temp_dat$Ka_i[1],V1=temp_dat$Vc_i[1],CL=temp_dat$CL_i[1]))
          
        incProgress(1)
      }
    })
    
    

    colnames(mcmc_ind_pars) <- c("ka", "V", "Cl")
    
    
    df_temp <- NULL
    
    withProgress(message = "Calculating Prediction interval", max = nrow(df), {
      ## bind simulations in a data.frame
      for (k in 1:nrow(df)) {
        df_temp <- rbind(df_temp, mcmc_se[[k]])
        incProgress(1)
      }
    })
    
    ## Generate Quantils
    s <- apply(df_temp,2,function(x) quantile(x,probs=c(0.025, 0.05, 0.075, 0.10, 0.9, 0.925, 0.95, 0.975, 0.5)))
    
    ## Combine individual PK data and quantils in a data.frame
    pk_data <- data.frame(time=TIME,
                          s1=s[1,],s2=s[8,], 
                          s3=s[2,],s4=s[7,],
                          s5=s[3,],s6=s[6,],
                          s7=s[4,],s8=s[5,],
                          max=s[9,]) # median 
    
    # write.csv(pk_data, "temp.csv", row.names = F)
    
    ## Get the last simulated concentration for the boxplot
    c_at_tlast <- df_temp[,ncol(df_temp)]
    
    ## carry on max value in PK plot for adjusting y-axis
    ind_y_max <- max(pk_data$s2)
    
    ind_y_min <- min(pk_data$s1[pk_data$s1>0])
    
    return(list(pk_data,             #1
                c_at_tlast,    #2
                ind_y_max,     #3
                ind_y_min,     #4
                mcmc_ind_pars  #5
                ))
  }
  
  # --- Generate MCMC trace plots and distributions for every eta estimated 
  
  mcmc_diagnosticplots <- function(jags_result,  omega, colour="red") {
    
    df <- data.frame(eta1=jags_result$BUGSoutput$sims.list$eta1,
                     eta2=jags_result$BUGSoutput$sims.list$eta2,
                     eta3=jags_result$BUGSoutput$sims.list$eta3)
    
    nb.etas <- ncol(df) 
    
    niter <- nrow(df)
    
    df$iteration <- (1:niter) 
    
    
    
    ## I will never again understand this...
    
    
    ## Problems that COULD happen: never refer aesthetics to columns via df[,n.et]
    ## Do not pass data to ggplot, but to the geom layer => problems with additional
    ## layers that are supposed to use fixed values like geom_vline
    plot_list <- list()
    
    for(n.et in 1:nb.etas) {
      
      dens_post <- density(df[,n.et], adjust=2)
      max_eta <- dens_post$x[which.max(dens_post$y)]
      
      dens_post <- data.frame(ETA=dens_post$x, freq=dens_post$y, max_eta=max_eta)
      x_this_eta <- seq(min(dens_post$ETA), max(dens_post$ETA), length.out = 512)
      
      dens_prior <- dnorm(x=x_this_eta, mean=0, sd=sqrt(omega[n.et]))
      dens_prior <- data.frame(ETA=x_this_eta, freq=dens_prior)
      
      current_data <- data.frame(iteration=1:niter,eta=df[,n.et])
      
      y_name <- paste("ETA", n.et)
      
      
      ## trace plot for this eta in this chain
      
      plot_list[[paste("p_iter_ETA", n.et, sep="")]] <- ggplot(data=current_data) + 
        geom_line(aes(x=iteration,y=eta), colour=colour)+ 
        ylim(min(x_this_eta),
             max(x_this_eta)) +
        theme_bw() + ylab(y_name) + xlab("Number of MCMC samples")
      
      
      ## 90° flipped density plot for this eta in this chain
      plot_list[[paste("p_dens_ETA", n.et, sep="")]] <- ggplot(data = dens_post) +
        geom_vline(aes(xintercept=max_eta), colour="red", linetype=2) +
        geom_line(aes(x=ETA, y=freq), colour="red") + 
        geom_line(data=dens_prior, aes(x=ETA,y=freq), colour = "blue") + 
        coord_flip() + 
        xlim(min(x_this_eta),
             max(x_this_eta))+
        annotate(geom="text", 
                 y=max(dens_post$freq)+0.2, 
                 x=max_eta, 
                 label="posterior", colour="red") +
        annotate(geom="text", y=max(dens_prior$freq)+0.2, x=0, label="prior", colour="blue") +
        ylim(0,2)+ ylab(paste("Density of", y_name)) +
        theme_bw() + theme(axis.title.y = element_blank()) 
      
      
    }
    
    df <- df[,-ncol(df)]
    
    plot_list[["chain_data"]] <- df
    
    
    
    return(plot_list)
  }
  
  
  
  ### separate dosing events ...
  dosing_events <- data.frame(time=as.numeric(as.character(pk_data[pk_data$evid==1,]$time)),
                              amt=as.numeric(as.character(pk_data[pk_data$evid==1,]$amt)))
  
  
  ### ... and TDM events
  tdm_data <- data.frame(conc=as.numeric(as.character(pk_data[pk_data$evid==0,]$conc)),
                         time=as.numeric(as.character(pk_data[pk_data$evid==0,]$time)))
  
  
  ### Use JAGS model to sample from posterior distribution
  ### According to the selected model

  #### ---- Compile and run JAGS model
  
  ### tdm_times muss ein Index in time werden!
  
  temp_times <- NULL
  for(i in 1:length(tdm_data$time)){
    temp_times <- c(temp_times, which(TIME == tdm_data$time[i]))
  }
  
  

  jagsfit <- jags(data = list('c' = tdm_data$conc,
                              'amt' = dosing_events$amt, 
                              'dosing_time' = dosing_events$time,
                              'MTX'=covariates$MTX[1],  ## Covariate is not variable!!
                              'tdm_times'= temp_times,
                              'times' =TIME,
                              "theta"=thetas,
                              "omega"=omegas,
                              'sigma'=SIGMAS ),
                  working.directory = NULL,
                  inits = NULL,
                  parameters.to.save = c('eta1', 'eta2', 'eta3'),
                  model.file = "Carmichael_et_al.bug",
                  n.chains = n.chain,
                  n.thin = n.thin,
                  n.iter = n.iter,
                  n.burnin = n.burn)
  
  
  
  # ---- Derive PK plot data from the mcmc samples using the inner function
  
  pk_profile <- (do_plot(jagsfit, time_reference=time_reference))
  
  # ---- Create Diagnostic plots from mcmc data
  
  mcmc_plots_1 <- mcmc_diagnosticplots(jagsfit, omega=omegas, "red")
  
  df <- data.frame(eta1=jagsfit$BUGSoutput$sims.list$eta1,
                   eta2=jagsfit$BUGSoutput$sims.list$eta2,
                   eta3=jagsfit$BUGSoutput$sims.list$eta3)
  
  
  
  result = list(mcmc_plots_1, 
                NULL, 
                NULL, 
                NULL,
                pk_profile=pk_profile[[1]], 
                c_at_tlast=pk_profile[[2]], 
                ind_y_max=pk_profile[[3]], 
                ind_y_min=pk_profile[[4]], 
                mcmc_etas = df,
                mcmc_ind_pars=pk_profile[[5]])
  
  return(result)
}


# --- GLOBAL function for the MC simulation

perform_mc_simulation <- function(n.mc, omegas, thetas, data_set, covariates, times) {
  
  # Take random n.mc random samples for the eta values using the standard deviation from the popPK model

  mc_eta2 <- (rnorm(n = n.mc, mean=0, sd=(omegas[2])))
  mc_eta3 <- (rnorm(n = n.mc, mean=0, sd=(omegas[3])))
  mc_eta1 <- (rnorm(n = n.mc, mean=0, sd=(omegas[1])))
    
  ## summarize etas in a data.frame
  
  all_etas <- data.frame(eta1=mc_eta1, eta2=mc_eta2, eta3=mc_eta3)
  
  
  dat_mc <- NULL
  
  mc_se <- list()

  mc_ind_pars <- data.frame()
  
  ## Get 
  
  d_set <- data_set

  dosing_events <- data.frame(time=as.numeric(as.character(d_set[d_set$evid==1,]$time)),
                              amt=as.numeric(as.character(d_set[d_set$evid==1,]$amt)))
  
  ## Do with progress
  withProgress(message = "Performing Monte Carlo simulation", max = n.mc, {
    for(i in 1:n.mc){
      ### Simulate population PK profiles for every monte carlo sample according to the PK model currently
      ### Selected
      temp_dat <- pk_1cmt_oral(theta = thetas,
                                   params=c(covariates$MTX[1]),
                                   eta = c(all_etas$eta1[i], all_etas$eta2[i], all_etas$eta3[i]),
                                   dosing_events = dosing_events,
                                   times=times)
      
  
      
      mc_se[[i]] <- temp_dat$IPRED


      mc_ind_pars <- rbind(mc_ind_pars, c(CL=temp_dat$Ka_i[1],V1=temp_dat$Vc_i[1],V2=temp_dat$CL_i[1]))
      
      dat_mc <- cbind(dat_mc, mc_se[[i]])
      incProgress(1)
    }
  })

  
  colnames(mc_ind_pars) <- c("ka", "V", "Cl")
  
  
  ## transpose data -> rows into columns
  dat_mc <- t(dat_mc)
  
  ## Get quantile from monte carlo result
  s <- apply(dat_mc,2,function(x) quantile(x,probs=c(0.025,0.5,0.975)))
  
  ## Data for population PK Plot
  plot_dat <- data.frame(TIME=times,CP_min=s[1,],CP=s[2,],CP_max=s[3,], DELTA=(s[3,]-s[1,]))
  return(list(plot_dat,      # 1
              dat_mc,        # 2
              all_etas,      # 3
              mc_ind_pars))  # 4
}
