# aws-infra-lab

AWS infrastructure lab — Terraform + ECS Fargate + RDS on AWS.

## Purpose

以補足「有證照但無 hands-on delivery 經驗」的落差為目的，產出可在面試中被逐行追問的技術作品。

## Architecture (Phase 1)

```
VPC (2 AZs)
├── Public Subnet  → ALB
└── Private Subnet → ECS Fargate + RDS PostgreSQL
```

Supporting services: IAM Role, Secrets Manager, CloudWatch, Security Groups

CI/CD: GitHub Actions → Terraform apply

## Project Structure

```
├── terraform/          # Infrastructure as Code
│   ├── environments/
│   │   └── dev/
│   └── modules/
├── app/                # FastAPI application
├── .github/
│   └── workflows/      # GitHub Actions CI/CD
└── docs/               # Architecture decisions & notes
```

## Phases

- **Phase 1**: VPC / ALB / ECS Fargate / RDS / Secrets Manager / CloudWatch / GitHub Actions
- **Phase 2**: EKS + Prometheus / Grafana
- **Phase 3**: DMS migration, microservices, AWS CDK, CodePipeline
