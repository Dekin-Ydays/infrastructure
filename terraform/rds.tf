resource "random_password" "db" {
  length  = 24
  special = true
  # Avoid characters disallowed by RDS master password rules.
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name    = "${var.project}-db-subnets"
    Project = var.project
  }
}

resource "aws_db_instance" "main" {
  identifier              = "${var.project}-postgres"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  storage_type            = "gp2"
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  deletion_protection     = false

  tags = {
    Name    = "${var.project}-postgres"
    Project = var.project
  }
}

resource "aws_ssm_parameter" "db_credentials" {
  name = "/${var.project}/db/credentials"
  type = "SecureString"
  value = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    jdbc_url = "jdbc:postgresql://${aws_db_instance.main.endpoint}/${var.db_name}"
  })

  tags = {
    Project = var.project
  }
}
