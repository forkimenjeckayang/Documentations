
# Resolving Database Persistence Issues by Linking EC2 Instance to EBS 

## Problem Statement
Having a database running on an EC2 instance was getting dropped every time the instance was restarted, causing data loss and disruption to the application.

## Solution
To ensure the database data persists beyond the lifetime of the EC2 instance, we will link the instance to an EBS (Elastic Block Store) volume.

## Steps

### 1. Create an EBS Volume
1. Go to the AWS Management Console and navigate to the EC2 dashboard.
2. Click on "Volumes" in the left-hand menu.
3. Click on "Create Volume" and configure the volume according to your database requirements (size, type, availability zone, etc.).

### 2. Attach the EBS Volume to the EC2 Instance

1. Go to the AWS Management Console.
2. Navigate to the **EC2 Dashboard**.
3. Select **Volumes** under **Elastic Block Store**.
4. Choose the EBS volume you want to attach.
5. Click on **Actions** and select **Attach Volume**.
6. Select the EC2 instance to attach the volume to and specify the device name (e.g., `/dev/nvme1n1`).
7. Click **Attach**.

### 3. Format and Mount the EBS Volume
1. Connect to your EC2 instance running the database using SSH.
2. Stop the container running the database
3. Run the following command to list the available block devices:
```bash
lsblk
```

4. Identify the device name of the attached EBS volume (e.g., `/dev/xvdf`).
5. Format the EBS volume using the appropriate file system for your database (e.g., ext4):
```bash
sudo mkfs -t ext4 /dev/xvdf
```

6. Create a mount point for the EBS volume:
```bash
sudo mkdir -p /mnt/database
```

7. Mount the EBS volume to the mount point:
```bash
sudo mount /dev/xvdf /mnt/database
```

### 4. Persist the Mount on Reboot
1. Open the `/etc/fstab` file using a text editor:
```bash
sudo nano /etc/fstab
```

2. Add the following line to the file, replacing `/dev/xvdf` with the appropriate device name:
```bash 
/dev/xvdf /mnt/database ext4 defaults,nofail 0 2
```

3. Save and close the file.


### 5. Run the database again specifying the volume
NOTE: Using the mounted volume (/mnt/database) directly is not advisable for security reasons
1. Create a subdirectory within the mounted directory where EBS volume is connected to.
```bash
mkdir -p /mnt/database/database-data
```

### 6. Run the database container specifying the volume to be used
- You can run the database container specifying the volume ie the subdirectory created.
- Since the EBS volume is mounted to the */mnt/database/* anything within that directory will be persistent
```bash
docker run --name postgresql -e POSTGRES_DB=db-name -e POSTGRES_USER=db-user -e POSTGRES_PASSWORD=db-password -p 5432:5432 -v /path-to-sub-directory-created-above:/path-to-mount-point-in-container -d postgres:latest
```


## Verification
After completing the steps, verify the following:
- The EBS volume is attached to the EC2 instance and the mount point is visible in the file system.
- The database service starts correctly and can be accessed without any issues.
- After a reboot of the EC2 instance, the EBS volume is automatically mounted, and the database is accessible without any data loss.

By linking the EC2 instance to an EBS volume, you have ensured that the database data persists beyond the lifetime of the instance, resolving the issue of the database getting dropped on each instance restart.