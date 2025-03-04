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


# Function to verify feature compatibility version using either mongo or mongosh
verify_fcv() {
    local expected_version=$1
    local mongo_cmd

    # Determine which MongoDB client to use
    if command -v mongo &>/dev/null; then
        mongo_cmd="mongo --quiet --eval"
    elif command -v mongosh &>/dev/null; then
        mongo_cmd="mongosh --quiet --eval"
    else
        echo -e "\033[1;31mError: Neither 'mongo' nor 'mongosh' is installed or accessible.\033[0m"
        exit 1
    fi

    # Get the featureCompatibilityVersion
    local fcv=$($mongo_cmd "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })['featureCompatibilityVersion']['version']" 2>/dev/null)

    # Check if the command returned a valid result
    if [[ -z "$fcv" ]]; then
        echo -e "\033[1;31mError: Failed to retrieve Feature Compatibility Version. Ensure MongoDB is running.\033[0m"
        exit 1
    fi

    # Compare the retrieved version with the expected version
    if [[ "$fcv" == "$expected_version" ]]; then
        echo -e "\033[1;32mFeature Compatibility Version is $fcv (as expected).\033[0m"
    else
        echo -e "\033[1;31mError: Expected FCV $expected_version but found $fcv. Exiting.\033[0m"
        exit 1
    fi
}

# Function to wait for mongod service to start and be ready
wait_for_mongod() {
    echo "Waiting for mongod service to start..."
    local retries=30  # Number of attempts
    local wait_time=5  # Time to wait between attempts in seconds
    local count=0

    # Step 1: Ensure the mongod service is active
    while ! systemctl is-active --quiet mongod && [ $count -lt $retries ]; do
        echo "mongod is not active. Retrying in $wait_time seconds..."
        sleep $wait_time
        ((count++))
    done

    if [ $count -eq $retries ]; then
        echo "Error: mongod service failed to start. Exiting."
        exit 1
    fi

    echo "mongod service is up and running."
    
    # Step 2: Ensure MongoDB is fully ready to accept connections
    count=0
    local mongo_cmd

    # Determine which MongoDB client to use
    if command -v mongo &>/dev/null; then
        mongo_cmd="mongo --quiet --eval"
    elif command -v mongosh &>/dev/null; then
        mongo_cmd="mongosh --quiet --eval"
    else
        echo "Error: Neither 'mongo' nor 'mongosh' is installed or accessible."
        exit 1
    fi

    echo "Waiting for MongoDB to become fully operational..."
    while [ $count -lt $retries ]; do
        local status=$($mongo_cmd "db.runCommand({ ping: 1 })" 2>/dev/null)

        if [[ "$status" == *"ok"* ]]; then
            echo "MongoDB is fully operational."
            return 0
        fi

        echo "MongoDB is not ready yet. Retrying in $wait_time seconds..."
        sleep $wait_time
        ((count++))
    done

    echo "Error: MongoDB did not become ready within the timeout period. Exiting."
    exit 1
}

# Function to verify MongoDB server version using either mongo or mongosh
check_mongodb_version() {
    local expected_version=$1
    local current_version

    # Try using mongo first
    if command -v mongo &>/dev/null; then
        current_version=$(mongo --quiet --eval "db.version()" 2>/dev/null)
    elif command -v mongosh &>/dev/null; then
        current_version=$(mongosh --quiet --eval "db.version()" 2>/dev/null)
    else
        echo "Error: Neither 'mongo' nor 'mongosh' is installed or accessible."
        exit 1
    fi

    # Check if the command was successful
    if [[ -z "$current_version" ]]; then
        echo "Error: Failed to retrieve MongoDB version. Ensure the service is running."
        exit 1
    fi

    # Compare versions
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

# Function to check if MongoDB replica set is initiated (with retries) using either mongo or mongosh
check_replica_set() {
    local retries=30  # Maximum retries
    local wait_time=5  # Seconds to wait between retries
    local count=0
    local mongo_cmd

    echo "Checking if MongoDB replica set is initiated..."

    # Determine which MongoDB client to use
    if command -v mongo &>/dev/null; then
        mongo_cmd="mongo --quiet --eval"
    elif command -v mongosh &>/dev/null; then
        mongo_cmd="mongosh --quiet --eval"
    else
        echo "Error: Neither 'mongo' nor 'mongosh' is installed or accessible."
        exit 1
    fi

    while [[ $count -lt $retries ]]; do
        local rs_status=$($mongo_cmd "try { rs.status().ok } catch(e) { printjson(e) }" 2>/dev/null)

        if [[ -z "$rs_status" ]]; then
            echo "MongoDB service might not be ready yet. Retrying in $wait_time seconds..."
        elif [[ "$rs_status" == "1" ]]; then
            echo "Replica set is initiated and running."
            return 0
        else
            echo "Replica set is not fully initialized yet. Retrying in $wait_time seconds..."
        fi

        sleep $wait_time
        ((count++))
    done

    echo "Error: Replica set did not become ready within the timeout period. Exiting."
    exit 1
}

######################################################
#This is where the party starts...

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use sudo or log in as root."
  exit 1
fi

# Ask user if they want to upgrade the local mongodb instance from 3.6.5 to 4.0.28
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 3.6.5 to 4.0.28? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "3.6.23"

# Verify the replica set is running
check_replica_set

# Upgrade from 3.6.23 to 4.0.28

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-server-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 4.0.28"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-tools-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-tools 4.0.28"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/RPMS/mongodb-org-shell-4.0.28-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 4.0.28"

run_command "yum update -y mongodb-org-server-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 4.0.28"

run_command "yum update -y mongodb-org-tools-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-tools to 4.0.28"

run_command "yum update -y mongodb-org-shell-4.0.28-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-shell to 4.0.28"

run_command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "4.0.28"

# Verify the replica set is running
check_replica_set

#Validate the FCV is now at 4.0
run_command "mongo --quiet --eval \"db.adminCommand({ setFeatureCompatibilityVersion: '4.0' })\"" "Setting FCV to 4.0"
verify_fcv "4.0"

echo -e "\033[1;32mMongoDB successfully upgraded to 4.0.28!\033[0m"






# Ask user if they want to upgrade the local mongodb instance from 4.0.28 to 4.2.25
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 4.0.28 to 4.2.25? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "4.0.28"

# Upgrade from 4.0.28 to 4.2.25

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.2/x86_64/RPMS/mongodb-org-server-4.2.25-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 4.2.25"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.2/x86_64/RPMS/mongodb-org-tools-4.2.25-1.amzn2.x86_64.rpm" "Downloading mongodb-org-tools 4.2.25"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.2/x86_64/RPMS/mongodb-org-shell-4.2.25-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 4.2.25"



run_command "yum update -y mongodb-org-server-4.2.25-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 4.2.25"

run_command "yum update -y mongodb-org-tools-4.2.25-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-tools to 4.2.25"

run_command "yum update -y mongodb-org-shell-4.2.25-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-shell to 4.2.25"



run_command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "4.2.25"

# Verify the replica set is running
check_replica_set

#Validate the FCV is now at 4.2
run_command "mongo --quiet --eval \"db.adminCommand({ setFeatureCompatibilityVersion: '4.2' })\"" "Setting FCV to 4.2"
verify_fcv "4.2"



echo -e "\033[1;32mMongoDB successfully upgraded to 4.2!\033[0m"





# Ask user if they want to upgrade the local mongodb instance from 4.2.25 to 4.4.29
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 4.2.25 to 4.4.29? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "4.2.25"

# Upgrade from 4.2.25 to 4.4.29

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.4/x86_64/RPMS/mongodb-org-server-4.4.29-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 4.4.29"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.4/x86_64/RPMS/mongodb-org-shell-4.4.29-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 4.4.29"

run_command "yum update -y mongodb-org-server-4.4.29-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 4.4.29"

run_command "yum update -y mongodb-org-shell-4.4.29-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-shell to 4.4.29"

run_command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "4.4.29"

# Verify the replica set is running
check_replica_set

#Validate the FCV is now at 4.4
run_command "mongo --quiet --eval \"db.adminCommand({ setFeatureCompatibilityVersion: '4.4' })\"" "Setting FCV to 4.4"
verify_fcv "4.4"

echo -e "\033[1;32mMongoDB successfully upgraded to 4.4!\033[0m"






# Ask user if they want to upgrade the local mongodb instance from 4.4.29 to 5.0.31
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 4.4.29 to 5.0.31? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "4.4.29"

# Upgrade from 4.4.29 to 5.0.31

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/5.0/x86_64/RPMS/mongodb-org-server-5.0.31-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 5.0.31"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/5.0/x86_64/RPMS/mongodb-org-shell-5.0.31-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 5.0.31"

run_command "yum update -y mongodb-org-server-5.0.31-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 5.0.31"

run_command "yum update -y mongodb-org-shell-5.0.31-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-shell to 5.0.31"

run_command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "5.0.31"

# Verify the replica set is running
check_replica_set

#Validate the FCV is now at 5.0
run_command "mongo --quiet --eval \"db.adminCommand({ setFeatureCompatibilityVersion: '5.0' })\"" "Setting FCV to 5.0"
verify_fcv "5.0"

echo -e "\033[1;32mMongoDB successfully upgraded to 5.0!\033[0m"








# Ask user if they want to upgrade the local mongodb instance from 5.0.31 to 6.0.19
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 5.0.31 to 6.0.19? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Validate MongoDB version
check_mongodb_version "5.0.31"

# Upgrade from 5.0.31 to 6.0.19

run_command "systemctl stop mongod" "Stopping MongoDB"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-org-server-6.0.19-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 6.0.19"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-database-tools-100.5.4.x86_64.rpm" "Downloading mongodb-database-tools 100.5.4"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-mongosh-2.4.0.x86_64.rpm" "Downloading mongosh 2.4.0"

run_command "yum update -y mongodb-org-server-6.0.19-1.amzn2.x86_64.rpm" "Upgrading mongodb-org-server to 6.0.19"

run_command "yum remove -y mongodb-org-shell" "Removing deprecated mongodb-org-shell"

run_command "yum remove -y mongodb-org-tools" "Removing deprecated mongodb-org-tools"

#cyrus-sasl is needed by mongodb-database-tools-100.5.4-1.x86_64
run_command "yum install -y cyrus-sasl"  "Installing cyrus-sasl for mongodb-database-tools prereq"

#cyrus-sasl-gssapi is needed by mongodb-database-tools-100.5.4-1.x86_64
run_command "yum install -y cyrus-sasl-gssapi"  "Installing sudo yum install cyrus-sasl-gssapi for mongodb-database-tools prereq"

#This also replaces the mongo-org-tools since 4.4
run_command "yum install -y mongodb-database-tools-100.5.4.x86_64.rpm" "Installing mongodb-database-tools"

#Original mongo shell is deprecated in 5+ so we now install this
run_command "yum install -y mongodb-mongosh-2.4.0.x86_64.rpm" "Installing mongosh 2.4.0"

run_command "sudo systemctl start mongod"

# Wait for mongod to be up and running
wait_for_mongod

# Validate MongoDB version
check_mongodb_version "6.0.19"

# Verify the replica set is running
check_replica_set

#Validate the FCV is now at 6.0
run_command "mongo --quiet --eval \"db.adminCommand({ setFeatureCompatibilityVersion: '6.0' })\"" "Setting FCV to 6.0"
verify_fcv "6.0"

echo -e "\033[1;32mMongoDB successfully upgraded to 6.0!\033[0m"














