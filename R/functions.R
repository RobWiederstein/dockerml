build_file_info_table <- function(data, rownames = "attributes", round = 2) {
  file.info(data) %>%
    t() %>%
    tibble::as_tibble(rownames = rownames) %>%
    dplyr::rename(value = round)
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
extract_model_results <- function(data_wf_set) {
  successful_workflows <- data_wf_set %>%
    filter(
      !purrr::map_lgl(result, inherits, "try-error") & # Not a try-error
        !purrr::map_lgl(result, is.null) & # Not NULL
        !(purrr::map_lgl(result, is.list) & purrr::map_int(result, length) == 0) # Not an empty list
    )
  cat("Processing", nrow(successful_workflows), "workflow(s) with valid results for ranking.\n")

  results_tibble <- successful_workflows %>%
    workflowsets::rank_results(select_best = TRUE) %>% # select_best = TRUE as in your original function
    dplyr::filter(.metric == "roc_auc") %>%
    dplyr::select(rank, wflow_id, .config, .metric, mean)

  return(results_tibble)
}
extract_tuning_parameters <- function(data, model_id, metric) {
  data %>%
    extract_workflow_set_result(id = model_id) %>%
    select_best(metric = metric)
}
fit_best_model <- function(all_results, best_model_results, data_split, workflow_id) {
  all_results %>%
    extract_workflow(workflow_id) %>%
    finalize_workflow(best_model_results) %>%
    last_fit(split = data_split)
}
impute_nas_via_mice <- function(data) {
  mice_output <- mice::mice(data, m = 1, method = "pmm", seed = 123, printFlag = FALSE)
  pima_imputed_by_mice <- mice::complete(mice_output, 1)
  pima_imputed_by_mice %>%
    mutate(outcome = factor(
      outcome,
      levels = c(0, 1),
      labels = c("nondiabetic", "diabetic")
    ))
}
plot_conf_matrix <- function(conf_mat) {
  # extract and calculate pct for heat map
  conf_df <- conf_mat[["table"]] %>%
    as_tibble() %>%
    mutate(total = sum(n)) %>%
    mutate(pct = n / total)
  names(conf_df)
  names(conf_df)[1] <- "Predicted"
  names(conf_df)[2] <- "Actual"
  # reorder factors to mirror common conf matrix
  conf_df$Predicted <- factor(conf_df$Predicted, levels = c("nondiabetic", "diabetic"))
  conf_df$Actual <- factor(conf_df$Actual, levels = c("diabetic", "nondiabetic"))
  # create the heatmap with ggplot2
  ggplot(conf_df, aes(x = Predicted, y = Actual, fill = pct)) +
    geom_tile(color = "white") +
    geom_label(aes(label = n), vjust = 0.5, hjust = 0.5, size = 8, fill = "white") +
    scale_fill_distiller(palette = "YlOrRd", type = "seq", direction = 1) +
    theme_minimal() +
    scale_x_discrete(position = "top") +
    theme(
      axis.text.x = element_text(hjust = 0.5, vjust = 0, size = 12),
      axis.text.x.top = element_text(vjust = -3),
      axis.text.y = element_text(size = 12),
      axis.title = element_text(size = 20),
      legend.position = "none",
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      aspect.ratio = 1
    )
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
plot_model_results <- function(data) {
  autoplot(
    data,
    rank_metric = "roc_auc",
    metric = "roc_auc",
    select_best = TRUE
  ) +
    geom_text(aes(y = mean - .035, label = wflow_id), angle = 90, hjust = 1, size = 4.5) +
    coord_cartesian(ylim = c(0.7, 0.9)) +
    scale_x_continuous(breaks = 1:10, minor_breaks = NULL) +
    cowplot::theme_half_open() +
    theme(legend.position = "none")
}
plot_model_roc_curve <- function(data) {
  # pull the best performing models by fold
  data %>%
    workflowsets::rank_results() %>%
    dplyr::filter(.metric == "roc_auc") %>%
    group_by(wflow_id) %>%
    arrange(wflow_id, desc(mean)) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    arrange(desc(mean)) %>%
    mutate(best_mod_folds = paste(wflow_id, .config, sep = "_"), .before = .metric) %>%
    pull(best_mod_folds) -> best_model_folds
  # filter model predictions to best performing fold
  data %>%
    collect_predictions() %>%
    mutate(wflow_id_config = paste(wflow_id, .config, sep = "_"), .before = preproc) %>%
    filter(wflow_id_config %in% all_of(best_model_folds)) -> best_model_predictions

  # plot
  best_model_predictions %>%
    group_by(wflow_id) %>%
    roc_curve(truth = outcome, .pred_nondiabetic) %>%
    ggplot(aes(
      x = 1 - specificity,
      y = sensitivity,
      color = wflow_id
    )) +
    geom_path() +
    geom_abline(lty = 3) +
    coord_equal() +
    theme_minimal_grid() +
    labs(color = "Recipe_Model:")
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
pull_best_model_results <- function(data, model_id) {
  data %>%
    extract_workflow_set_result(model_id) %>%
    select_best(metric = "roc_auc")
}
read_in_csv_file <- function(data, ...) {
  vroom(
    data,
    show_col_types = FALSE,
    .name_repair = ~ janitor::make_clean_names(.x)
  ) %>%
    dplyr::rename(dbf = diabetes_pedigree_function)
}
screen_for_best_model <- function(data_train, data_folds) {
  # recipes ----
  base_recipe <- recipe(formula = outcome ~ ., data = data_train)

  normalized_recipe <-
    base_recipe %>%
    step_normalize(all_predictors()) %>%
    step_zv(all_predictors())

  # model specifications ----
  ## svm linear ----
  # svm_linear_spec <-
  #   svm_linear(
  #     cost = tune()
  #   ) %>%
  #   set_engine("LiblineaR") %>%
  #   set_mode("classification")
  # hard_class_metrics <- metric_set(accuracy, sens, spec, f_meas, mcc, roc_auc)
  # svm_linear_cost_grid <- grid_regular(cost(), levels = 10)
  ## xgboost ----
  xgb_spec <-
    boost_tree(
      trees = tune(),
      tree_depth = tune(),
      learn_rate = tune(),
      loss_reduction = tune(),
      sample_size = tune(),
      mtry = tune()
    ) %>%
    set_engine("xgboost") %>%
    set_mode("classification") %>%
    translate()
  ## brulee ----
  mlp_brulee_spec <-
    mlp(
      hidden_units = tune(),
      penalty = tune(),
      epochs = tune(),
      learn_rate = tune(),
      activation = "relu"
    ) %>%
    set_engine("brulee", verbose = F) %>%
    set_mode("classification")
  # mars ----
  mars_spec <-
    mars(
      num_terms = tune(),
      prod_degree = tune(),
      prune_method = tune()
    ) %>%
    set_engine("earth", nfold = 10) %>%
    set_mode("classification")
  # rpart ----
  rpart_spec <-
    decision_tree(
      tree_depth = tune(),
      min_n = tune(),
      cost_complexity = tune()
    ) %>%
    set_engine("rpart") %>%
    set_mode("classification")

  # random forrest ----
  rf_spec <-
    rand_forest(
      mtry = tune(),
      trees = tune(),
      min_n = tune()
    ) %>%
    set_engine("ranger") %>%
    set_mode("classification")
  # knn ----
  knn_spec <-
    nearest_neighbor(
      neighbors = tune(),
      weight_func = tune()
    ) %>%
    set_engine("kknn") %>%
    set_mode("classification") %>%
    translate()
  ## log reg ----
  lr_spec <-
    logistic_reg(
      penalty = tune(),
      mixture = tune()
    ) %>%
    set_engine("glmnet") %>%
    set_mode("classification") %>%
    translate()
  ## nnet ----
  nnet_spec <-
    bag_mlp(
      hidden_units = tune(),
      penalty = tune(),
      epochs = tune()
    ) %>%
    set_engine("nnet") %>%
    set_mode("classification") %>%
    translate()

  # create worksets ----
  base <-
    workflow_set(
      preproc = list(base = base_recipe),
      models = list(
        mars = mars_spec,
        k_nrst_nghbr = knn_spec,
        random_forest = rf_spec,
        rpart = rpart_spec,
        xgboost = xgb_spec
      )
    )
  normalized <-
    workflow_set(
      preproc = list(normalized = normalized_recipe),
      models = list(
        k_nrst_nghbr = knn_spec,
        log_regression = lr_spec,
        neural_network = nnet_spec,
        mlp_brulee = mlp_brulee_spec
      )
    ) # %>%
  # option_add(metrics = hard_class_metrics, id = "normalized_svm_linear") %>%
  # option_add(grid = svm_linear_cost_grid, id = "normalized_svm_linear")
  # adjust dials
  # option_add(param_info = nnet_param, id = "normalized_neural_network")

  # combine ----
  all_workflows <- bind_rows(base, normalized)
  all_workflows

  # create grid ----
  race_ctrl <-
    control_race(
      save_pred = TRUE,
      parallel_over = "everything",
      save_workflow = TRUE
    )

  # race results ----
  race_results <-
    all_workflows %>%
    workflow_map(
      "tune_race_anova",
      seed = 1,
      resamples = data_folds,
      grid = 25,
      control = race_ctrl
    )
  race_results
}
summarize_pima_raw <- function(data, diabetes) {
  psych::describe(filter(data, outcome == diabetes)) %>%
    dplyr::select(-n, -skew, -kurtosis, -se) %>%
    dplyr::mutate(across(where(is.numeric), ~ round(.x, 2)))
}
switch_0_to_NA <- function(data) {
  cols_to_impute <- c("glucose", "blood_pressure", "skin_thickness", "insulin", "bmi")
  data %>% mutate(across(all_of(cols_to_impute), ~ ifelse(.x == 0, NA_real_, .x)))
}
