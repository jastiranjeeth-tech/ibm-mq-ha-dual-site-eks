site_name          = "site-b"
aws_region         = "us-west-2"
cluster_name       = "mq-ha-site-b"
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

node_instance_type = "t3.medium"
node_desired_size  = 3
node_min_size      = 3
node_max_size      = 4

enable_spot_instances = false

mq_client_cidrs  = ["0.0.0.0/0"]
mq_console_cidrs = ["0.0.0.0/0"]

tags = {
  Owner = "learning-team"
  Site  = "site-b"
}
