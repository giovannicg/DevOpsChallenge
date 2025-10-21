# In this file put all the logic to crete the proper infraestructure
terraform {
    required_providers {
        # Add the provideres according to the challenges
        aws = {
            source  = "hashicorp/aws"
            version = "~> 6.0"
        }
    }
}

provider "aws" {
    region = var.region
    default_tags {
      tags = {
        ManagedBy = "Terraform"
        Environment = terraform.workspace
        Project = var.app_name
      }
    }
}
locals {
  env_suffix = terraform.workspace
}

# Add the resources relatedo to the provider
data "aws_caller_identity" "current" {}
#s3 bucket
resource "aws_s3_bucket" "app_bucket" {
    bucket = "${var.app_name}-app-${local.env_suffix}"
}
resource "aws_s3_bucket_public_access_block" "app_bucket_pab" {
    bucket = aws_s3_bucket.app_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}
resource "aws_s3_bucket" "log_bucket" {
    bucket = "${var.app_name}-log-${local.env_suffix}"
}
resource "aws_s3_bucket_public_access_block" "log_bucket_pab" {
    bucket = aws_s3_bucket.log_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "log_bucket_own" {
    bucket = aws_s3_bucket.log_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
resource "aws_s3_bucket_acl" "log_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.log_bucket_own]

  bucket = aws_s3_bucket.log_bucket.id
  acl    = "private"
}


#Cloudfront

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.app_name}-oac-${local.env_suffix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    depends_on = [ aws_s3_bucket_acl.log_bucket_acl ]
  origin {
    domain_name              = aws_s3_bucket.app_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "s3-${aws_s3_bucket.app_bucket.id}"
  }
  enabled             = true
  default_root_object = "index.html"
  price_class = "PriceClass_100"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-${aws_s3_bucket.app_bucket.id}"
    compress = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  logging_config {
    include_cookies = false
    bucket = aws_s3_bucket.log_bucket.bucket_domain_name
    prefix = "cdn-logs/"
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  custom_error_response {
    error_caching_min_ttl = 10
    error_code = 404
    response_code = 200
    response_page_path = "/index.html"
  }
   custom_error_response {
    error_caching_min_ttl = 10
    error_code = 403
    response_code = 200
    response_page_path = "/index.html"
  }
}

resource "aws_s3_bucket_policy" "app_policy" {
    bucket = aws_s3_bucket.app_bucket.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid = "AllowCloudFrontOAC"
                Effect = "Allow"
                Principal = {Service = "cloudfront.amazonaws.com"}
                Action = "s3:GetObject"
                Resource = "${aws_s3_bucket.app_bucket.arn}/*"
                Condition = {
                    StringEquals = {
                        "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
                    }
                }
            }
        ]
    })
  
}


output "domain-name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
output "id" {
  value = aws_cloudfront_distribution.s3_distribution.id
}