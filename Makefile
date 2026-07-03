package:
	./scripts/package_lambda.sh

init:
	cd terraform && terraform init

plan: package
	cd terraform && terraform plan

apply: package
	cd terraform && terraform apply

destroy:
	cd terraform && terraform destroy
