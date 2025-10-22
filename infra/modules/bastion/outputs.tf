output "instance_id" {
  description = "ID of the bastion instance"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "private_ip" {
  description = "Private IP address of the bastion host"
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "Security group ID of the bastion host"
  value       = var.bastion_sg_id
}

output "iam_role_arn" {
  description = "IAM role ARN of the bastion host"
  value       = aws_iam_role.bastion.arn
}

output "ssh_command" {
  description = "SSH command to connect to bastion (if key provided)"
  value       = var.key_name != "" ? "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.bastion.public_ip}" : "Use AWS Systems Manager Session Manager: aws ssm start-session --target ${aws_instance.bastion.id}"
}

output "ssm_command" {
  description = "AWS Systems Manager command to connect (no SSH key needed)"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

