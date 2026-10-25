# infra/ (Shaurya)

All Terraform for SentimentOps, region `ap-south-1`. Manik owns `modules/pipeline/`.

## Modules

| Module | Creates |
|---|---|
| `storage` | Model/data bucket (private) and frontend website bucket (public read). Versioning on, `force_destroy` so destroy works |
| `registry` | ECR repo `sentimentops-dev-app`, keep-last-10 lifecycle rule, Lambda pull policy |
| `database` | DynamoDB `sentimentops-dev-predictions`: on-demand, key `request_id`, TTL on `expires_at` |
| `iam` | Lambda exec role: `dynamodb:PutItem` on the table + log writes on its log group only |
| `monitoring` | Log group (14 days), alarms on Lambda `Errors` and API `5xx`, optional SNS email |
| `serving` | Lambda from image, HTTP API (`POST /predict`, `GET /health`), CORS, env vars per contract |

## First-time setup (once, by one person)

```bash
aws configure --profile sentimentops        # your own IAM user, MFA
export AWS_PROFILE=sentimentops

./bootstrap/bootstrap.sh you@example.com 5  # state bucket + lock table + $5 budget alert
terraform init -backend-config=backend.hcl

# Lambda needs an image to exist before it can be created:
terraform apply -target=module.registry
./scripts/push_placeholder.sh               # needs Docker
terraform apply
```

Optional: `-var alarm_email=you@example.com` to get alarm emails.

## Everyday

```bash
terraform fmt -recursive && terraform validate
terraform plan
terraform apply
terraform output
```

## Destroy / rebuild proof (rule 11 and Gate 2)

```bash
terraform destroy
terraform apply -target=module.registry
./scripts/push_placeholder.sh
terraform apply
```
State bucket and lock table are *not* managed by Terraform, so they survive destroy.

## Notes

- `image_uri` has `ignore_changes`: after creation the deploy pipeline owns the running image, so `terraform apply` never rolls back a deployment.
- `pipeline.tf` is commented out. Uncomment when Manik's module merges to expose `state_machine_arn` and `github_actions_role_arn`.
- Bucket names carry the AWS account id for global uniqueness.
- The frontend site is HTTP (S3 website endpoint), which is fine for the course demo. CloudFront would add HTTPS if needed.
- Outputs match contract section 7. Extras: `frontend_website_url`, `model_bucket_name`, `predictions_table_name`.
