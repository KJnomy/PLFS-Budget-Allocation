library(readxl)
library(readr)
library(dplyr)
library(lpSolve)

# --- Step 1: Load Layouts and Data ---
layout_path <- "C:/Users/USER/Downloads/project/Data_LayoutPLFS_Calendar_2024.xlsx"

data_layout_cp <- read_excel(layout_path, sheet = "cperv1")
data_layout_ch <- read_excel(layout_path, sheet = "chhv1")

cp_widths <- as.numeric(data_layout_cp[[4]], na.rm = TRUE)
col_names_cp <- data_layout_cp[[5]]

ch_widths <- as.numeric(data_layout_ch[[5]], na.rm = TRUE)
col_names_ch <- data_layout_ch[[6]]

data_cp <- read_fwf("C:/Users/USER/Downloads/project/CPERV1.TXT", col_positions = fwf_widths(cp_widths[-1]), col_types = cols(.default = "c"))
colnames(data_cp) <- col_names_cp[-1]

data_ch <- read_fwf("C:/Users/USER/Downloads/project/CHHV1.TXT", col_positions = fwf_widths(ch_widths[-1]), col_types = cols(.default = "c"))
colnames(data_ch) <- col_names_ch[-1]

# --- Step 2: Expand household data by HH_SIZE ---
data_ch$HH_SIZE <- as.integer(data_ch$HH_SIZE)
chhv1_expanded <- data_ch[rep(seq_len(nrow(data_ch)), times = data_ch$HH_SIZE), ]
row.names(chhv1_expanded) <- NULL
row.names(data_cp) <- NULL

# --- Step 3: Merge person and household data ---
data_merged <- bind_cols(data_cp, chhv1_expanded[18:38])

# Convert relevant columns to integer/numeric
cols_to_convert <- 6:ncol(data_merged)
data_merged[ , cols_to_convert] <- lapply(data_merged[ , cols_to_convert], function(x) as.integer(as.character(x)))

# --- Step 4: Define Employment Status ---
employed_codes <- c(11, 12, 21, 31, 41, 51, 61)
data_merged$PAS <- as.integer(as.character(data_merged$PAS))
data_merged$employed <- ifelse(data_merged$PAS %in% employed_codes, 1, 0)

# --- Step 5: Prepare grouping variables ---
data_merged <- data_merged %>%
  mutate(
    ST = as.character(ST),
    SEC = as.character(SEC),
    SG = as.character(SG),
    HCE_TOT = as.numeric(HCE_TOT)
  )

# --- Step 6: Aggregate by State, Sector, Social Group ---
agg_data <- data_merged %>%
  group_by(ST, SEC, SG) %>%
  summarise(
    total_population = n(),
    total_employed = sum(employed, na.rm = TRUE),
    avg_expenditure = mean(HCE_TOT, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(total_population > 0) %>%
  mutate(
    emp_rate = total_employed / total_population,
    unemp_rate = 1 - emp_rate,
    need_exp_proxy = 1 / (avg_expenditure + 1),  # avoid divide by zero
    emp_uplift_proxy = 0.7 * unemp_rate + 0.3 * need_exp_proxy
  )

# --- Step 7: Setup optimization problem ---
total_budget <- 200000000000  #  Rs 20 thousand crores

obj <- agg_data$emp_uplift_proxy
n_groups <- nrow(agg_data)

# Constraint 1: Total budget limit
A1 <- matrix(1, nrow = 1, ncol = n_groups)
dir1 <- "<="
rhs1 <- total_budget

# Constraint 2: Minimum 10% allocation to SC/ST (SG codes "1"=SC, "2"=ST)
scst_indices <- which(agg_data$SG %in% c("1", "2"))
A2 <- matrix(0, nrow = 1, ncol = n_groups)
A2[1, scst_indices] <- 1
dir2 <- ">="
rhs2 <- 0.1 * total_budget

# Constraint 3: Minimum 1.2% allocation to each state
states <- unique(agg_data$ST)
n_states <- length(states)
A3 <- matrix(0, nrow = n_states, ncol = n_groups)
for (i in seq_along(states)) {
  A3[i, which(agg_data$ST == states[i])] <- 1
}
dir3 <- rep(">=", n_states)
rhs3 <- rep(0.012 * total_budget, n_states)  # 1.2% per state

# Constraint 4: Minimum Rs. 1200 allocation to each group
A4 <- diag(n_groups)
dir4 <- rep(">=", n_groups)
rhs4 <- rep(1200, n_groups)

# Combine all constraints
A <- rbind(A1, A2, A3, A4)
dir <- c(dir1, dir2, dir3, dir4)
rhs <- c(rhs1, rhs2, rhs3, rhs4)

# --- Step 8: Solve LP ---
lp_solution <- lp(
  direction = "max",
  objective.in = obj,
  const.mat = A,
  const.dir = dir,
  const.rhs = rhs,
  all.int = FALSE
)

# --- Step 9: Output results ---
if(lp_solution$status == 0) {
  agg_data$allocation <- lp_solution$solution
  print(agg_data %>% arrange(desc(allocation)) %>% head(20))
  write.csv(agg_data, "PLFS_Optimal_Allocation.csv", row.names = FALSE)
  cat("Optimization successful! Allocation saved to PLFS_Optimal_Allocation.csv\n")
} else {
  stop("No optimal solution found. Try reducing minimum allocation constraints.")
}


agg_data$unemp_priority <- cut(
  agg_data$unemp_rate,
  breaks = seq(0, 1, by = 0.1),        # intervals: [0.0–0.1), [0.1–0.2), ..., [0.9–1.0]
  labels = seq(0.1, 1.0, by = 0.1),    # assign priority values from 0.1 to 1.0
  include.lowest = TRUE,              # include 0.0 in the first bin
  right = FALSE                       # left-closed, right-open intervals [a, b)
)

agg_data$unemp_priority <- as.numeric(as.character(agg_data$unemp_priority))
x <- agg_data$unemp_priority * agg_data$emp_uplift_proxy * agg_data$total_population
y <- (x / sum(x, na.rm = TRUE)) * total_budget
agg_data$ab2 <- y


#analysis by state
state_budget <- agg_data %>% 
  group_by(ST) %>%
  summarise(total_budget = sum(ab2, na.rm = TRUE)) %>%
  arrange(desc(total_budget))


state_names <- tibble::tibble(
  ST = as.character(1:37),
  state_name = c(
    "Jammu & Kashmir", "Himachal Pradesh", "Punjab", "Chandigarh", "Uttarakhand",
    "Haryana", "Delhi", "Rajasthan", "Uttar Pradesh", "Bihar",
    "Sikkim", "Arunachal Pradesh", "Nagaland", "Manipur", "Mizoram",
    "Tripura", "Meghalaya", "Assam", "West Bengal", "Jharkhand",
    "Odisha", "Chhattisgarh", "Madhya Pradesh", "Gujarat", "Daman & Diu",
    "Dadra & Nagar Haveli", "Maharashtra", "Andhra Pradesh", "Karnataka", "Goa",
    "Lakshadweep", "Kerala", "Tamil Nadu", "Puducherry", "Andaman & Nicobar Islands",
    "Telangana", "Ladakh"
  )
)

state_budget <- state_budget %>%
  mutate(ST = as.character(ST)) %>%
  left_join(state_names, by = "ST") %>%
  select(ST, state_name, total_budget) %>%
  arrange(desc(total_budget))


write.csv(state_budget, "C:/Users/USER/Downloads/project/Statewise_Budget_Allocation_With_Names.csv", row.names = FALSE)

# View the table
print(state_budget)


#analysis sector budget
sector_budget <- agg_data %>%
     group_by(SEC) %>%
     summarise(total_budget = sum(ab2, na.rm = TRUE)) %>%
     arrange(desc(total_budget))

sector_budget <- sector_budget %>%
  mutate(sector_name = ifelse(SEC == "1", "Rural", "Urban"))

write.csv(sector_budget, "C:/Users/USER/Downloads/project/Sectorwise_Budget_Allocation.csv", row.names = FALSE)
 # print the table
print(sector_budget)

#analysis by caste
caste_budget <- agg_data %>%
  group_by(SG) %>%
  summarise(total_budget = sum(ab2, na.rm = TRUE)) %>%
  arrange(desc(total_budget))

caste_budget <- caste_budget %>%
  mutate(caste_name = case_when(
    SG == "1" ~ "SC",
    SG == "2" ~ "ST",
    SG == "3" ~ "OBC",
    SG == "9" ~ "Others",
    TRUE ~ "Unknown"
  ))

write.csv(caste_budget, "C:/Users/USER/Downloads/project/Castewise_Budget_Allocation.csv", row.names = FALSE)

print(caste_budget)
