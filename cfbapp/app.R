#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# Libraries
library(shiny)
library(tidyverse)
library(tidymodels)
library(cfbplotR)
library(snakecase)
library(bslib)
library(xgboost)

# Data:
dfl <- read.csv("gamesModifiedModel2022CondensedLogos.csv") %>% 
       filter(classification == "fbs")                      %>%  
       select(school, opponent, week, matches("AvgLag"))

newNames <- snakecase::to_any_case(colnames(dfl), case = "snake") 
newNames <- gsub("_lag", "", newNames)
newNamesLimited <- sort(newNames[-c(1,2,3)])
teamNames <- sort(unique(dfl$school))
source("predict matchups.R")

# Create the Shiny UI and Server components
ui <- fluidPage(
  
  # Theme Setter
  theme = bs_theme(
    bg = "#f5c962", fg = "#050505", primary = "#198E42",
    base_font = font_google("Space Mono"),
    code_font = font_google("Space Mono")
  ),
  
  # CSS style blueprint:
  tags$style(HTML("
      @import url('https://fonts.googleapis.com/css2?family=Yusei+Magic&display=swap');
      h1 {
        font-family: 'Space Mono', sans-serif;
        color:#767676  ;
        font-size: 50px;
      }
      h2 {
        font-family: 'Space Mono', sans-serif;
        color:#1d24a8  ;
        font-size: 50px;
      }
      h5 {
        color: #1d24a8;
        font-weight: bold;
      }
      body {
        background-color: #FFFDF9;
        color: #0D9347;
      }
      .shiny-input-container {
        color: #474747;
      }
      p {
        color: #050505;
        border-color: #f5c962;
        border-bottom-style: solid;
        font-size: 20px;
      }
      code {
         font-size: 20px;
      }"
      )
    ),
  
  # Title
  titlePanel(title=div( img(src="icon.png", height = "100px", width = "100px"), img(src="logo.png", height = "100px"))),
  
  # Subtitle
  h5('Please click the "Submit" button to get started!'),
  
  # Side bar with inputs:
  sidebarLayout(
    sidebarPanel(
      selectizeInput("team1", "Home Team",   choices = teamNames, multiple = FALSE, selected = teamNames[27]),
      selectizeInput("team2", "Away Team", choices = teamNames, multiple = FALSE, selected = teamNames[36]),
      numericInput("spread", "Home Team's Spread", value = -7, min = -80, max = 80),
      numericInput("moneyLine1", "Home Team's Moneyline",value = -500, min = -12000, max = 12000),
      numericInput("moneyLine2", "Away Team's Moneyline",value = 350, min = -12000, max = 12000),
      numericInput("overUnder",  "Over/Under",value = 90, min = 0, max = 180),
      selectizeInput("plotVar", "Bar Chart Variable", choices = newNamesLimited, multiple = FALSE,
                     selected = newNamesLimited[74]),
      actionButton("submitBtn", "Submit")
    ),
    
    # Body
    mainPanel(
      tableOutput("predictionsTable"),
      
      plotOutput("comparePlot"),
      
      code("Info:"),
      
      p("The predictions you see use an XGBoost model for the output. Overall, the accuracy of wins/losses sits at about 78%, whereas the
        accuracy of the Cover Prediction sits at about 58%. The model was trained up until the last 2-3 games of the 2022 Season for all teams!
        Model predictions tend to be conservative, so you won't see many score differentials beyond a 15 point threshold. Predictions tend to be
        more useful when comparing teams from a similar echelon of strength, such as Penn State/Oregon.")
    )
  )
)

server <- function(input, output) {
  
  # Return a table with the predictions of the selected teams.
  predictions <- eventReactive(input$submitBtn, {
    team1 <-  input$team1
    team2 <-  input$team2
    spread <- input$spread
    moneyLine1 <- input$moneyLine1
    moneyLine2 <- input$moneyLine2
    overUnder  <- input$overUnder
    
  # Return predictMatchup dataframe and pull relevant details:
    if (!is.null(team1) && !is.null(team2)) {
      predictMatchup(team1, 
                     team2, 
                     year = 2022, 
                     manualBooks = T, 
                     spreadTeam1 = spread, 
                     moneylineTeam1 = moneyLine1, 
                     moneylineTeam2 = moneyLine2, 
                     overunder = overUnder) %>% 
        select(school, pointsDiffPredFinal, winPred, coverPred, spread) %>%
        mutate(coverPred = if_else(-pointsDiffPredFinal == spread, 
                                   "Push",
                                   if_else(coverPred == 1, "Covers",
                                           "Does Not Cover")),
               winPred   = if_else(abs(pointsDiffPredFinal) == 0, "It's 50/50 :)",
                                 if_else(winPred == 1, "Win" , "Loss"))) %>% 
        rename(School = school,
               `Predicted Score Difference` = pointsDiffPredFinal,
               `Win Prediction` = winPred,
               `Cover Prediction` =  coverPred,
               Spread = spread)
     }
    }
  )
  
  # Make some CFB comparison plots.
  cfbplot <- eventReactive(input$submitBtn, {
    team1 <-  input$team1
    team2 <-  input$team2
    variable <- input$plotVar
    
    # The plot:
    dfl %>% dplyr::filter(school == team1 | school == team2) %>% 
            group_by(school) %>% 
            filter(week == max(week)) %>% 
            ungroup() %>% 
            set_names(newNames) %>% 
            ggplot(aes_string(y= "school", x = variable)) +
            geom_col(aes(color = school, fill = school), linewidth = 2) +
            scale_color_cfb(alt_colors = teamNames) +
            scale_fill_cfb(alpha = .8) +
            theme_minimal() +
            theme(legend.position = "none",
                  panel.grid.major.y = element_blank()) +
            theme(axis.text.y = element_cfb_logo(size = 3)) +
            theme(axis.text.x = element_text(size = 20)) +
            theme(axis.title=element_text(size=20)) +

            ylab("") +
            xlab(to_any_case(variable, "title"))
   }
  )
  
  # Grab output of the prediction dataframe:
  output$predictionsTable <- renderTable(
    expr = {predictions()},
    striped  = T,
    bordered = T)
  
  #Grab output of the plot.
  output$comparePlot <- renderPlot(
    expr = {cfbplot()},  bg="transparent"
  )
}

# Run the application 
shinyApp(ui = ui, server = server)