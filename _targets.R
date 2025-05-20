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
  # Download ----
  tar_download(
    name = pima_data,
    urls = pima_data_url,
    paths = raw_pima_data_path
  ),
  # File info ----
  downloaded_file_info = build_file_info_table(pima_data),
  # Load raw data ----
  pima_raw = read_in_csv_file(pima_data),
  # zeroes to NA ----
  pima_raw_converted = switch_0_to_NA(pima_raw),
  # explore ----
  tbl_raw_summary_0 = summarize_pima_raw(pima_raw_converted, diabetes = 0),
  tbl_raw_summary_1 = summarize_pima_raw(pima_raw_converted, diabetes = 1),
  plot_raw_missing = naniar::vis_miss(pima_raw_converted),
  plot_raw_outliers = plot_scaled_outliers_3_sd_or_more(pima_raw_converted),
  pima_raw_ol_to_na = convert_outliers_to_na(pima_raw_converted, sd_threshold = 3),
  # imputation ----
  pima_imputed = impute_nas_via_mice(pima_raw_ol_to_na),
  # after imputation ----
  tbl_imputed_summary_0 = summarize_pima_raw(pima_imputed, diabetes = "diabetic"),
  tbl_imputed_summary_1 = summarize_pima_raw(pima_imputed, diabetes = "nondiabetic"),
  plot_imputed_outliers = plot_scaled_outliers_3_sd_or_more(pima_imputed),
  plot_imputed_corr = plot_correlation_by_vars(pima_imputed),
  plot_imputed_missing = naniar::vis_miss(pima_imputed),
  # split datasets ----
  data_to_model = {
    pima_raw_converted %>%
      mutate(outcome = factor(
        outcome,
        levels = c(0, 1),
        labels = c("nondiabetic", "diabetic")
      ))
  },
  pima_split = initial_split(data_to_model, prop = 0.80, strata = outcome),
  pima_train = training(pima_split),
  pima_test = testing(pima_split),
  pima_folds = vfold_cv(pima_train, strata = "outcome", v = 10),
  # evaluate models ----
  model_results = screen_for_best_model(pima_train, pima_folds),
  tbl_model_results = extract_model_results(model_results),
  plot_model_results = plot_model_results(model_results),
  plot_ROC_curve = plot_model_roc_curve(model_results),
  tbl_tuning_parameters = extract_tuning_parameters(model_results, "base_random_forest", "roc_auc"),
  plot_tuning_grid = workflowsets::autoplot(model_results, id = "base_random_forest", metric = "roc_auc"),
  # finalize ----
  best_model_results = pull_best_model_results(model_results, "base_random_forest"),
  model_test_results = fit_best_model(model_results, best_model_results, pima_split, "base_random_forest"),
  tbl_test_results = collect_metrics(model_test_results),
  final_cm = conf_mat(model_test_results[[5]][[1]], truth = outcome, estimate = .pred_class),
  plot_conf_matrix = plot_conf_matrix(final_cm)
)
