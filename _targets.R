# Load packages required to define the pipeline:
source("./R/packages.R")
source("./R/functions.R")
source("./R/helpers.R")

# Set target options:
tar_option_set(format = "qs", error = "continue", seed = 1)

# set file structure
create_user_folders(c("data", "interim", "results"))

# globals
data_dir <- "_targets/user/data"
inter_dir <- "_targets/user/intermediates"
results_dir <- "_targets/user/results"
pima_data_url <- "https://raw.githubusercontent.com/npradaschnor/Pima-Indians-Diabetes-Dataset/refs/heads/master/diabetes.csv"
raw_pima_data_path <- here::here(data_dir, "pima_indians_diabetes_dataset.csv")

# Define the target plan using explicit tar_target() / tar_download()
tar_plan(
  # Download (track remote changes)
  tar_download(
    name = pima_data,
    urls = pima_data_url,
    paths = raw_pima_data_path
  ),
  # File info
  downloaded_file_info = build_file_info_table(pima_data),
  # Load raw data
  pima_raw = read_in_csv_file(pima_data),
  # Convert zeros to NAs using the custom function
  pima_raw_converted = switch_0_to_NA(pima_raw),
  # --- Analysis BEFORE Imputation ---
  tar_target(
    name = tbl_raw_summary_0,
    command = psych::describe(filter(pima_raw_converted, outcome == 0)) %>%
      dplyr::select(-n, -skew, -kurtosis, -se) %>%
      dplyr::mutate(across(where(is.numeric), ~ round(.x, 2)))
  ),
  tar_target(
    name = tbl_raw_summary_1,
    command = psych::describe(filter(pima_raw_converted, outcome == 1)) %>%
      dplyr::select(-n, -skew, -kurtosis, -se) %>%
      dplyr::mutate(across(where(is.numeric), ~ round(.x, 2)))
  ),
  tar_target(
    name = plot_raw_missing,
    command = naniar::vis_miss(pima_raw_converted)
  ),
  tar_target(
    name = plot_raw_outliers,
    command = plot_scaled_outliers_3_sd_or_more(
      pima_raw_converted
    )
  ),
  # set outliers > 3 sd to NA 652 to 694
  tar_target(
    pima_raw_ol_to_na,
    command = convert_outliers_to_na(pima_raw_converted, sd_threshold = 3)
  ),

  # --- Imputation Step ---
  tar_target(
    name = pima_imputed,
    command = {
      mice_output <- mice::mice(pima_raw_ol_to_na, m = 1, method = "pmm", seed = 123, printFlag = FALSE)
      pima_imputed_by_mice <- mice::complete(mice_output, 1)
      pima_imputed_by_mice %>%
        mutate(outcome = factor(outcome,
          levels = c(0, 1),
          labels = c("nondiabetic", "diabetic")
        ))
    }
  ),
  # --- Analysis AFTER Imputation ---
  tar_target(
    name = tbl_imputed_summary_0,
    # Use the imputed data as input
    command = psych::describe(filter(pima_imputed, outcome == "nondiabetic")) %>%
      dplyr::select(-n, -skew, -kurtosis, -se) %>%
      dplyr::mutate(across(where(is.numeric), ~ round(.x, 2))),
  ),
  tar_target(
    name = tbl_imputed_summary_1,
    # Use the imputed data as input
    command = psych::describe(filter(pima_imputed, outcome == "diabetic")) %>%
      dplyr::select(-n, -skew, -kurtosis, -se) %>%
      dplyr::mutate(across(where(is.numeric), ~ round(.x, 2))),
  ),
  tar_target(
    name = plot_imputed_outliers,
    command = plot_scaled_outliers_3_sd_or_more(pima_imputed)
  ),
  plot_imputed_corr = plot_correlation_by_vars(pima_imputed),
  plot_imputed_missing = naniar::vis_miss(pima_imputed),
  # models
  pima_split = initial_split(pima_imputed, prop = 0.80, strata = outcome),
  pima_train = training(pima_split),
  pima_test = testing(pima_split),
  pima_folds = vfold_cv(pima_train, strata = "outcome"),
  # begin logistic regression ----
  tar_target(
    name = tuned_log_reg,
    command = build_log_reg(
      train = pima_train,
      folds = pima_folds,
      engine = "glmnet"
    )
  ),
  tar_target(
    name = results_log_reg,
    command = model_log_reg(
      workflow = tuned_log_reg$log_reg_wflow,
      last_model = tuned_log_reg$log_reg_model,
      test = pima_split
    )
  ),
  tbl_cm_log_reg = conf_mat(results_log_reg$lr_last_fit[[5]][[1]], truth = outcome, estimate = .pred_class),
  tbl_results_log_reg = results_log_reg$lr_last_fit[[3]][[1]],
  # end logistic regression ----
  # knn begin ----
  tar_target(
    name = tuned_knn,
    command = build_knn(
      train = pima_train,
      folds = pima_folds,
      engine = "kknn"
    )
  ),
  tar_target(
    name = results_knn,
    command = model_knn(
      workflow = tuned_knn$knn_wflow,
      last_model = tuned_knn$knn_model,
      test = pima_split
    )
  ),
  tbl_cm_knn = conf_mat(results_knn$knn_last_fit[[5]][[1]], truth = outcome, estimate = .pred_class),
  tbl_results_knn = results_knn$knn_last_fit[[3]][[1]],
  
  # knn end ----
  # resamples begin ----
  tar_target(
    name = model_resamples,
    command = list(knn = tuned_knn$knn_res, lr = tuned_log_reg$log_reg_res)
  ),
  # resamples end ----
  # test results begin ----
  tar_target(
    name = test_set_results,
    command = list(knn = results_knn$knn_last_fit, lr = results_log_reg$lr_last_fit)
  ),
  # test results end ----
  lr_best_auc = select_best(model_resamples$lr, metric = "roc_auc"),
  knn_best_auc = select_best(model_resamples$knn, metric = "roc_auc"),
  tar_target(
    name = models,
    command = dplyr::bind_rows(
      # logistic regression results
      model_resamples$lr |>
        collect_predictions(parameters = lr_best_auc) |>
        roc_curve(outcome, .pred_nondiabetic) |>
        mutate(model = "Logistic Reg."),
      # nearest neighbor results
      model_resamples$knn |>
        collect_predictions(parameters = knn_best_auc) |>
        roc_curve(outcome, .pred_nondiabetic) |>
        mutate(model = "K-Nearest-Neighbor"),
    )
  ),
  tar_target(
    name = plot_roc_curve,
    command = models |>
      ggplot(aes(x = 1 - specificity, y = sensitivity, color = model)) +
      geom_path() +
      geom_abline(linetype = "dashed") +
      scale_color_manual(values = c("Logistic Reg." = "blue", "K-Nearest-Neighbor" = "red")) +
      labs(
        title = "ROC Curve",
        x = "1 - Specificity",
        y = "Sensitivity"
      ) +
      theme_minimal()
  ),
  tar_target(
    name = tbl_test_set_results,
    command = {
      metrics <- map_df(test_set_results, ~ bind_rows(.x[[".metrics"]], .id = "model"))
      metrics$model <- c("knn", "knn", "knn", "lr", "lr", "lr")
      final <-
        metrics |>
        arrange(desc(.metric), desc(.estimate)) |>
        select(!.config)
      final
    }
  )
)

