# Load packages required to define the pipeline:
source("./R/packages.R")
source("./R/functions.R")
source("./R/helpers.R")
source("./R/write_bib.R")

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

  # imputation ----
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
  # after imputation ----
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
  # split datasets ----
  pima_split = initial_split(pima_imputed, prop = 0.80, strata = outcome),
  pima_train = training(pima_split),
  pima_test = testing(pima_split),
  pima_folds = vfold_cv(pima_train, strata = "outcome", v = 10),
  # evaluate models ----
  model_results = screen_for_best_model(pima_train, pima_folds),
  tbl_model_results = extract_model_results(model_results),
  plot_model_results = plot_model_results(model_results),
  plot_ROC_curve = plot_model_roc_curve(model_results),
  tbl_tuning_parameters = extract_tuning_parameters(model_results, "base_mars", "roc_auc"),
  plot_tuning_grid = workflowsets::autoplot(model_results, id = "base_mars", metric = "roc_auc"),
  # finalize ----
  best_model_results = pull_best_model_results(model_results, "base_mars"),
  model_test_results = fit_best_model(model_results, best_model_results, pima_split, "base_mars"),
  tbl_test_results = collect_metrics(model_test_results),
  final_cm = conf_mat(model_test_results[[5]][[1]], truth = outcome, estimate = .pred_class),
  plot_conf_matrix = plot_conf_matrix(final_cm)
)

