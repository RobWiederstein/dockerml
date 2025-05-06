#!/bin/bash
echo "ENTRYPOINT START PATH: $PATH"
echo "Starting analysis..."

# --- ADD THIS SECTION BACK ---
# Run targets pipeline first, exit script with error if R fails
echo "Running targets::tar_make()..."
Rscript -e 'targets::tar_make()' || exit 1
echo "targets::tar_make() finished."
# --- END ADDED SECTION ---

# Render Quarto report to current directory (/app)
echo "Rendering Quarto report to /app..."
quarto render index.qmd --to html
RENDER_STATUS=$?

if [ $RENDER_STATUS -ne 0 ]; then
  echo "Quarto render failed with status $RENDER_STATUS."
  exit 1
fi
echo "Quarto render successful."

# Move rendered files to final destination
# (Using mv as per your last version)
echo "Moving rendered files to final destination..."
FINAL_OUTPUT_DIR="_targets/user/results" # Relative path from /app

# Ensure the final destination directory exists
mkdir -p "$FINAL_OUTPUT_DIR"

# Optional but recommended: Clean previous contents from destination
find "$FINAL_OUTPUT_DIR" -mindepth 1 -delete
echo "Cleaned $FINAL_OUTPUT_DIR."

# Move the index.html file if it exists
if [ -f "index.html" ]; then
  mv index.html "$FINAL_OUTPUT_DIR/" # Using mv
  echo "Moved index.html"
else
  echo "Warning: index.html not found in /app after render."
fi

# Move the index_files directory recursively if it exists
if [ -d "index_files" ]; then
  mv index_files "$FINAL_OUTPUT_DIR/" # Using mv
  echo "Moved index_files directory"
else
  echo "Info: index_files directory not found in /app after render."
fi

echo "File moving finished."

echo "Analysis finished."
