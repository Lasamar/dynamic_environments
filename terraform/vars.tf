variable "region" {
    type = string
    default = "eu-central-1"
}

variable "cluster_name" {
    type = string
    default = "minimal_demo"
}

variable "cluster_version" {
    type = string
    default = "1.23"
}

variable "repository" {
    type = string
}

variable "github_arc_token" {
    type = string
    description = "PAT to enable Action runner controller to create github token inside user/organisation repositories"
    sensitive = true
}


