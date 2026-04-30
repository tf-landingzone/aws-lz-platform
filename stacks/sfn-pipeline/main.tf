###############################################################################
# sfn-pipeline/main.tf
#
# Resources:
#   1. ECR repository for tf-executor image
#   2. CloudWatch log groups (SFN + ECS)
#   3. DynamoDB: lz-account-inventory (PK=account_id, 3 GSIs)
#   4. IAM roles: ecs-task-execution, ecs-task, sfn-exec
#   5. ECS cluster (Fargate) + task definition
#   6. VPC security group (egress-only 443)
#   7. Step Functions state machine (Distributed Map)
###############################################################################

locals {
  cluster_name       = "lz-account-pipeline"
  task_family        = "lz-tf-executor"
  state_machine_name = "lz-account-pipeline"
  ecr_repo_name      = "lz-tf-executor"
}

# ── 1. ECR repository ─────────────────────────────────────────────────────────
resource "aws_ecr_repository" "tf_executor" {
  name                 = local.ecr_repo_name
  image_tag_mutability = "MUTABLE" # "latest" tag updated by CI

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "tf_executor" {
  repository = aws_ecr_repository.tf_executor.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}

# ── 2. CloudWatch log groups ──────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.task_family}"
  retention_in_days = var.log_retention_days
}

# ── 3. DynamoDB: lz-account-inventory ────────────────────────────────────────
resource "aws_dynamodb_table" "account_inventory" {
  name         = var.inventory_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "account_id"

  attribute {
    name = "account_id"
    type = "S"
  }

  attribute {
    name = "environment"
    type = "S"
  }

  attribute {
    name = "ou"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "last_deployed_at"
    type = "S"
  }

  global_secondary_index {
    name            = "environment-index"
    hash_key        = "environment"
    range_key       = "account_id"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "ou-index"
    hash_key        = "ou"
    range_key       = "account_id"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "last_deployed_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.inventory_table_name
  }
}

# ── 4. IAM roles ──────────────────────────────────────────────────────────────

## 4a. ECS Task Execution Role (ECR pull + CW Logs)
resource "aws_iam_role" "ecs_task_execution" {
  name = "lz-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

## 4b. ECS Task Role (what runs inside the container)
resource "aws_iam_role" "ecs_task" {
  name = "lz-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        # Prevent confused-deputy attack
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "lz-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 — read policy map + write Terraform state
      {
        Sid    = "S3StateAndConfig"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject",
          "s3:ListBucket", "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      # DynamoDB — Terraform lock table + inventory table
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:UpdateItem", "dynamodb:DeleteItem",
          "dynamodb:Query", "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/acme-lz-terraform-locks",
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.inventory_table_name}",
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.inventory_table_name}/index/*"
        ]
      },
      # STS — assume AWSControlTowerExecution role in target accounts
      {
        Sid      = "AssumeControlTowerExecution"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/AWSControlTowerExecution"
      },
      # CloudWatch Logs — allow container to emit structured logs
      {
        Sid    = "CWLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      }
    ]
  })
}

## 4c. Step Functions Execution Role
resource "aws_iam_role" "sfn_exec" {
  name = "lz-sfn-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:*"
        }
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_exec_policy" {
  name = "lz-sfn-exec-policy"
  role = aws_iam_role.sfn_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECS — run Fargate tasks synchronously
      {
        Sid    = "RunFargate"
        Effect = "Allow"
        Action = [
          "ecs:RunTask", "ecs:StopTask",
          "ecs:DescribeTasks"
        ]
        Resource = [
          aws_ecs_task_definition.tf_executor.arn,
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task/${local.cluster_name}/*"
        ]
      },
      # ECS IAM PassRole (required for RunTask)
      {
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
        Condition = {
          StringLike = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      # Events — allow SFN to wait for ECS task completion
      {
        Sid    = "EventBridgeSync"
        Effect = "Allow"
        Action = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
      },
      # DynamoDB — RecordSuccess / RecordFailure steps
      {
        Sid    = "DynamoDBInventory"
        Effect = "Allow"
        Action = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.inventory_table_name}"
      },
      # S3 — read job manifest (ItemReader) + write results (ResultWriter)
      {
        Sid    = "S3JobManifest"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      # CloudWatch Logs — SFN execution logs
      {
        Sid    = "CWLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:CreateLogGroup",
          "logs:DescribeLogGroups", "logs:DescribeResourcePolicies",
          "logs:GetLogDelivery", "logs:ListLogDeliveries",
          "logs:PutLogEvents", "logs:PutResourcePolicy",
          "logs:UpdateLogDelivery", "logs:DeleteLogDelivery"
        ]
        Resource = "*"
      },
      # X-Ray (optional but recommended for tracing)
      {
        Sid    = "XRay"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      },
      # SNS — completion notification
      {
        Sid      = "SNSNotify"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn == "" ? "arn:aws:sns:*:*:*" : var.sns_topic_arn
      }
    ]
  })
}

# ── 5. ECS cluster + task definition ─────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}

resource "aws_ecs_task_definition" "tf_executor" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "tf-executor"
    image     = "${aws_ecr_repository.tf_executor.repository_url}:${var.ecr_image_tag}"
    essential = true

    # Environment — base config; account-specific values injected by SFN
    environment = [
      { name = "AWS_REGION",          value = var.region },
      { name = "TF_STATE_BUCKET",     value = var.tf_state_bucket },
      { name = "LZ_INVENTORY_TABLE",  value = var.inventory_table_name },
      { name = "TF_PLUGIN_CACHE_DIR", value = "/tmp/tf-plugin-cache" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "account"
        "awslogs-create-group"  = "false"
      }
    }
  }])

  lifecycle {
    # image tag is updated by CI; ignore to avoid spurious Terraform diffs
    ignore_changes = [container_definitions]
  }
}

# ── 6. Security group (egress only) ──────────────────────────────────────────
resource "aws_security_group" "tf_executor" {
  name        = "lz-tf-executor-egress"
  description = "Allow egress HTTPS only — tf-executor Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No ingress rules — Fargate tasks initiate all connections

  tags = { Name = "lz-tf-executor-egress" }
}

# ── 7. Step Functions state machine ──────────────────────────────────────────
locals {
  # Notify is an optional terminal step — only emitted when sns_topic_arn is set
  sfn_notify_state = var.sns_topic_arn == "" ? {} : {
    Notify = {
      Type     = "Task"
      Resource = "arn:aws:states:::sns:publish"
      Parameters = {
        TopicArn = var.sns_topic_arn
        "Message.$" = "States.Format('LZ pipeline complete. Execution: {}', $$.Execution.Name)"
        Subject  = "LZ Account Pipeline Complete"
      }
      End = true
    }
  }

  sfn_definition = {
    Comment        = "Landing Zone account provisioning pipeline — Distributed Map"
    StartAt        = "ProvisionAccounts"
    TimeoutSeconds = 86400 # 24 h safety ceiling

    States = merge({
      ProvisionAccounts = {
        Type = "Map"
        Label = "ProvisionAccounts"
        ItemProcessor = {
          ProcessorConfig = {
            Mode        = "DISTRIBUTED"
            ExecutionType = "STANDARD"
          }
          StartAt = "RunTfExecutor"
          States = {
            RunTfExecutor = {
              Type     = "Task"
              Resource = "arn:aws:states:::ecs:runTask.sync"
              Parameters = {
                LaunchType     = "FARGATE"
                Cluster        = aws_ecs_cluster.main.arn
                TaskDefinition = aws_ecs_task_definition.tf_executor.arn
                NetworkConfiguration = {
                  AwsvpcConfiguration = {
                    Subnets        = var.subnet_ids
                    SecurityGroups = [aws_security_group.tf_executor.id]
                    AssignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
                  }
                }
                Overrides = {
                  ContainerOverrides = [{
                    Name = "tf-executor"
                    Environment = [
                      { "Name" = "ACCOUNT_ID",   "Value.$" = "$.account_id" },
                      { "Name" = "ACCOUNT_NAME", "Value.$" = "$.account_name" },
                      { "Name" = "ENVIRONMENT",  "Value.$" = "$.environment" },
                      { "Name" = "OU",           "Value.$" = "$.ou" },
                      { "Name" = "PLAN_ONLY",    "Value.$" = "$.plan_only" }
                    ]
                  }]
                }
              }
              Retry = [{
                ErrorEquals  = ["ECS.AmazonECSException", "States.TaskFailed", "States.Timeout"]
                IntervalSeconds = 60
                MaxAttempts  = 3
                BackoffRate  = 2.0
                JitterStrategy = "FULL"
              }]
              Catch = [{
                ErrorEquals = ["States.ALL"]
                ResultPath  = "$.error"
                Next        = "RecordFailure"
              }]
              ResultPath = null
              Next       = "RecordSuccess"
            }

            RecordSuccess = {
              Type     = "Task"
              Resource = "arn:aws:states:::dynamodb:putItem"
              Parameters = {
                TableName = var.inventory_table_name
                Item = {
                  account_id       = { "S.$" = "$.account_id" }
                  account_name     = { "S.$" = "$.account_name" }
                  environment      = { "S.$" = "$.environment" }
                  ou               = { "S.$" = "$.ou" }
                  status           = { S = "provisioned" }
                  sfn_status       = { S = "succeeded" }
                  "last_deployed_at" = { "S.$" = "$$.Execution.StartTime" }
                  "execution_arn"  = { "S.$" = "$$.Execution.Id" }
                }
              }
              ResultPath = null
              End        = true
            }

            RecordFailure = {
              Type     = "Task"
              Resource = "arn:aws:states:::dynamodb:putItem"
              Parameters = {
                TableName = var.inventory_table_name
                Item = {
                  account_id   = { "S.$" = "$.account_id" }
                  account_name = { "S.$" = "$.account_name" }
                  environment  = { "S.$" = "$.environment" }
                  ou           = { "S.$" = "$.ou" }
                  status       = { S = "failed" }
                  sfn_status   = { S = "failed" }
                  "error_info" = { "S.$" = "States.JsonToString($.error)" }
                  "last_deployed_at" = { "S.$" = "$$.Execution.StartTime" }
                  "execution_arn"    = { "S.$" = "$$.Execution.Id" }
                }
              }
              ResultPath = null
              End        = true
            }
          }
        }

        ItemReader = {
          Resource  = "arn:aws:states:::s3:getObject"
          ReaderConfig = {
            InputType  = "JSON"
            JSONPath   = "$.accounts"
          }
          Parameters = {
            Bucket = var.tf_state_bucket
            "Key.$" = "$.job_manifest_key"
          }
        }

        MaxConcurrency              = var.sfn_max_concurrency
        ToleratedFailurePercentage  = var.tolerated_failure_percentage

        ResultWriter = {
          Resource = "arn:aws:states:::s3:putObject"
          Parameters = {
            Bucket  = var.tf_state_bucket
            "Prefix.$" = "States.Format('sfn-results/{}', $$.Execution.Name)"
          }
        }

        ResultPath = "$.map_result"
        Next       = var.sns_topic_arn == "" ? "Done" : "Notify"
      }

      Done = {
        Type = "Succeed"
      }
    }, local.sfn_notify_state)
  }
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.sfn_exec.arn
  type     = "STANDARD"

  definition = jsonencode(local.sfn_definition)

  logging_configuration {
    level                  = "ALL"
    include_execution_data = false
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
  }

  tracing_configuration {
    enabled = true
  }

  depends_on = [aws_cloudwatch_log_group.sfn]
}

# ── Data sources ──────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
