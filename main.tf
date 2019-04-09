# Define composite variables for resources
variable "id" {}
#variable "tags" {}

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
  replication_group_id          = "${var.replication_group_id == "" ? var.id : var.replication_group_id}"
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
