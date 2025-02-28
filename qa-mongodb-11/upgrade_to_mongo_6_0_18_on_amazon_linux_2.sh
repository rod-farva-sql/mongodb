#!/bin/bash


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


# Function to verify feature compatibility version
verify_fcv() {
    local expected_version=$1
    local fcv=$(mongo --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })['featureCompatibilityVersion']['version']")
    if [[ "$fcv" == "$expected_version" ]]; then
        echo -e "\033[1;32mFeature Compatibility Version is $fcv (as expected). \033[0m"
    else
        echo -e "\033[1;31mError: Expected FCV $expected_version but found $fcv. Exiting.\033[0m"
        exit 1
    fi
}

# Function to verify feature compatibility version with mongosh
verify_fcv_sh() {
    local expected_version=$1
    local fcv=$(mongosh --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })['featureCompatibilityVersion']['version']")
    if [[ "$fcv" == "$expected_version" ]]; then
        echo -e "\033[1;32mFeature Compatibility Version is $fcv (as expected). \033[0m"
    else
        echo -e"\033[1;31mError: Expected FCV $expected_version but found $fcv. Exiting. \033[0m"
        exit 1
    fi
}

# Function to wait for mongod service to start
wait_for_mongod() {
    echo "Waiting for mongod service to start..."
    local retries=30  # Number of attempts
    local wait_time=5  # Time to wait between attempts in seconds
    local count=0
    while ! systemctl is-active --quiet mongod && [ $count -lt $retries ]; do
        echo "mongod is not active. Retrying in $wait_time seconds..."
        sleep $wait_time
        ((count++))
    done
    if [ $count -eq $retries ]; then
        echo "Error: mongod service failed to start. Exiting."
        exit 1
    else
        echo "mongod service is up and running."
		echo "Waiting an additional 5 seconds to ensure MongoDB is ready..."
		sleep 5
    fi
}


# Function to verify MongoDB server version
check_mongodb_version() {
    local expected_version=$1
    local current_version=$(mongosh --quiet --eval "db.version()" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to connect to MongoDB. Ensure the service is running."
        exit 1
    fi

    if [[ "$current_version" == "$expected_version" ]]; then
        echo "MongoDB is running the expected version: $current_version"
    else
        echo "Error: MongoDB is running version $current_version, but $expected_version is expected. Exiting."
        exit 1
    fi
}
# Function to check if a directory is mounted
check_mount() {
    local mount_point=$1
    if mount | grep -q " on ${mount_point} "; then
        echo -e "\033[1;32m${mount_point} is mounted.\033[0m"
    else
        echo -e "\033[1;31m${mount_point} is not mounted. Please mount it before proceeding.\033[0m"
        exit 1
    fi
}


######################################################
#This is where the party starts...

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use sudo or log in as root."
  exit 1
fi

# Ask user if they want to upgrade the local mongodb instance from 3.6.5 to 6.0.18
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 3.6.5 to 6.0.18? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "3.6.23"

# Upgrade from 3.6.23 to 4.0.28

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-server-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 4.0.28"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-tools-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-tools 4.0.28"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-shell-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 4.0.28"

run_command "rpm -Uvh mongodb-org-server-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 4.0.28"

run_command "rpm -Uvh mongodb-org-tools-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-tools to 4.0.28"

run_command "rpm -Uvh mongodb-org-shell-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-shell to 4.0.28"

run command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "4.0.28"

#Validate the FCV is now at 4.0
run command "mongo --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '4.0' })"" "Setting FCV to 4.0"
verify_fcv "4.0"

echo -e "\033[1;32mMongoDB successfully upgraded to 6.0!\033[0m"


