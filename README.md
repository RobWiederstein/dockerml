
# dockerml

The goal of the `dockerml` project is to serve as a demonstration of modern reproducible research principles, applied to a classic machine learning problem using the Pima Indians Diabetes dataset from Kaggle. It aims to (1) clearly showcase each component of a reproducible workflow, (2) fully automate this workflow from code changes through published results, and (3) publish these results as a well-documented webpage using a tidymodels approach for the analysis. 

To achieve peak reproducibility, several oft-cited tools are integrated: `git` underpins version control. The R environment itself, including all package dependencies and their exact versions, is managed by `renv`. The `targets` and its related package `tarchetypes` then builds the programming pipeline. The packages, R, and the environment is wrapped into a Docker container, providing a shareable, consistent runtime environment that executes identically across different machines. For workflow automation, a GitHub Actions workflow (defined in a YAML file within the .github/workflows directory of the repository) was created. Finally, for publishing, the scientific publishing platform quarto, is used to create a webpage via pandoc. This webpage displays plots and tables and also  incorporates a  citation strategy, managed by Zotero.



# Challenges

- **Long Docker Build Times:** The initial Docker build times were excessively long, taking 40-50 minutes. This was due to the large number of R packages and system dependencies being installed from scratch each time.

- **Missing System Library Dependencies in Docker:** Iteratively added system libraries (e.g., libxml2-dev, libfreetype6-dev, libfontconfig1-dev, libharfbuzz-dev, libfribidi-dev, libpng-dev, libcairo2-dev, libjpeg-dev, pkg-config) to the Dockerfile. This was necessary to allow R packages (like xml2, systemfonts) to compile and install correctly from source.

- **Platform and Architecture Mismatches (amd64 vs. arm64 on macOS host):** Eventually, combining Dockerfile.base and the main Dockerfile into a single file to simplify the build chain and resolve persistent platform resolution issues.

- **Quarto Rendering Complexities within Docker/targets:** The Quarto CLI itself failing (System command 'quarto' failed) when called by tar_quarto. The index_files directory and its contents (plots, CSS) not being generated or correctly placed when using tar_quarto with _quarto.yml's output-dir. This led to the workaround of using direct quarto render ... calls in entrypoint.sh and ensuring _quarto.yml was not present or used by the render command in the script. Ultimately, the index.qmd was removed from the targets pipeline, and the quarto render command was directly called in the entrypoint.sh script.

- **GitHub Actions Workflow Configuration:**  Refactoring the workflow to build a single combined Dockerfile instead of a separate base and pipeline image. Implementing Docker layer caching (cache-from: type=gha, cache-to: type=gha,mode=max) using docker/build-push-action. Making the run_pipeline.sh script CI-friendly (e.g., not trying to open a browser in a non-graphical environment).


# Acknowledgements

Some people and at least one company deserve special mention:

- Will Landau, author of the `targets` package.  His Github profile is [here](https://github.com/wlandau/). Eli Lilly Inc. deserves some recognition as well.

- Joel Nitta, a researcher of ferns and educator on reproducibility.  His GitHub profile can be found [here](https://github.com/joelnitta).
