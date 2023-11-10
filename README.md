# Terraform AWS Face Recognition Infrastructure

When uploading images to S3 bucket, make sure to follow this folder structure.
The lambda function is configured to take the parent directory as individual's
name.

```
.
– individual-1-name/
-— 1.jpg
-— 2.jpg
-— 3.jpg
– individual-2-name/
-— 1.jpg
-— 2.jpg
-— 3.jpg
```

---

This Terraform code is designed to create an AWS infrastructure for a face
recognition application. It includes the setup of an S3 bucket, AWS Lambda
function, DynamoDB table, and AWS Rekognition collection. Below are the key
components and how they are configured:

## Prerequisites

Before using this Terraform code, make sure you have the following
prerequisites:

- AWS CLI installed and configured with the necessary credentials.
- Terraform CLI installed on your local machine.

## Usage

1. Clone the repository to your local machine.
2. Run `terraform init` to initialize the Terraform environment.
3. Customize variables to suit your requirements.
4. Run `terraform apply` to create the AWS infrastructure based on the specified configurations.

## Components

### AWS S3 Bucket

An S3 bucket is created with a unique name generated using the `random_pet`
resource. The bucket is configured with private access controls and Bucket
Ownership Controls with "BucketOwnerPreferred."

### AWS Lambda Function

A Lambda function is created, packaged as a ZIP file from the `lambda`
directory. The function has permissions to read/write to the S3 bucket, and its
execution is triggered by new S3 object creations. The Lambda function is
associated with an IAM role.

### DynamoDB Table

A DynamoDB table is created with a primary key and optional TTL (Time to Live)
for data expiration.

### AWS Rekognition Collection

An AWS Rekognition collection is created, allowing you to index faces for
recognition.

## Configuration

You can customize the following configuration options in `variables.tf`:

- `aws_profile`: The AWS CLI profile to use for authentication.
- `aws_region`: The AWS region where the resources will be created.
- `tags`: Tags to be applied to various resources for better organization.

## Cleanup

After you are done using the infrastructure, you can run `terraform destroy` to
remove all the created resources. Be cautious, as this will permanently delete
the configured resources.

For more details about the specific configurations and resource details, please
refer to the respective Terraform resource blocks in the code.

Please make sure you have reviewed and understood the Terraform code and its
implications before applying it to your AWS account.

ChatGPT2 / 2

Certainly! Here's a short README file for the provided Terraform code:
Face Recognition Infrastructure Deployment

This Terraform configuration automates the setup of an AWS infrastructure for
face recognition services.

## Required Providers:

1. Terraform Version: ~> 1.5
2. AWS: Source: hashicorp/aws (version: ~> 5.19)
3. Random: Source: hashicorp/random (version: ~> 3.5.1)
4. AWSCC: Source: hashicorp/awscc (version: ~> 0.1)
5. Archive: Source: hashicorp/archive (version: ~> 2.4.0)
