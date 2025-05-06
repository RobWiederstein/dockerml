#!/bin/bash
echo "--- Running Docker Build and Pipeline ---"
# Run compose, rebuild if needed, wait for completion
docker compose up --build

# Check the exit code of the compose command
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "--- Pipeline finished successfully. ---" # Slightly changed message
  # Check if we are NOT in a GitHub Actions environment
  if [ -z "$GITHUB_ACTIONS" ]; then
    echo "--- Opening report locally... ---"
    open ./docs/index.html # macOS command to open file/URL
  else
    echo "--- Report generated. Skipping local browser open in CI environment. ---"
  fi
else
  echo "--- Pipeline failed with exit code $EXIT_CODE. Report not opened. ---"
  exit $EXIT_CODE # Exit script with the same error code
fi
