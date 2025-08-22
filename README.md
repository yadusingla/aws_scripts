# AWS Resource Auditor

This script audits AWS resources (EC2, RDS, and ElastiCache) for idle and underutilized instances and provides an estimated bill for the month.

## Prerequisites

- Ruby installed on your machine
- AWS SDK for Ruby (`aws-sdk-ec2`, `aws-sdk-rds`, `aws-sdk-cloudwatch`, `aws-sdk-pricing`, `aws-sdk-elasticache`)
- Terminal Table gem (`terminal-table`)

## Setup

1. Clone the repository:
   ```sh
   git clone <repository_url>
   cd <repository_directory>
   ```

2. Install the required gems:
   ```sh
   gem install aws-sdk-ec2 aws-sdk-rds aws-sdk-cloudwatch aws-sdk-pricing aws-sdk-elasticache terminal-table
   ```

3. Set up your AWS credentials as environment variables:
   ```sh
   export AWS_ACCESS_KEY_ID=your_access_key_id
   export AWS_ACCESS_SECRET_KEY=your_secret_access_key
   ```

## Usage

1. Run the script:
   ```sh
   ruby aws_bill_audit.rb
   ```

2. Follow the prompts to select the services you want to audit:
   - Enter `1` for EC2
   - Enter `2` for RDS
   - Enter `3` for ElastiCache
   - Leave empty for all services

## Output

The script will output a table with the following columns:
- ResourceID
- ResourceName
- ResourceFamily
- ResourceType
- ResourceCreationDate
- AvgCPUUtilization
- AvgMemoryUtilization
- InstanceLifecycle
- PricePerHour
- EstBillMonthTillDate
- EstBillForTheMonth
