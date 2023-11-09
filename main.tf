terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.19"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }

    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 0.1"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }

  required_version = "~> 1.5"

  #backend "s3" {
  #bucket  = "terraform-state-2021"
  #key     = "face-recognition/terraform.tfstate"
  #region  = var.aws_region
  #profile = "abdus"
  #}
}

variable "aws_profile" {
  type     = string
  default  = "abdus"
  nullable = false
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "tags" {
  type = map(string)
  default = {
    Name        = "face-rekog"
    Environment = "dev"
    CreatedBy   = "terraform"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "awscc" {
  region  = var.aws_region
  profile = var.aws_profile
}

resource "random_pet" "bucket_name" {
  prefix = "${var.aws_profile}-face-rekog"
  length = 2
}

resource "aws_s3_bucket" "face_bucket" {
  bucket        = random_pet.bucket_name.id
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.face_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket     = aws_s3_bucket.face_bucket.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.bucket_ownership]
}

resource "aws_iam_policy" "s3_policy" {
  name        = "s3-policy"
  description = "Policy for s3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:PutObject", "s3:GetObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.face_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "s3_policy_attachment" {
  name       = "s3-policy-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.s3_policy.arn
}

# 2. create a lambda function and deploy it
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "face-rekog"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.faceIndexHandler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 60
  memory_size      = 128
  publish          = true
  tags             = var.tags
  environment {
    variables = {
      REGION          = var.aws_region
      PROFILE         = var.aws_profile
      TABLE_NAME      = aws_dynamodb_table.face_table.name
      COLLECTION_NAME = awscc_rekognition_collection.face_collection.collection_id
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.face_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.face_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda.function_name}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_iam_policy" "dynamo_policy" {
  name        = "dynamo-policy"
  description = "Policy for dynamodb table"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
        Effect   = "Allow"
        Resource = "${aws_dynamodb_table.face_table.arn}"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy_attachment" "dynamo_policy_attachment" {
  name       = "dynamo-policy-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.dynamo_policy.arn
}

resource "aws_dynamodb_table" "face_table" {
  name             = "face-rekog"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "faceId"
  range_key        = "createdTimestamp"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  tags             = var.tags

  attribute {
    type = "S"
    name = "faceId"
  }

  attribute {
    type = "N"
    name = "createdTimestamp"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_iam_policy" "face_collection_policy" {
  name        = "face-collection-policy"
  description = "Policy for face collection"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["rekognition:IndexFaces"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy_attachment" "face_collection_policy_attachment" {
  name       = "face-collection-policy-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.face_collection_policy.arn
}

resource "awscc_rekognition_collection" "face_collection" {
  collection_id = "face-rekog"
}
