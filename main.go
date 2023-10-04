package main

import (
	"encoding/json"
	"flag"
	"net/http"
	"os"
	"path"
	"strings"

	"github.com/sirupsen/logrus"
)

func serveRegistry(urlPrefix, registryDir string) http.Handler {
	h := http.StripPrefix(urlPrefix, http.FileServer(http.Dir(registryDir)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		contentPath := registryDir + "/" + path.Clean(strings.TrimPrefix(r.URL.Path, urlPrefix))
		testPath := strings.Split(contentPath, "/")
		if testPath[len(testPath)-2] == "manifests" {
			if content, err := os.ReadFile(contentPath); err == nil {
				var decoded map[string]any
				if err = json.Unmarshal(content, &decoded); err == nil {
					if err = json.Unmarshal(content, &decoded); err == nil {
						w.Header().Set("Content-Type", decoded["mediaType"].(string))
					}
				}
			}
		} else {
			if requestContentType := r.Header.Get("Accept"); requestContentType != "" {
				w.Header().Set("Content-Type", requestContentType)
			} else {
				w.Header().Del("Content-Type")
			}
		}
		h.ServeHTTP(w, r)
		logrus.Infof("registry: %s %s", r.Method, r.RequestURI)
	})
}

func main() {
	port := flag.String("p", "9080", "port")
	directory := flag.String("d", "./", "registry directory")
	flag.Parse()

	registryURL := "/v2/"

	http.Handle(registryURL, serveRegistry(registryURL, *directory))

	logrus.Infof("Serving http://127.0.0.1:%s%s from %s\n", *port, registryURL, *directory)
	logrus.Fatal(http.ListenAndServe("127.0.0.1:"+*port, nil))
}
