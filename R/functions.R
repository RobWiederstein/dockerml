build_file_info_table <- function(data, rownames = "attributes", round = 2) {
  file.info(data) %>%
    t() %>%
    tibble::as_tibble(rownames = rownames) %>%
    dplyr::rename(value = round)
}
create_user_folders <- function(dir_name) {
  something <- function(dir_name) {
    target_dir <- here::here("_targets", "user", dir_name)
    if (!fs::dir_exists(target_dir)) {
      fs::dir_create(target_dir)
      message(glue::glue("Directory \"{dir_name}\" created."))
    } else {
      message(glue::glue("Directory \"{dir_name}\" already exists."))
    }
  }
  print("Creating user directories...")
  purrr::walk(dir_name, something)
}
convert_outliers_to_na <- function(data, sd_threshold = 3, na_rm = TRUE) {
  # Check if input is a data frame
  if (!is.data.frame(data)) {
    stop("Input 'data' must be a data frame or tibble.")
  }

  # Apply the mutation across numeric columns
  data %>%
    mutate(across(where(is.numeric), ~ {
      # Calculate mean and sd for the current column (.x)
      col_mean <- mean(.x, na.rm = na_rm)
      col_sd <- sd(.x, na.rm = na_rm)

      # Check if sd is valid (not NA and not zero)
      if (is.na(col_sd) || col_sd == 0) {
        # If sd is invalid, return the column unchanged
        .x
      } else {
        # Identify outliers
        is_outlier <- abs(.x - col_mean) > (sd_threshold * col_sd)
        # Replace outliers with NA_real_ (numeric NA)
        ifelse(is_outlier, NA_real_, .x)
      }
    }))
}
switch_0_to_NA <- function(data) {
  cols_to_impute <- c("glucose", "blood_pressure", "skin_thickness", "insulin", "bmi")
  data %>% mutate(across(all_of(cols_to_impute), ~ ifelse(.x == 0, NA_real_, .x)))
}
plot_scaled_outliers_3_sd_or_more <- function(data) {
  data %>%
    mutate(outcome = factor(
      outcome,
      levels = c(0, 1),
      labels = c("Normal", "Diabetes") # Assign labels to levels
    )) %>%
    select(outcome, where(is.numeric)) %>%
    mutate(across(
      -outcome, # Selects all columns in the current data except 'outcome'
      ~ as.numeric(scale(.x)) # Apply scale() and ensure output is numeric vector
    )) %>%
    tidyr::pivot_longer(
      cols = -outcome, # Pivot all columns except outcome
      names_to = "variable_name", # More descriptive name than 'name'
      values_to = "scaled_value" # More descriptive name than 'value'
    ) %>%
    mutate(is_outlier = abs(scaled_value) > 3) -> df
  ggplot(df) +
    aes(variable_name, scaled_value) +
    geom_boxplot() +
    geom_point(
      data = filter(df, is_outlier == TRUE),
      aes(colour = "red"), alpha = 1
    ) +
    scale_y_continuous(limits = c(-4, 4)) +
    facet_grid(. ~ outcome) +
    labs(
      title = "Distribution of Scaled Predictors by Outcome",
      x = "Predictor Variable",
      y = "Scaled Value (Z-score)"
    ) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}
read_in_csv_file <- function(data, ...) {
  vroom(
    data,
    show_col_types = FALSE,
    .name_repair = ~ janitor::make_clean_names(.x)
  ) %>%
    dplyr::rename(dbf = diabetes_pedigree_function)
}
plot_correlation_by_vars <- function(data, mapping, ...) {
  my_ggpairs_scatter_smooth <- function(data, mapping, ...) {
    ggplot(data = data, mapping = mapping) +
      # Add points (adjust alpha/size for overplotting)
      geom_point(alpha = 0.3, size = 0.05) +
      # Add smoother line (method="loess" by default for <1000 pts, "gam" otherwise)
      # se = FALSE hides the confidence interval ribbon
      geom_smooth(method = "loess", se = FALSE, color = "steelblue", ...) +
      theme_classic()
  }

  # Assuming 'your_data' is your data frame with numeric columns
  ggpairs(
    data %>%
      select(-outcome) %>%
      select(where(is.numeric)),
    lower = list(
      continuous = my_ggpairs_scatter_smooth # Use your custom function here
    )
    # Add other ggpairs arguments (diag, upper, columns, etc.) as needed
  )
}
