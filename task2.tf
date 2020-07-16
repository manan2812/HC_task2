provider "aws" {
  region = "us-east-1"
  profile = "default"
}

resource "tls_private_key" "task2-private-key" { 
  algorithm   = "RSA"
  rsa_bits = "2048"
}


resource "aws_key_pair" "task2-key" {
  depends_on = [ tls_private_key.task2-private-key, ]
  key_name   = "task2-key"
  public_key = tls_private_key.task2-private-key.public_key_openssh
}


resource "aws_security_group" "task2-sg" {
  depends_on = [ aws_key_pair.task2-key, ]
  name        = "task2-sg"
  description = "Allow SSH AND HTTP and NFS inbound traffic"
  vpc_id      = "vpc-debda2a4"


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }


  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
 ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "task2-sg"
  }
}




resource "aws_instance" "task2-os" {
   depends_on =  [ aws_key_pair.task2-key,
              aws_security_group.task2-sg, ] 
   ami                 = "ami-09d95fab7fff3776c"
   instance_type = "t2.micro"
   key_name       =  "task2-key"
   security_groups = [ "task2-sg" ]
     connection {
     type     = "ssh"
     user     = "ec2-user"
     private_key = tls_private_key.task2-private-key.private_key_pem
     host     = aws_instance.task2-os.public_ip
   }
   provisioner "remote-exec" {
    inline = [
       "sudo yum update -y",
      "sudo yum install httpd  php git -y ",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
      Name =  "task2-os"
           }
}


resource "aws_efs_file_system" "allow_nfs" {
 depends_on =  [ aws_security_group.task2-sg,
                aws_instance.task2-os,  ] 
  creation_token = "allow_nfs"


  tags = {
    Name = "allow_nfs"
  }
}

resource "aws_efs_mount_target" "alpha" {
 depends_on =  [ aws_efs_file_system.allow_nfs,
                         ] 
  file_system_id = aws_efs_file_system.allow_nfs.id
  subnet_id      = aws_instance.task2-os.subnet_id
  security_groups = ["${aws_security_group.task2-sg.id}"]
}


resource "null_resource" "null-remote-1"  {
 depends_on = [ 
               aws_efs_mount_target.alpha,
                  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task2-private-key.private_key_pem
    host     = aws_instance.task2-os.public_ip
  }
  provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.allow_nfs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.allow_nfs.dns_name}:/  /var/www/html",
        "sudo curl https://raw.githubusercontent.com/manan2812/HC_task2/master/index.html > index.html",                                  "sudo cp index.html  /var/www/html/",
      ]
  }
}

resource "aws_s3_bucket" "task2-s3" {
depends_on = [
    null_resource.null-remote-1,    
  ]     
  bucket = "task2-s3"
  force_destroy = true
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "MYBUCKETPOLICY",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::task2-s3/*"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_object" "task2-object" {
  depends_on = [ aws_s3_bucket.task2-s3,
                null_resource.null-remote-1,
               
 ]
     bucket = aws_s3_bucket.task2-s3.id
  key    = "one"
  source = "C:/Users/manan/Desktop/dog.jpeg"
  etag = "C:/Users/manan/Desktop/dog.jepg"
  acl = "public-read"
  content_type = "image/jpeg"
}


locals {
  s3_origin_id = "aws_s3_bucket.task2-s3.id"
}

resource "aws_cloudfront_origin_access_identity" "o" {
     comment = "this is oai"
 }


resource "aws_cloudfront_distribution" "task2-s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.task2-s3.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
           origin_access_identity = aws_cloudfront_origin_access_identity.o.cloudfront_access_identity_path 
     }
  }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "dog.jpeg"


  logging_config {
    include_cookies = false
    bucket          =  aws_s3_bucket.task2-s3.bucket_domain_name
    
  }






  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id


    forwarded_values {
      query_string = false


      cookies {
        forward = "none"
      }
    }


    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id


    forwarded_values {
      query_string = false
   


      cookies {
        forward = "none"
      }
    }


    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }


  price_class = "PriceClass_200"


  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "IN","CA", "GB", "DE"]
    }
  }


  tags = {
    Environment = "production"
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
output "out3" {
        value = aws_cloudfront_distribution.task2-s3_distribution.domain_name
}

