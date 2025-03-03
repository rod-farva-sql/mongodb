#! /bin/bash

# Function to run a command and check its result
run_command() {
    eval "$1"
    if [ $? -eq 0 ]; then
        success_message "$2 succeeded."
    else
        error_message "$2 failed. Stopping script."
        exit 1
    fi
} 

# Function to echo messages in green
success_message() {
    echo -e "\e[32m$1\e[0m"
}

# Function to echo messages in red
error_message() {
    echo -e "\e[31m$1\e[0m"
}



# Ask user if they want to run the script
echo -e "\033[1;33mDo you want to run mongodump from qa-mongodb-02 and place the files on the local machine? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi



echo -e "\033[1;32mContinuing with mongodump...\033[0m"

run_command "mkdir /var/lib/mongodb_backup/migration" "Creating /var/lib/mongodb_backup/migration directory"

run_command "mongodump --host qa-mongodb-02 --port 27017 --gzip --numParallelCollections=1 --out /var/lib/mongodb_backup/migration" "Running mongodump"



# Ask user if they want to import the dump from qa-mongdb-02 into the local server
echo -e "\033[1;33mDo you want to import/mongro restore the data in /var/log/mongodb_backup/migration to the local machine? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with mongorestore...\033[0m"
#we want to exclude the config files as that contains sharding info for the cluster...
run_command "mongorestore --host localhost --port 27017 --gzip --dir=/var/lib/mongodb_backup/migration/ --nsExclude=config.*" "Running mongorestore"

echo "Script complete"
