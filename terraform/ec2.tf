data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "app" {
  key_name   = "${var.project}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.app.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    apt-get update
    apt-get install -y ca-certificates curl gnupg unzip
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker ubuntu
    systemctl enable --now docker

    # AWS CLI v2 (for ECR login + SSM parameter fetch)
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscli.zip
    unzip -q /tmp/awscli.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscli.zip

    # ECR docker credential helper — auto-refreshes auth tokens
    mkdir -p /home/ubuntu/.docker
    cat > /home/ubuntu/.docker/config.json <<'JSON'
    {
      "credHelpers": {
        "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com": "ecr-login"
      }
    }
    JSON
    chown -R ubuntu:ubuntu /home/ubuntu/.docker
    apt-get install -y amazon-ecr-credential-helper || {
      # Fallback: install the helper from Go binary release if distro package is missing
      curl -fsSL -o /usr/local/bin/docker-credential-ecr-login \
        https://amazon-ecr-credential-helper-releases.s3.us-east-2.amazonaws.com/0.9.0/linux-amd64/docker-credential-ecr-login
      chmod +x /usr/local/bin/docker-credential-ecr-login
    }
  EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
    encrypted   = true
  }

  tags = {
    Name    = "${var.project}-app"
    Project = var.project
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project}-app-eip"
    Project = var.project
  }
}
