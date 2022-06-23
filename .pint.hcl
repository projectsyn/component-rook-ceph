parser {
  relaxed = [ "(.*)" ]
}

prometheus "appuio" {
  uri      = "http://proxy:9090"
  timeout  = "10s"
  required = true
}
