#!/bin/sh
[ -e k8s.key ] || openssl genrsa -out k8s.key 2048
openssl req -x509 -new -nodes -key k8s.key -subj "/CN=127.0.0.1" -days 3650 -out k8s.crt -config openssl.conf -extensions v3_ext
chmod 0640 k8s.key
chmod 0644 k8s.crt
