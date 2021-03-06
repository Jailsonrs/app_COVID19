## Aplicativo Shiny - Modelo de Predição de Casos de Coronavírus
## DEST/UFMG - mar/2020

## Código do servidor

## load packages
library(dplyr)
library(tidyr)
library(httr)
library(lubridate)

# Sys.setlocale("LC_TIME", "pt-br")

##############################################################################

## define font to be used later
f1 = list(#family="Courier New, monospace",
          family="Arial", 
          size=10,color="rgb(30,30,30)")

## function to measure how old a file is
minutesSinceLastUpdate = function(fileName) {
  (as.numeric(as.POSIXlt(Sys.time())) -  
     as.numeric(file.info(fileName)$ctime)) / 60
}

## function to format the dates for better plotting
printDate = function(date){
  # paste0(day(date),"/",month(date, lab=T, locale="us"))
  monthsEn=c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")
  paste0(day(date),"/",monthsEn[month(date)])
}

##############################################################################

## DATA SOURCES

## setup data source (Johns Hopkins)- GLOBAL
baseURL = "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series"


## main function to load the data - GLOBAL
loadData = function(fileName, columnName) {
  if(!file.exists(fileName) || 
     minutesSinceLastUpdate(fileName) > 10) {
    data = read.csv(file.path(baseURL, fileName), 
                    check.names=FALSE, stringsAsFactors=FALSE) %>%
      select(-Lat, -Long) %>% 
      pivot_longer(-(1:2), names_to="date", values_to=columnName)%>%
      mutate(
        date=as.Date(date, format="%m/%d/%y"),
        `Province/State`=
          if_else(`Province/State` == "", "<all>", `Province/State`)
      )
    save(data, file=fileName)  
  } else {
    load(file=fileName)
  }
  return(data)
}

allData = 
  loadData("time_series_covid19_confirmed_global.csv", "CumConfirmed") %>%
  inner_join(
    loadData("time_series_covid19_deaths_global.csv", "CumDeaths")) # %>%
  # inner_join(
    # loadData("time_series_covid19_recovered_global.csv","CumRecovered"))

##############################################################################

## setup data source (MSaude/BR)- BRAZIL
# baseURL.BR = "https://raw.githubusercontent.com/belisards/coronabr/master/dados"
# baseURL.BR = "https://covid.saude.gov.br/assets/files/COVID19_"
baseURL.BR = "https://raw.githubusercontent.com/covid19br/covid19br.github.io/master/dados"


## function to load data - BRAZIL
loadData.BR = function(fileName) {
  if(!file.exists(fileName) || 
     minutesSinceLastUpdate(fileName) > 10) {
    data = read.csv(file.path(baseURL.BR, fileName), 
                    check.names=FALSE, stringsAsFactors=FALSE) %>%
      # select(-c(1,3:8,10:11,14)) %>% # remove unwanted columns
      select(-c(1,4,6)) %>%
      as_tibble() %>%
      mutate(date = as.Date(data)
        # date=as.Date(date), # format dates
             # `CumRecovered` = NA
             ) %>% 
      rename(`Province/State` = estado, # rename some variables
             `CumConfirmed` = casos.acumulados,
             `CumDeaths` = obitos.acumulados
             ) %>%
      select(-2)
    
    save(data, file=fileName)  
  } else {
    load(file=fileName)
  }
  return(data)
}

# brData = loadData.BR("corona_brasil.csv")
brData = loadData.BR("EstadosCov19.csv")


##############################################################################

## LOAD PREDICTION RESULTS

## function to return list of countries with available data on github
readfiles.repo <- function(){
  req <- GET("https://api.github.com/repos/thaispaiva/app_COVID19/git/trees/master?recursive=1")
  stop_for_status(req)
  # extract list of files on github
  filelist <- unlist(lapply(content(req)$tree, "[", "path"), use.names = F)
  files <- grep("STpredictions/", filelist, value = TRUE, fixed = TRUE)
  files <- unlist(lapply(strsplit(files,"/"),"[",2))
  files <- grep(".rds",files, value=TRUE)
  return(files)
}

files = readfiles.repo() # get available results
aux = sub('\\_n.rds$', '', sub('\\_d.rds$', '', files))

##############################################
## list of countries for SHORT TERM prediction
countries_STpred = sort(unique(  # country names without space 
  unlist(lapply(strsplit(aux,"_"), function(x) x[1]))))
countries_STpred_orig = gsub("-"," ", countries_STpred) # country names with space (original)

## list of Brazil's states
statesBR_STpred = unique(
  unlist(lapply(strsplit(aux,"_"), function(x) if(x[1]=="Brazil") return(x[2]) )))
statesBR_STpred[is.na(statesBR_STpred)] = "<all>"
statesBR_STpred = sort(statesBR_STpred)

#############################################
## list of countries for LONG TERM prediction
countries_LTpred_orig = countries_STpred_orig

## list of Brazil's states - LONG TERM
statesBR_LTpred = statesBR_STpred

## read RDS files from github repository
githubURL = "https://github.com/thaispaiva/app_COVID19/raw/master/STpredictions"


##############################################################################

#########################
## REACTIVE SERVER CODE

server = function(input, output, session) {
  
  ## add message on startup
  showModal(modalDialog(
    "Caso esteja acessando pelo celular, o aplicativo é melhor visualizado com o aparelho na horizontal.",
    easyClose = T,
    footer = tagList(
      modalButton("Ok")
    )
  ))

  ###################
  ## OBSERVED DATA
  ## load data depending on the country/region selected
  
  data = reactive({
    if(input$country == "Brazil"){ # if selected Brazil
      d = brData %>%
        arrange(`Province/State`, date)
    } else{ # otherwise, filter by selected country
      d = allData %>%
        filter(`Country/Region` == input$country)
    }
    if(input$state != "<all>") {
      d = d %>% 
        filter(`Province/State` == input$state) # filter by selected state
    } else { # otherwise, group by all states
      d = d %>% 
        group_by(date) %>% 
        summarise_at(c("CumConfirmed","CumDeaths"), sum) #,"CumRecovered"), sum)
    }
    d %>% # create new variables
      mutate(
        dateStr = format(date, format="%d/%b"),
        NewConfirmed=CumConfirmed - lag(CumConfirmed, default=0),
        # NewRecovered=CumRecovered - lag(CumRecovered, default=0),
        NewDeaths=CumDeaths - lag(CumDeaths, default=0)
      )
  })
  
  ## OBSERVED DATA
  ## observe if there is any change on the dropdown menu ( -> show states)
  
  observeEvent(input$country, {
    if(input$country == "Brazil"){ # if country is Brazil
      states = brData %>% pull(`Province/State`)
    } else{ # if other countries
      states = allData %>%
        filter(`Country/Region` == input$country) %>% 
        pull(`Province/State`)
    }
    states = c("<all>", sort(unique(states)))
    updateSelectInput(session, "state", choices=states, selected=states[1])
  })
  
  ## setup the list of countries - OBSERVED DATA
  countries = sort(unique(allData$`Country/Region`))
  
  ## start session with Brazil selected
  updateSelectInput(session, "country", choices=countries, 
                    selected="Brazil")
  
  ################
  ## ST prediction
  ##
  ## load (observed) data depending on the country/region selected
  data_pred = reactive({
    if(input$country_STpred == "Brazil"){ # if selected Brazil
      d = brData %>%
        arrange(`Province/State`, date)
    } else{ # otherwise, filter by selected country
      d = allData %>%
        filter(`Country/Region` == input$country_STpred)
    }
    if(input$state_STpred != "<all>") {
      d = d %>% 
        filter(`Province/State` == input$state_STpred) # filter by selected state
    } else { # otherwise, group by all states
      d = d %>% 
        group_by(date) %>% 
        summarise_at(c("CumConfirmed","CumDeaths"), sum) #,"CumRecovered"), sum)
    }
    d %>% # create new variables
      mutate(
        dateStr = format(date, format="%d/%b"),
        NewConfirmed=CumConfirmed - lag(CumConfirmed, default=0),
        # NewRecovered=CumRecovered - lag(CumRecovered, default=0),
        NewDeaths=CumDeaths - lag(CumDeaths, default=0)
      )
  })
  
  ## load ST prediction results depending on the country/region selected
  pred_n = reactive({
    country_name = input$country_STpred
    country_name = gsub(" ","-", country_name) # remove space from country name
    
    metric = ifelse(input$metrics_ST=="Confirmed","n","d") # which results to load
    
    if(country_name=="Brazil"){
      state = input$state_STpred
      if(state != "<all>"){
        if(exists(paste0(country_name,"_",state,"_",metric))){
          pred_n = get(paste0(country_name,"_",state,"_",metric))
        }else{
          pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",state,"_",metric,"e.rds")))
          assign(paste0(country_name,"_",state,"_",metric), pred_n)  # create country_name object
        }
      }else{
        if(exists(paste0(country_name,"_",metric))){
          pred_n = get(paste0(country_name,"_",metric))
        }else{
          pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",metric,".rds")))
          assign(paste0(country_name,"_",metric), pred_n)  # create country_name object
        }
      }
    }else{
      if(exists(paste0(country_name,"_",metric))){
        pred_n = get(paste0(country_name,"_",metric))
      }else{
        pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",metric,".rds")))
        assign(paste0(country_name,"_",metric), pred_n)  # create country_name object
      }
    }
    
    closeAllConnections()
    
    ## select only object 'df_predict' from the list
    pred_n = pred_n$df_predict
    pred_n$date = as.Date(pred_n$date)  # format date
    return(pred_n)
  })
  
  ## ST prediction
  ## observe if there is any change on the dropdown menu ( -> show states)
  observeEvent(input$country_STpred, {
    if(input$country_STpred == "Brazil"){ # if country is Brazil
      states = statesBR_STpred
    } else{ # if other countries
      states = "<all>"
    }
    # states = c("<all>", sort(unique(states)))
    updateSelectInput(session, "state_STpred", choices=states, selected=states[1])
  })
  
  ## setup the list of countries - ST prediction
  updateSelectInput(session, "country_STpred",
                    choices=countries_STpred_orig, selected="Brazil")
  updateSelectInput(session, "state_STpred", 
                    choices=NULL, selected=NULL)
  
  
  ################
  ## LT prediction
  ##
  ## load (observed) data depending on the country/region selected
  data_predLT = reactive({
    if(input$country_LTpred == "Brazil"){ # if selected Brazil
      d = brData %>%
        arrange(`Province/State`, date)
    } else{ # otherwise, filter by selected country
      d = allData %>%
        filter(`Country/Region` == input$country_LTpred)
    }
    if(input$state_LTpred != "<all>") {
      d = d %>% 
        filter(`Province/State` == input$state_LTpred) # filter by selected state
    } else { # otherwise, group by all states
      d = d %>% 
        group_by(date) %>% 
        summarise_at(c("CumConfirmed","CumDeaths"), sum) #,"CumRecovered"), sum)
    }
    d %>% # create new variables
      mutate(
        dateStr = format(date, format="%d/%b"),
        NewConfirmed=CumConfirmed - lag(CumConfirmed, default=0),
        # NewRecovered=CumRecovered - lag(CumRecovered, default=0),
        NewDeaths=CumDeaths - lag(CumDeaths, default=0)
      )
  })
  
  ## load LT prediction results depending on the country/region selected
  predLT_n = reactive({
    country_name = input$country_LTpred
    country_name = gsub(" ","-", country_name) # remove space from country name
    
    if(country_name == "") return(NULL)
    
    metric = ifelse(input$metrics_LT=="Confirmed","n","d") # which results to load
    
    if(country_name=="Brazil"){
      state = input$state_LTpred
      if(state != "<all>"){
        if(exists(paste0(country_name,"_",state,"_",metric))){
          pred_n = get(paste0(country_name,"_",state,"_",metric))
        }else{
          pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",state,"_",metric,"e.rds")))
          assign(paste0(country_name,"_",state,"_",metric), pred_n)  # create country_name object
        }
      }else{
        if(exists(paste0(country_name,"_",metric))){
          pred_n = get(paste0(country_name,"_",metric))
        }else{
          pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",metric,".rds")))
          assign(paste0(country_name,"_",metric), pred_n)  # create country_name object
        }
      }
    }else{
      if(exists(paste0(country_name,"_",metric))){
        pred_n = get(paste0(country_name,"_",metric))
      }else{
        pred_n = readRDS(url(paste0(githubURL,"/",country_name,"_",metric,".rds")))
        assign(paste0(country_name,"_",metric), pred_n)  # create country_name object
      }
    }
    
    closeAllConnections()

    pred_n$lt_predict$date = as.Date(pred_n$lt_predict$date)
    pred_n$df_predict = NULL  # remove df_predict object
    return(pred_n)
  })
  
  ## observe if there is any change on the dropdown menu (show states) - LTpred
  observeEvent(input$country_LTpred, {
    if(input$country_LTpred == "Brazil"){ # if country is Brazil
      states = statesBR_LTpred
    } else{ # if other countries
      states = "<all>"
    }
    # states = c("<all>", sort(unique(states)))
    updateSelectInput(session, "state_LTpred", choices=states, selected=states[1])
  })
  
  ## setup the list of countries - LT prediction
  updateSelectInput(session, "country_LTpred",
                    choices=countries_LTpred_orig, selected="Brazil")
  updateSelectInput(session, "state_LTpred", 
                    choices=NULL, selected=NULL)

  
  #####################################################################
  ## GRAPHS
  
  ################
  ## OBSERVED DATA
  ## plot for observed data (confirmed, deaths, recovered)
  renderPlot_obs = function(varPrefix, legendPrefix, yaxisTitle) {
    ## plotly function for interactive plot
    renderPlotly({
      data = data()
      plt = data %>%
        plot_ly() %>%  # first, make empty plot and setup axis and legend
        plotly::config(displayModeBar=TRUE) %>%
        layout(
          ## add pred dates to the x axis
          xaxis=list(
            title="", tickangle=-90, #type='category',
            # ticktext=as.list(data$dateStr),
            # tickvals=as.list(data$date)),
            tick0=data$dateStr[1],dtick=7*86400000, # add ticks every week
            tickformat="%d/%b"
          ),
          yaxis=list(title=yaxisTitle, type=if_else(input$scale==1,"log","linear"),
                     hoverformat='.0f', hoverinfo="x+y"),
          legend=list(x=0.1,y=0.9,bgcolor='rgba(240,240,240,0.5)'),
          font=f1
        )
      
      ## after, add lines for each metric from input
      for(metric in input$metrics){
        ## portuguese labels for legend
        metric_pt = switch(metric, Deaths="Mortes/Deaths",
                           Recovered="Recuperados/Recovered Cases",
                           Confirmed="Casos Confirmados/Confirmed Cases")
        plt = plt %>%
          add_trace(
            x=~date, y=data[[paste0(varPrefix, metric)]],
            type='scatter', mode='lines+markers', hoverinfo="x+y",
            name= metric_pt,
            marker=list(
              color=switch(metric,Deaths='rgb(200,30,30)', # Recovered='rgb(30,200,30)',
                           Confirmed='rgb(100,140,240)'),
              line=list(color='rgb(8,48,107)', width=1.0)
              # line=list(color=switch(metric,Deaths='rgb(200,30,30)', # Recovered='rgb(30,200,30)',
              #                        Confirmed='rgb(100,140,240)'),
              #           width=1.0)
            )
          )
      }
      plt
    })
  }
  
  ## add title bar with country name - New Cases
  output$plotTitle_daily <- renderUI({
    title = paste0(input$country,ifelse(input$state == "<all>","",paste0(" / ",input$state)))
    div(style='text-align:center; font-size:15px; 
        font-family:"Open Sans",arial,sans-serif; font-weight:bold', 
        "Novos Casos/New Cases - ",title)
  })
  
  ## add title bar with country name - Cumulated Cases
  output$plotTitle_cum <- renderUI({
    title = paste0(input$country,ifelse(input$state == "<all>","",paste0(" / ",input$state)))
    div(style= 'text-align:center; font-size:15px;
        font-family:"Open Sans",arial,sans-serif; font-weight:bold', 
        "Casos Acumulados/Cumulated Cases - ",title)
  })
  
  #########################
  ## plot for ST prediction
  renderPlot_STpred = function(varPrefix, legendPrefix, yaxisTitle, pred_time) {
    ## plotly function for interactive plot
    renderPlotly({
      data = data_pred()
      pred_n = pred_n()
      ## create last date and format dates for prediction
      last_date_n = min(pred_n$date)-1
      pred_dateStr = format(pred_n$date, format="%d/%b")
      
      plt = data %>%
        plot_ly() %>%  # first, make empty plot and setup axis and legend
        # config(displayModeBar=FALSE) %>%
        plotly::config(displayModeBar=TRUE) %>%
        layout(
          ## title of ST pred graph
          title = list(
            text=paste0("Atualizado em/Updated on ",format(last_date_n, format="%d/%m/%Y"),
                        "<br>Em desenvolvimento/Under development"),
            xanchor="left", x=0, font=list(family="Arial",size=12)), # y=1, yanchor="top"),
          xaxis=list(
            title="",
            tickangle=-90, #type='category',
            ## add pred dates to the x axis
            # ticktext=as.list(c(data$dateStr[which(data$date<=last_date_n)][-c(1:30)], 
            # pred_dateStr)),                         # removing 1st 30 days
            # tickvals=as.list(c(data$date[which(data$date<=last_date_n)][-c(1:30)], 
            # pred_n$date)),
            tick0=data$dateStr[31],dtick=7*86400000, # add ticks every week
            tickformat="%d/%b"
          ),
          yaxis=list(title=yaxisTitle, type=if_else(input$scale_STpred==1,"log","linear"),
                     hoverformat='.0f', hoverinfo="x+y"), 
          legend=list(x=0.1, y=0.9,bgcolor='rgba(240,240,240,0.5)'),
          font=f1,
          # add vertical line on last observed day
          shapes=list(type="line", opacity=0.7, line=list(color="grey", width=1),
                      y0=0, y1=1, yref="paper",
                      x0=last_date_n, x1=last_date_n)
        )
      
      # varPrefix = "Cum"; legendPrefix = ""
      # metric = "Confirmed"; 
      metric = input$metrics_ST
      ## portuguese labels for legend
      metric_pt = switch(metric, Deaths="Mortes/Deaths",
                         Recovered="Recuperados/Recovered Cases",
                         Confirmed="Casos Confirmados/Confirmed Cases")
      
      plt = plt %>%
        ## add lines for observed data
        add_trace(
          x=data$date[which(data$date<=last_date_n)][-c(1:30)], # removing 1st 30 days
          y=data[[paste0(varPrefix, metric)]][which(data$date<=last_date_n)][-c(1:30)], 
          type='scatter', mode='lines+markers', hoverinfo="x+y", 
          name=metric_pt,
          marker=list(
            color=switch(metric,Deaths='rgb(200,30,30)', Confirmed='rgb(100,140,240)'),
            line=list(color='rgb(8,48,107)', width=1.0)
            # line=list(color=switch(metric,Deaths='rgb(200,30,30)', Confirmed='rgb(100,140,240)'),
            #           width=1.0)
          )
        ) %>% 
        ## add 2,5% and 97,5% quantiles
        add_trace(
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
              pred_n$date[1:input$pred_time]),
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              pred_n$q25[1:input$pred_time]),
          showlegend=F,
          name=paste("95% IC - ",metric_pt,"CI"),
          type='scatter', #mode = 'none',
          mode='lines', hoverinfo="x+y", 
          fillcolor='rgba(150,150,150,0.5)',
          line=list(color='rgba(0,0,0,1)', width=0) #, dash='dot')
        ) %>%
        add_trace(
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
              pred_n$date[1:input$pred_time]),
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              pred_n$q975[1:input$pred_time]),
          type='scatter', #mode = 'none',
          mode='lines', hoverinfo="x+y", 
          fill='tonexty',
          # showlegend=F,
          name=paste("95% IC - ",metric_pt,"CI"),
          fillcolor='rgba(150,150,150,0.5)',
          line=list(color='rgba(0,0,0,1)', width=0)# , dash='dot')
        ) %>%
        ## add median of prediction
        add_trace(
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
               pred_n$date[1:input$pred_time]),
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              pred_n$med[1:input$pred_time]),
          type='scatter', mode='lines+markers', hoverinfo="x+y", 
          name=paste("Previsão", metric_pt, "Prediction"),
          marker=list(color='rgb(0,0,0)', size=4), line=list(color='rgb(0,0,0)', dash='dot')
        )
      plt
    })
  }
  
  ## add title bar with country name - ST prediction
  output$plotTitle <- renderUI({
    title = paste0(input$country_STpred,
                   ifelse(input$state_STpred == "<all>","",paste0(" / ",input$state_STpred)))
    div(style='text-align:center; font-size:15px;
        font-family:"Open Sans",arial,sans-serif; font-weight:bold', 
        title)
  })
  
  #########################
  ## plot for LT prediction
  renderPlot_LTpred = function(varPrefix, legendPrefix, yaxisTitle) {
    ## plotly function for interactive plot
    renderPlotly({
      data = data_predLT()
      if(nrow(data) == 0) return(NULL) ## DOUGLAS
      # pred_n = predLT_n()
      aux = predLT_n()
      pred_n = aux$lt_predict
      pred_summary = aux$lt_summary
      mu_plot = aux$mu_plot
      flag = aux$flag

      ## create last date and format dates for prediction
      last_date_n = min(pred_n$date)-1
      pred_dateStr = format(pred_n$date, format="%d/%b")
      
      # varPrefix = "New"; legendPrefix = ""
      metric = input$metrics_LT
      metric_leg = switch(metric, Deaths="Deaths", Confirmed="Cases") 
      
      plt = data %>%
        plot_ly() %>%  # first, make empty plot and setup axis and legend
        # config(displayModeBar=FALSE) %>%
        plotly::config(displayModeBar=TRUE ) %>% #, locale='pt-br') %>%
        layout(
          title = list(
            text=paste0("Atualizado em/Updated on ",format(last_date_n, format="%d/%m/%Y"),
                        "<br>Em desenvolvimento/Under development"),
            xanchor="left", x=0, font=list(family="Arial",size=12)), # y=1, yanchor="top"),
          annotations = list(text = paste0(ifelse(is.null(pred_summary$high.dat.med), "",
                                                  paste0("<b>Estimated peak 95% CI:</b> (",
                                                         printDate(pred_summary$high.dat.low),
                                                         # format(pred_summary$high.dat.low,form="%d/%b"),
                                                         ", ",
                                                         printDate(pred_summary$high.dat.upper),
                                                         # format(pred_summary$high.dat.upper,form="%d/%b"),
                                                         ")<br>")),
                                           "<b>Total Number of ",metric_leg,":</b> ",
                                           round(pred_summary$NTC500,0), "<br>",
                                           ifelse(flag==1, "",
                                                  paste0("<b>95% CI:</b> (", round(pred_summary$NTC25,0),
                                                         ", ", round(pred_summary$NTC975,0),")<br>")),
                                           "<b>End (99%) of the pandemic:</b> ",
                                           printDate(pred_summary$end.dat.med),
                                           # format(pred_summary$end.dat.med, form="%d/%b"),
                                           "<br><b>95% CI:</b> (",
                                           printDate(pred_summary$end.dat.low),
                                           # format(pred_summary$end.dat.low,form="%d/%b"),
                                           ", ",
                                           printDate(pred_summary$end.dat.upper),
                                           # format(pred_summary$end.dat.upper,form="%d/%b"),
                                           ")"
                                           ),
                             # x=max(pred_n$date), y=1, yref="paper",
                             x = 0.99, y = 0.95, xref="paper", yref="paper",
                             # y=0.9*max(c(unlist(data[[paste0(varPrefix, metric)]]),max(pred_n[,-1]))),
                             font=list(family="Arial",size=10), align="right",
                             showarrow=FALSE),
          xaxis=list(
            title="",
            tickangle=-90, #type='category',
            ## add pred dates to the x axis
            tick0=data$dateStr[1],dtick=7*86400000, # add ticks every week
            tickformat="%d/%b"
          ),
          yaxis=list(title=yaxisTitle, type=if_else(input$scale_LTpred==1,"log","linear"),
                     hoverformat='.0f', hoverinfo="x+y"),
          legend=list(x=0.01, y=0.95,bgcolor='rgba(240,240,240,0.5)'),
          font=f1,
          # add vertical line on last observed day
          shapes=list(type="line", opacity=0.7, line=list(color="black", width=1),
                      y0=0, y1=1, yref="paper",
                      x0=last_date_n, x1=last_date_n)
        )
      
      ## portuguese labels for legend
      metric_pt = switch(metric, Deaths="Deaths", #Deaths="Mortes/Deaths",
                         Recovered="Recuperados/Recovered Cases",
                         # Confirmed="Casos Confirmados/Confirmed Cases")
                         Confirmed="Confirmed Cases")
      
      plt = plt %>%
        ## add mu line
        add_trace(
          x=c(data$date[-c(1:(length(data$date)+length(pred_n$date)-length(mu_plot)))],
              pred_n$date),
          y=c(mu_plot),
          type='scatter', mode='lines', hoverinfo="none", # "x+y",
          # name=paste("Previsão", metric_pt, "Prediction"),
          name=paste(metric_pt, "Estimated Mean"),
          line=list(color='rgb(230,115,0)', dash='solid', width=2.5)
        ) %>%
        ## add lines for observed data
        add_trace(
          x=data$date[which(data$date<=last_date_n)],#[-c(1:30)], # removing 1st 30 days
          y=data[[paste0(varPrefix, metric)]][which(data$date<=last_date_n)],#[-c(1:30)], 
          type='scatter', mode='lines+markers', hoverinfo="x+y",
          name=metric_pt,
          marker=list(
            color=switch(metric,Deaths='rgb(200,30,30)', Confirmed='rgb(100,140,240)'),
            line=list(color='rgb(8,48,107)', width=1.0)),
          line=list(color=switch(metric,Deaths='rgb(200,30,30)', Confirmed='rgb(100,140,240)'), width=2.0)
            # line=list(color=switch(metric,Deaths='rgb(200,30,30)', Confirmed='rgb(100,140,240)'),
            #           width=1.0)
        ) # %>%
      if(flag!=1){
        plt = plt %>%
        ## add 2,5% and 97,5% quantiles
        add_trace(
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
              pred_n$date),
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              pred_n$q25),
          showlegend=F,
          # name=paste("95% IC - ",metric_pt,"CI"),
          name=paste("95% CI - ",metric_pt),
          type='scatter', #mode = 'none',
          mode='lines', hoverinfo="x+y",
          fillcolor='rgba(150,150,150,0.5)',
          line=list(color='rgba(0,0,0,1)', width=0) #, dash='dot')
        ) %>%
        add_trace(
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
              # pred_n$date[1:input$pred_time]),
              pred_n$date),
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              # pred_n$q975[1:input$pred_time]),
              pred_n$q975),
          type='scatter', #mode = 'none',
          mode='lines', hoverinfo="x+y",
          fill='tonexty',
          # showlegend=F,
          # name=paste("95% IC - ",metric_pt,"CI"),
          name=paste("95% CI - ",metric_pt),
          fillcolor='rgba(150,150,150,0.5)',
          line=list(color='rgba(0,0,0,1)', width=0)# , dash='dot')
        )
      }
      plt = plt %>%
        ## add median of prediction
        add_trace(
          # x=c(data$date[-c(1:(length(data$date)+length(pred_n$date)-length(mu_plot)))], # plot median for all data
          x=c(data$date[which(data$date==last_date_n)], # to connect with last observed point
              pred_n$date),
          # y=c(mu_plot,
          y=c(data[[paste0(varPrefix, metric)]][which(data$date==last_date_n)],
              pred_n$med),
          type='scatter', mode='lines+markers', hoverinfo="x+y",
          # name=paste("Previsão", metric_pt, "Prediction"),
          name=paste(metric_pt, "Prediction"),
          marker=list(color='rgb(0,0,0)', size=4), line=list(color='rgb(0,0,0)', dash='dot')
        ) 
      plt
    })
  }
  
  ## add title bar with country name - LT prediction
  output$plotTitle_LT <- renderUI({
    title = paste0(input$country_LTpred,
                   ifelse(input$state_LTpred == "<all>","",paste0(" / ",input$state_LTpred)))
    div(style= 'text-align:center; font-size:15px;
        font-family:"Open Sans",arial,sans-serif; font-weight:bold', 
        title)
  })
  

  ## hide plot -> if lt_summary$flag=2
  # observeEvent(c(input$country_LTpred, input$state_LTpred), {
  observe({
    ## add code to read results and get flag
    ## get flag from confirmed or deaths!
    flag = predLT_n()$flag
    ## then change if condition to if(flag==2)
    # if(input$country_LTpred == "Brazil" & input$state_LTpred %in% statesBR2rem) {
    if(flag == 2){
      updateSelectInput(session, "show_plotLT", choices = c(TRUE, FALSE), selected = FALSE)
    } else{
      updateSelectInput(session, "show_plotLT", choices = c(TRUE, FALSE), selected = TRUE)
    }
  })

  
  ###################################################################
  
  ## OBSERVED DATA GRAPHS
  output$dailyMetrics = renderPlot_obs(
    varPrefix = "New", # legendPrefix="New", yaxisTitle="New Cases per Day")
    legendPrefix="", yaxisTitle="Novos Casos por Dia/New Cases per Day")
  output$cumulatedMetrics = renderPlot_obs(
    varPrefix = "Cum", # legendPrefix="Cumulated", yaxisTitle="Cumulated Cases")
    legendPrefix="", yaxisTitle="Casos Acumulados/Cumulated Cases")
  
  ## SHORT TERM PREDICTION GRAPH
  output$STpred = renderPlot_STpred(
    varPrefix = "Cum", legendPrefix = "", 
    yaxisTitle = "Casos Acumulados/Cumulated Cases",
    input$pred_time
  )
  
  ## LONG TERM PREDICTION GRAPH
  output$LTpred = renderPlot_LTpred(
    varPrefix = "New", legendPrefix = "", 
    yaxisTitle = "Novos Casos por Dia/New Cases per Day"
  )
  
  
}
