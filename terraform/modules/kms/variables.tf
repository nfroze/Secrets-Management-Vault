variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
