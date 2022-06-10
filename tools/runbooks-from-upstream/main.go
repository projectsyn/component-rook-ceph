package main

import (
	_ "embed"
	"os"
	"path/filepath"
	"text/template"

	monitoringv1 "github.com/prometheus-operator/prometheus-operator/pkg/apis/monitoring/v1"
	"sigs.k8s.io/yaml"
)

//go:embed runbook.adoc.gotmpl
var rawTemplate string

var tmpl = template.Must(template.New("").Parse(rawTemplate))

func main() {
	input := os.Args[1]
	outputDir := os.Args[2]

	r, err := unmarshalPrometheusRuleFile(input)
	if err != nil {
		panic(err)
	}

	for _, g := range r.Spec.Groups {
		for _, r := range g.Rules {
			err := renderRunbook(outputDir, r)
			if err != nil {
				panic(err)
			}
		}
	}
}

func renderRunbook(outputDir string, rule monitoringv1.Rule) error {
	file, err := os.OpenFile(filepath.Join(outputDir, rule.Alert+".adoc"), os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0666)
	if err != nil {
		return err
	}
	defer file.Close()
	err = tmpl.Execute(file, struct{ Rule monitoringv1.Rule }{rule})
	if err != nil {
		return err
	}
	return nil
}

func unmarshalPrometheusRuleFile(filePath string) (monitoringv1.PrometheusRule, error) {
	var data monitoringv1.PrometheusRule

	raw, err := os.ReadFile(filePath)
	if err != nil {
		return data, err
	}
	return data, yaml.Unmarshal(raw, &data)
}
