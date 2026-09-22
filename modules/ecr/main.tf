data "aws_ecr_repositories" "existing" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Handle the case where no ECR repos exist yet in the AWS account.
  existing_repository_names = try(data.aws_ecr_repositories.existing.names, [])

  # Only create repos that don't already exist.
  new_repositories = setsubtract(
    toset(var.repositories),
    toset(local.existing_repository_names)
  )

  # Covers every repo in var.repositories, not just the ones this module created.
  repository_urls = {
    for name in var.repositories :
    name => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${name}"
  }
}

resource "aws_ecr_repository" "main" {
  for_each = local.new_repositories

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${var.project}-${each.value}"
    Env     = var.env
    Project = var.project
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = local.new_repositories
  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
