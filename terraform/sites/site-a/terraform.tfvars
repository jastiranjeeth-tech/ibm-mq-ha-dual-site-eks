site_name          = "site-a"
aws_region         = "us-east-1"
cluster_name       = "mq-ha-site-a"
vpc_cidr           = "10.10.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

node_instance_type = "t3.medium"
node_desired_size  = 3
node_min_size      = 3
node_max_size      = 4

enable_spot_instances = false

mq_client_cidrs  = ["0.0.0.0/0"]
mq_console_cidrs = ["0.0.0.0/0"]

tags = {
  Owner = "learning-team"
  Site  = "site-a"
}
