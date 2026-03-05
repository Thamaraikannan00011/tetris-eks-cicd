output "alb_arn" { 
    value = aws_lb.main.arn 
}

output "alb_dns_name" { 
    value = aws_lb.main.dns_name 
}

output "alb_zone_id" { 
    value = aws_lb.main.zone_id 
}

output "http_listener_arn" { 
    value = aws_lb_listener.http.arn 
}

output "default_tg_arn" { 
    value = aws_lb_target_group.default.arn 
}
