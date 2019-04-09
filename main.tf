# Define composite variables for resources
variable "id" {}

variable "tags" {
  type        = "map"
  description = "Additional tags (_e.g._ map(\"BusinessUnit\",\"ABC\")"
  default     = {}
}

variable "enabled" {
  description = "Set to false to prevent the module from creating any resources"
  default     = "true"
}

variable "security_groups" {
  type        = "list"
  default     = []
  description = "AWS security group ids"
}

variable "vpc_id" {
  default     = "REQUIRED"
  description = "AWS VPC id"
}

variable "subnets" {
  type        = "list"
  description = "AWS subnet ids"
  default     = []
}

variable "maintenance_window" {
  default     = "wed:03:00-wed:04:00"
  description = "Maintenance window"
}

variable "cluster_size" {
  default     = "1"
  description = "Count of nodes in cluster"
}

variable "port" {
  default     = "6379"
  description = "Redis port"
}

variable "instance_type" {
  default     = "cache.t2.micro"
  description = "Elastic cache instance type"
}

variable "family" {
  default     = "redis4.0"
  description = "Redis family "
}

variable "parameter" {
  type        = "list"
  default     = []
  description = "A list of Redis parameters to apply. Note that parameters may differ from one Redis family to another"
}

variable "engine_version" {
  default     = "4.0.10"
  description = "Redis engine version"
}

variable "at_rest_encryption_enabled" {
  default     = "false"
  description = "Enable encryption at rest"
}

variable "transit_encryption_enabled" {
  default     = "true"
  description = "Enable TLS"
}

variable "notification_topic_arn" {
  default     = ""
  description = "Notification topic arn"
}

variable "alarm_cpu_threshold_percent" {
  default     = "75"
  description = "CPU threshold alarm level"
}

variable "alarm_memory_threshold_bytes" {
  # 10MB
  default     = "10000000"
  description = "Ram threshold alarm level"
}

variable "alarm_actions" {
  type        = "list"
  description = "Alarm action list"
  default     = []
}

variable "ok_actions" {
  type        = "list"
  description = "The list of actions to execute when this alarm transitions into an OK state from any other state. Each action is specified as an Amazon Resource Number (ARN)"
  default     = []
}

variable "apply_immediately" {
  default     = "true"
  description = "Apply changes immediately"
}

variable "automatic_failover" {
  default     = "false"
  description = "Automatic failover (Not available for T1/T2 instances)"
}

variable "availability_zones" {
  type        = "list"
  description = "Availability zone ids"
  default     = []
}

variable "zone_id" {
  default     = ""
  description = "Route53 DNS Zone id"
}

variable "zone_name" {
  default     = ""
  description = "dns name / prefix, if this isn't set but zone_id is set name will be used"
}

variable "auth_token" {
  type        = "string"
  description = "Auth token for password protecting redis, transit_encryption_enabled must be set to 'true'! Password must be longer than 16 chars"
  default     = ""
}

variable "replication_group_id" {
  type        = "string"
  description = "Replication group ID with the following constraints: \nA name must contain from 1 to 20 alphanumeric characters or hyphens. \n The first character must be a letter. \n A name cannot end with a hyphen or contain two consecutive hyphens."
  default     = ""
}

#
# Security Group Resources
#
resource "aws_security_group" "default" {
  count  = "${var.enabled == "true" ? 1 : 0}"
  vpc_id = "${var.vpc_id}"
  name   = "${var.id}"

  ingress {
    from_port       = "${var.port}"              # Redis
    to_port         = "${var.port}"
    protocol        = "tcp"
    security_groups = ["${var.security_groups}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${var.tags}"
}

resource "aws_elasticache_subnet_group" "default" {
  count      = "${var.enabled == "true" ? 1 : 0}"
  name       = "${var.id}"
  subnet_ids = ["${var.subnets}"]
}

resource "aws_elasticache_parameter_group" "default" {
  count     = "${var.enabled == "true" ? 1 : 0}"
  name      = "${var.id}"
  family    = "${var.family}"
  parameter = "${var.parameter}"
}

resource "aws_elasticache_replication_group" "default" {
  count = "${var.enabled == "true" ? 1 : 0}"

  auth_token                    = "${var.auth_token}"
  replication_group_id          = "${substr("${var.id}", 0, min(length("${var.id}"), 20))}"
  replication_group_description = "${var.id}"
  node_type                     = "${var.instance_type}"
  number_cache_clusters         = "${var.cluster_size}"
  port                          = "${var.port}"
  parameter_group_name          = "${aws_elasticache_parameter_group.default.name}"
  availability_zones            = ["${slice(var.availability_zones, 0, var.cluster_size)}"]
  automatic_failover_enabled    = "${var.automatic_failover}"
  subnet_group_name             = "${aws_elasticache_subnet_group.default.name}"
  security_group_ids            = ["${aws_security_group.default.id}"]
  maintenance_window            = "${var.maintenance_window}"
  notification_topic_arn        = "${var.notification_topic_arn}"
  engine_version                = "${var.engine_version}"
  at_rest_encryption_enabled    = "${var.at_rest_encryption_enabled}"
  transit_encryption_enabled    = "${var.transit_encryption_enabled}"

  tags = "${var.tags}"
}

#
# CloudWatch Resources
#
resource "aws_cloudwatch_metric_alarm" "cache_cpu" {
  count               = "${var.enabled == "true" ? 1 : 0}"
  alarm_name          = "${var.id}-cpu-utilization"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"

  threshold = "${var.alarm_cpu_threshold_percent}"

  dimensions {
    CacheClusterId = "${var.id}"
  }

  alarm_actions = ["${var.alarm_actions}"]
  ok_actions    = ["${var.ok_actions}"]
  depends_on    = ["aws_elasticache_replication_group.default"]
}

resource "aws_cloudwatch_metric_alarm" "cache_memory" {
  count               = "${var.enabled == "true" ? 1 : 0}"
  alarm_name          = "${var.id}-freeable-memory"
  alarm_description   = "Redis cluster freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/ElastiCache"
  period              = "60"
  statistic           = "Average"

  threshold = "${var.alarm_memory_threshold_bytes}"

  dimensions {
    CacheClusterId = "${var.id}"
  }

  alarm_actions = ["${var.alarm_actions}"]
  ok_actions    = ["${var.ok_actions}"]
  depends_on    = ["aws_elasticache_replication_group.default"]
}
