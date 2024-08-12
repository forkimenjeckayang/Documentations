# Steps to Create an RDS Instance Running PostgreSQL

## Step 1: Log in to AWS Management Console
1. Open the AWS Management Console
2. Sign in with your credentials.

## Step 2: Navigate to RDS Service
1. In the AWS Management Console, type **RDS** in the search bar and select **RDS** from the list of services.

## Step 3: Create a Database
1. On the **Amazon RDS** dashboard, click **Create database**.

## Step 4: Choose a Database Creation Method
1. Select the **Standard Create** option for more configuration choices.

## Step 5: Select the Engine
1. In the **Engine options**, select **PostgreSQL**.

## Step 6: Choose a Version
1. Choose the desired PostgreSQL version from the drop-down menu.

## Step 7: Configure the Database Instance
1. **DB Instance Identifier**: Enter a unique name for your database.
2. **Master Username**: Enter a username for the master user.
3. **Master Password**: Enter a password and confirm it.

## Step 8: Choose Instance Size
1. In the **DB instance class** section, choose the instance size (e.g., `db.t3.micro` for a small instance).

## Step 9: Configure Storage
1. **Allocated Storage**: Set the desired storage size (e.g., 20 GB).
2. **Storage Autoscaling**: Enable or disable storage autoscaling as needed.

## Step 10: Configure Connectivity
1. **Virtual Private Cloud (VPC)**: Choose the VPC where the RDS instance will be deployed.
2. **Subnet Group**: Select the appropriate subnet group.
3. **Public Access**: Choose **Yes** if you want the RDS instance to be accessible publicly (not recommended for production).
4. **VPC Security Group**: Choose an existing security group or create a new one to allow inbound traffic on the PostgreSQL port (`5432`).

## Step 11: Additional Configuration
1. **Database Options**: Optionally, configure the database name, parameter group, option group, and backups.
2. **Encryption**: Enable encryption if required.
3. **Monitoring**: Enable enhanced monitoring if desired.

## Step 12: Review and Create
1. Review your settings.
2. Click **Create database** to launch the RDS instance.

## Step 13: Wait for the Instance to Launch
1. It may take several minutes for the instance to be created. The status will change to **Available** once it is ready.

## Step 14: Retrieve the Endpoint
1. After the instance is available, click on the instance name.
2. Note the **Endpoint** under the **Connectivity & security** tab. This endpoint will be used to connect your application to the PostgreSQL database.

## Using the AWS CLI
- You could also create your RDS instance via the aws CLI using the command below
```bash
aws rds create-db-instance \
    --db-instance-identifier mydbinstance \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --allocated-storage 20 \
    --master-username admin \
    --master-user-password password123 \
    --vpc-security-group-ids <your-security-group-id> \
    --availability-zone <your-availability-zone>

```
## Linking to ECS 
1. After creating the RDS with your chosen provider, you can go ahead to use the credentials of the RDS instance just created and link to your application directly or through env variables.
- Modify your ECS task definition by including the variables used and their values. For example:
  - DB_NAME: <your_db_name> (by default postgres)
  - DB_USERNAME: <your_db_username>
  - DB_HOST: <endpoint_url_of_rds_instance>
  - DB_PORT: <db_port>
  - DB_PASSWORD: <db_password>