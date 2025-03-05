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



# Function to initiate MongoDB replica set
initiate_replica_set() {
    echo "Initiating MongoDB replica set..."

    # Run rs.initiate() and capture the output
    local init_result=$(mongo --quiet --eval "try { rs.initiate(); rs.status().ok } catch(e) { printjson(e) }" 2>/dev/null)

    # Check if the initiation was successful
    if [[ "$init_result" == "1" ]]; then
        success_message "Replica set successfully initiated."
    else
        error_message "Error: Failed to initiate replica set. It may already be initialized or there was an issue."
        exit 1
    fi
}


####################################


# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use sudo or log in as root."
  exit 1
fi


read -p "Do you want to change the hostname? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi

# Prompt the user for a new hostname
read -p "Enter new hostname: " NEW_HOSTNAME

# Ensure a hostname was provided
if [ -z "$NEW_HOSTNAME" ]; then
  echo "No hostname provided. Exiting."
  exit 1
fi

# Write the new hostname to /etc/hostname
echo "$NEW_HOSTNAME" > /etc/hostname

# Update the current hostname immediately
if command -v hostnamectl >/dev/null 2>&1; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
else
  hostname "$NEW_HOSTNAME"
fi

echo "Hostname has been updated to '$NEW_HOSTNAME'."


read -p "Do you want to mount format and mount /var/lib/mongodb? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi


#Wait for the volume to be attached
while  [ ! -e /dev/nvme1n1 ] ; do sleep 1; done

#Check if the volume already has a filesystem
if ! blkid /dev/nvme1n1 | grep -q "UUID"; then
  #Create an XFS filesystem if it doesn't exist
  run_command "mkfs.xfs /dev/nvme1n1" "Formatting /dev/nvme1n1 as XFS"
fi

#Get the UUID of the volume
UUID=$(blkid -s UUID -o value /dev/nvme1n1)

#Create the mount point
run_command "mkdir -p /var/lib/mongodb"  "Creating mount point /var/lib/mongodb"

#Mount the volume using the UUID
run_command "mount UUID=$UUID /var/lib/mongodb" "Mounting ebs volume as /var/lib/mongodb"

#Add the UUID-based entry to /etc/fstab if not already present
if ! grep -q "UUID=$UUID" /etc/fstab; then
  run_command "echo \"UUID=$UUID /var/lib/mongodb xfs defaults,nofail 0 0\" >> /etc/fstab" "Adding volume to /etc/fstab"
fi


# Check if there is data on the mounted volume
if [ "$(ls -A /var/lib/mongodb)" ]; then
    echo "Warning: Data found on /var/lib/mongodb."
    read -p "Would you like to wipe the volume? (yes/no): " response

    if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Wiping the volume..."
        rm -rf "/var/lib/mongodb"/*
        echo "Volume has been wiped."
    else
        echo "Volume data has been kept."
    fi
else
    echo "The volume is empty."
fi


read -p "Do you want to download install mongodb 6.0.19? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi



#Now its time to download Mongodb 6.0.19 rpm packages

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-org-server-6.0.19-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 6.0.19"


#This is the latest version of mongodb-database-tools for Mongo 6.x (https://www.mongodb.com/docs/database-tools/release-notes/dbtools-100.5.0-changelog/)
#Starting with MongoDB 4.4, the MongoDB Database Tools are now released separately from the MongoDB Server and use their own versioning, with an initial version of 100.0.0.
#https://www.mongodb.com/docs/database-tools/
#This also replaces the mongo-org-tools since 4.4
run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-database-tools-100.5.4.x86_64.rpm" "Downloading mongodb-database-tools 100.5.4"

#Original mongo shell is deprecated in 5+ so we now install this
run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-mongosh-2.4.0.x86_64.rpm" "Downloading mongosh 2.4.0"






#Now its time to install 6.0.19 rpm packages

run_command "yum install -y mongodb-org-server-6.0.19-1.amzn2.x86_64.rpm" "Installing mongodb-org-server 6.0.19"

#cyrus-sasl is needed by mongodb-database-tools-100.5.4-1.x86_64
run_command "yum install -y cyrus-sasl"  "Installing cyrus-sasl for mongodb-database-tools prereq"

#cyrus-sasl-gssapi is needed by mongodb-database-tools-100.5.4-1.x86_64
run_command "yum install -y cyrus-sasl-gssapi"  "Installing sudo yum install cyrus-sasl-gssapi for mongodb-database-tools prereq"

run_command "yum install -y mongodb-database-tools-100.5.4.x86_64.rpm" "Installing mongodb-database-tools"

run_command "yum install -y mongodb-mongosh-2.4.0.x86_64.rpm" "Installing mongosh 2.4.0"




#Set permissions
#RPM package sets mongo user as mongod instead of mongodb
run_command "sudo chown -R mongod:mongod /var/lib/mongodb /var/log/mongodb" "Set ownership on /var/lib/mongodb and /var/log/mongodb to mongod:mongod"
#run_command "sudo chown -R mongod:mongod /var/log/mongodb" "Set ownership on /var/log/mongodb to mongod:mongod"

#Download and update /etc/mongod.conf
run_command "wget https://raw.githubusercontent.com/rod-farva-sql/mongodb/refs/heads/main/qa-mongodb-11/etc/mongod.conf" "Downloading /etc/mongod.conf"

run_command "sudo cp -f mongod.conf /etc/mongod.conf" "Updating /etc/mongod.conf with new version"

run_command "sudo systemctl enable mongod" "Enabling mongod service"

run_command "sudo systemctl start mongod" "Starting mongod service"

run_command "sudo systemctl status mongod -l" "Checking status of mongod service"

run_command "sudo sh -c 'echo vm.max_map_count=1048576 >> /etc/sysctl.conf'" "Updating vm max map count"


echo "Now you need to join this host to your replica set"



