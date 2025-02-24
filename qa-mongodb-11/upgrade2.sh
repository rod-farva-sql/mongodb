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

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use sudo or log in as root."
  exit 1
fi



# Function to check command success
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed. Exiting."
        exit 1
    fi
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


# Ask user if they want to upgrade the local mongodb instance from 3.6.5 to 6.0.18
echo -e "\033[1;33mDo you want to upgrade the local mongodb instance from 3.6.5 to 6.0.18? (y/n)\033[0m"
read -p "Enter your choice: " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "\033[1;31mExiting the script.\033[0m"
    exit 0
fi

echo -e "\033[1;32mContinuing with upgrade...\033[0m"

# Upgrade from 3.6 to 4.0
echo -e "\033[1;33mUpgrading from 3.6 to 4.0... \033[0m"

run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/4.0/multiverse/binary-arm64/mongodb-org-server_4.0.28_arm64.deb" "Downloading mongodb-org-server"
run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/4.0/multiverse/binary-arm64/mongodb-org-shell_4.0.28_arm64.deb" "Downloading mongodb-org-shell"
run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/4.0/multiverse/binary-arm64/mongodb-org-tools_4.0.28_arm64.deb" "Downloading mongodb-org-tools"

run_command "sudo systemctl stop mongod" "Stopping mongod service"

run_command "sudo dpkg -i mongodb-org-server_4.0.28_arm64.deb" "Installing mongodb-org-server"
run_command "sudo dpkg -i mongodb-org-shell_4.0.28_arm64.deb" "Installing mongodb-org-shell"
run_command "sudo dpkg -i mongodb-org-tools_4.0.28_arm64.deb" "Installing mongodb-org-tools"

run_command "sudo systemctl start mongod" "Starting MongoDB 4.0"

# Wait for mongod to be up and running
wait_for_mongod

run_command 'mongo --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '4.0' })"' "Setting FCV to 4.0"

verify_fcv "4.0"

# Upgrade from 4.0 to 4.2
echo -e "\033[1;33mUpgrading from 4.0 to 4.2... \033[0m"
cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-4.2.repo
[mongodb-org-4.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.2.asc
EOF

sudo systemctl stop mongod
check_success "Stopping MongoDB"

sudo yum install -y mongodb-org
check_success "Installing MongoDB 4.2"

sudo systemctl start mongod
check_success "Starting MongoDB 4.2"

# Wait for mongod to be up and running
wait_for_mongod

mongo --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '4.2' })"
check_success "Setting FCV to 4.2"

verify_fcv "4.2"

# Upgrade from 4.2 to 4.4
echo -e "\033[1;33mUpgrading from 4.2 to 4.4... \033[0m"
cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-4.4.repo
[mongodb-org-4.4]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.4/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.4.asc
EOF

sudo systemctl stop mongod
check_success "Stopping MongoDB"

sudo yum install -y mongodb-org
check_success "Installing MongoDB 4.4"

sudo systemctl start mongod
check_success "Starting MongoDB 4.4"

# Wait for mongod to be up and running
wait_for_mongod

mongo --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '4.4' })"
check_success "Setting FCV to 4.4"

verify_fcv "4.4"

echo "MongoDB successfully upgraded to 4.4!"

# Upgrade from 4.4 to 5.0
echo -e "\033[1;33mUpgrading from 4.4 to 5.0... \033[0m"
cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-5.0.repo
[mongodb-org-5.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/5.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-5.0.asc
EOF

sudo systemctl stop mongod
check_success "Stopping MongoDB"

echo "Uninstalling mongo 4.4 packages"
sudo yum remove -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools mongodb-org-database-tools
check_success "Succedded uninstalling mongo 4.4 packages"

# Install mongodb-mongosh (MongoDB shell) if it's not already installed
#sudo yum install -y mongodb-mongosh
#check_success "Installing MongoDB Shell (mongosh)"

sudo yum install -y mongodb-org
check_success "Installing MongoDB 5.0"

sudo systemctl start mongod
check_success "Starting MongoDB 5.0"

# Wait for mongod to be up and running
wait_for_mongod

# After upgrading to 5.0, validate MongoDB version
check_mongodb_version "5.0.30"

echo "MongoDB binaries updated successfully."

mongosh --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '5.0' })"
check_success "Setting FCV to 5.0"

verify_fcv_sh "5.0"

echo "MongoDB successfully upgraded to 5.0!"




# Upgrade from 5.0 to 6.0
echo -e "\033[1;33mUpgrading from 5.0 to 6.0... \033[0m"

cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-6.0.repo
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-6.0.asc
EOF


sudo systemctl stop mongod
check_success "Stopping MongoDB"

echo "Uninstalling mongo 5.0 packages"
sudo yum remove -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools mongodb-org-database-tools
check_success "Succedded uninstalling mongo 5.0 packages"

# Install mongodb-mongosh (MongoDB shell) if it's not already installed
#sudo yum install -y mongodb-mongosh
#check_success "Installing MongoDB Shell (mongosh)"

#sudo yum install -y mongodb-org-6.0.18
sudo yum install -y sudo yum install mongodb-org-6.0.18 mongodb-org-server-6.0.18 mongodb-org-mongos-6.0.18 mongodb-org-database-6.0.18 mongodb-org-tools-6.0.18
check_success "Installing MongoDB 6.0.18"

sudo systemctl start mongod
check_success "Starting MongoDB 6.0"

# Wait for mongod to be up and running
wait_for_mongod

# After upgrading to 6.0, validate MongoDB version
check_mongodb_version "6.0.18"

echo "MongoDB binaries updated successfully."

mongosh --quiet --eval "db.adminCommand({ setFeatureCompatibilityVersion: '6.0' })"
check_success "Setting FCV to 6.0"

verify_fcv_sh "6.0"

echo -e "\033[1;32mMongoDB successfully upgraded to 6.0!\033[0m"


