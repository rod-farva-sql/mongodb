#! /bin/bash

LOG_DIR="/var/lib/mongodb_backup/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/mongodb_backup_$(date +'%Y%m%d_%H%M%S').log"

# Function to log and echo to both console and log file
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to run a command and check its result
run_command() {
    eval "$1" 2>&1 | tee -a "$LOG_FILE"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        log "\e[32m$2 succeeded.\e[0m"
    else
        log "\e[31m$2 failed. Stopping script.\e[0m"
        exit 1
    fi
} 

# Ask user if they want to run the script
log "\033[1;33mDo you want to run mongodump from qa-mongodb-02 and place the files on the local machine? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    log "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

log "\033[1;32mContinuing with mongodump...\033[0m"

run_command "mkdir -p /var/lib/mongodb_backup/migration" "Creating /var/lib/mongodb_backup/migration directory"

# Timestamp before mongodump
start_time=$(date +%s)
log "\033[1;34mStarting mongodump at: $(date)\033[0m"

run_command "mongodump --host qa-mongodb-02 --port 27017 --gzip --numParallelCollections=1 --out /var/lib/mongodb_backup/migration" "Running mongodump"

# Timestamp after mongodump
end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))
log "\033[1;34mFinished mongodump at: $(date)\033[0m"
log "\033[1;34mMongodump duration: ${minutes} minutes ${seconds} seconds\033[0m"

# Ask user if they want to import the dump into local server
log "\033[1;33mDo you want to import/mongorestore the data to the local machine? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    log "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

log "\033[1;32mContinuing with mongorestore...\033[0m"

# Timestamp before mongorestore
restore_start=$(date +%s)
log "\033[1;34mStarting mongorestore at: $(date)\033[0m"

run_command "mongorestore --host localhost --port 27017 --gzip --dir=/var/lib/mongodb_backup/migration/ --nsExclude=config.*" "Running mongorestore"

restore_end=$(date +%s)
restore_duration=$((restore_end - restore_start))
restore_minutes=$((restore_duration / 60))
restore_seconds=$((restore_duration % 60))
log "\033[1;34mFinished mongorestore at: $(date)\033[0m"
log "\033[1;34mMongorestore duration: ${restore_minutes} minutes ${restore_seconds} seconds\033[0m"

log "\033[1;32mScript complete.\033[0m"
log "Full log saved to $LOG_FILE"
