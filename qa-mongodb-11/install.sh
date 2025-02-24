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
while  ! -e /dev/nvme1n1 ; do sleep 1; done

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
  run_command "echo "UUID=$UUID /var/lib/mongodb xfs defaults,nofail 0 0" >> /etc/fstab" "Adding volume to /etc/fstab"
fi


read -p "Do you want to download install mongodb 3.6.5? (yes/no): " answer
if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Continuing..."
else
  echo "Operation cancelled."
  exit 0
fi



#Now its time to install Mongodb 3.6.5

#This is a prereq for mongodb 3.6.5
run_command "wget http://launchpadlibrarian.net/668090466/libssl1.0.0_1.0.2n-1ubuntu5.13_arm64.deb" "Downloading libssl1.0.0"

run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/3.6/multiverse/binary-arm64/mongodb-org-server_3.6.5_arm64.deb" "Downloading mongodb-org-server"

run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/3.6/multiverse/binary-arm64/mongodb-org-mongos_3.6.5_arm64.deb" "Downloading mongodb-org-mongos"

run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/3.6/multiverse/binary-arm64/mongodb-org-tools_3.6.5_arm64.deb" "Downloading mongodb-org-tools"

run_command "wget https://repo.mongodb.org/apt/ubuntu/dists/xenial/mongodb-org/3.6/multiverse/binary-arm64/mongodb-org-shell_3.6.5_arm64.deb" "Downloading mongodb-org-shell"

  
run_command "sudo dpkg -i libssl1.0.0_1.0.2n-1ubuntu5.13_arm64.deb" "Installing libssl1.0.0"

run_command "sudo dpkg -i mongodb-org-server_3.6.5_arm64.deb" "Installing mongodb-org-server"

run_command "sudo dpkg -i mongodb-org-mongos_3.6.5_arm64.deb" "Installing mongodb-org-mongos"

run_command "sudo dpkg -i mongodb-org-tools_3.6.5_arm64.deb" "Installing mongodb-org-tools"

run_command "sudo dpkg -i mongodb-org-shell_3.6.5_arm64.deb" "Installing mongodb-org-shell"


#Set permissions
run_command "chown -R mongodb:mongodb /var/lib/mongodb" "Set ownership on /var/lib/mongodb to mongodb:mongodb"


#Download and update /etc/mongod.conf
run_command "wget http://launchpadlibrarian.net/668090466/libssl1.0.0_1.0.2n-1ubuntu5.13_arm64.deb" "Downloading /etc/mongod.conf"
