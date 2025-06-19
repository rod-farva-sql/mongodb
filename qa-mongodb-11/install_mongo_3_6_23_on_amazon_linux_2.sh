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
  run_command "echo /"UUID=$UUID /var/lib/mongodb xfs defaults,nofail 0 0/" >> /etc/fstab" "Adding volume to /etc/fstab"
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






read -p "Do you want to mount format and mount /var/lib/mongodb_backup? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi


#Wait for the volume to be attached
while  [ ! -e /dev/nvme2n1 ] ; do sleep 1; done

#Check if the volume already has a filesystem
if ! blkid /dev/nvme2n1 | grep -q "UUID"; then
  #Create an XFS filesystem if it doesn't exist
  run_command "mkfs.xfs /dev/nvme2n1" "Formatting /dev/nvme2n1 as XFS"
fi

#Get the UUID of the volume
UUID=$(blkid -s UUID -o value /dev/nvme2n1)

#Create the mount point
run_command "mkdir -p /var/lib/mongodb_backup"  "Creating mount point /var/lib/mongodb_backup"

#Mount the volume using the UUID
run_command "mount UUID=$UUID /var/lib/mongodb_backup" "Mounting ebs volume as /var/lib/mongodb_backup"

#Add the UUID-based entry to /etc/fstab if not already present
if ! grep -q "UUID=$UUID" /etc/fstab; then
  run_command "echo /"UUID=$UUID /var/lib/mongodb_backup xfs defaults,nofail 0 0/" >> /etc/fstab" "Adding volume to /etc/fstab"
fi


# Check if there is data on the mounted volume
if [ "$(ls -A /var/lib/mongodb_backup)" ]; then
    echo "Warning: Data found on /var/lib/mongodb_backup."
    read -p "Would you like to wipe the volume? (yes/no): " response

    if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Wiping the volume..."
        rm -rf "/var/lib/mongodb_backup"/*
        echo "Volume has been wiped."
    else
        echo "Volume data has been kept."
    fi
else
    echo "The volume is empty."
fi














read -p "Do you want to download install mongodb 3.6.23-1? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi



#Now its time to dwonload Mongodb 3.6.23 rpm packages

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/3.6/x86_64/RPMS/mongodb-org-server-3.6.23-1.amzn2.x86_64.rpm" "Downloading mongodb-org-server 3.6.23"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/3.6/x86_64/RPMS/mongodb-org-shell-3.6.23-1.amzn2.x86_64.rpm" "Downloading mongodb-org-shell 3.6.23"

run_command "wget https://repo.mongodb.org/yum/amazon/2/mongodb-org/3.6/x86_64/RPMS/mongodb-org-tools-3.6.23-1.amzn2.x86_64.rpm" "Downloading mongodb-org-tools 3.6.23"


#Now its time to install 3.6.23 rpm packages

run_command "sudo rpm -ivh mongodb-org-server-3.6.23-1.amzn2.x86_64.rpm" "Installing mongodb-org-server 3.6.23"

run_command "sudo rpm -ivh mongodb-org-tools-3.6.23-1.amzn2.x86_64.rpm" "Installing mongodb-org-tools"

run_command "sudo rpm -ivh mongodb-org-shell-3.6.23-1.amzn2.x86_64.rpm" "Installing mongodb-org-shell 3.6.23"

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



echo "Initiating replica set"
# Lets initiate the replica set
initiate_replica_set


