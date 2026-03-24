variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "domain_name" {
  description = "Dominio raiz para o hosted zone (ex: exemplo.com)"
  type        = string
}

variable "comment" {
  description = "Comentario do hosted zone"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Permite destruir o hosted zone mesmo com records"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags globais"
  type        = map(string)
  default     = {}
}
