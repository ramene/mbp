#!/usr/bin/env bash
# exit on error
set -eo pipefail

echo "install helm"
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

# kubectl --namespace kube-system create sa tiller
kubectl create -f values/rbac-config.yaml

echo "create tiller namespace"
kubectl create namespace tiller
kubectl create serviceaccount tiller --namespace tiller
kubectl create -f values/role-tiller.yaml
kubectl create -f values/rolebinding-tiller.yaml

echo "preclean"
rm -f ca.* tiller.* helm.*

echo "set key values"
export SUBJECT="/C=US/ST=Washington/L=District of Columbia/O=appmaestro/OU=devops/CN=appmaestro.io"

echo "create certs"
openssl genrsa -out ca.key.pem 4096
openssl req -key ca.key.pem -new -x509 \
    -days 7300 -sha256 \
    -out ca.cert.pem \
    -extensions v3_ca \
    -subj "${SUBJECT}"
# one per tiller host
openssl genrsa -out tiller.key.pem 4096
# one PER user (in this case helm is the user)
openssl genrsa -out helm.key.pem 4096
# create certificates for each of the keys
openssl req \
    -key tiller.key.pem \
    -new \
    -sha256 \
    -out tiller.csr.pem \
    -subj "${SUBJECT}"
openssl req \
    -key helm.key.pem \
    -new \
    -sha256 \
    -out helm.csr.pem \
    -subj "${SUBJECT}"
# sign each of the CSRs with the CA cert
openssl x509 -req \
    -CA ca.cert.pem \
    -CAkey ca.key.pem \
    -CAcreateserial \
    -in tiller.csr.pem \
    -out tiller.cert.pem \
    -days 365
openssl x509 -req \
    -CA ca.cert.pem \
    -CAkey ca.key.pem \
    -CAcreateserial \
    -in helm.csr.pem \
    -out helm.cert.pem \
    -days 365

echo "initialize helm"
helm init \
    --tiller-tls \
    --tiller-tls-cert tiller.cert.pem \
    --tiller-tls-key tiller.key.pem \
    --tiller-tls-verify \
    --tls-ca-cert ca.cert.pem \
    --service-account tiller
helm repo update

echo "verify tiller deployment"
kubectl get deploy,svc tiller-deploy -n kube-system

echo "waiting for tiller pod to become available"
pod=$(kubectl get pod --namespace kube-system --selector="name=tiller" --output jsonpath='{.items[0].metadata.name}')
kubectl wait --for=condition=Ready pod/$pod --timeout=60s --namespace kube-system

echo "verify helm tls"
helm ls \
    --tls \
    --tls-ca-cert ca.cert.pem \
    --tls-cert helm.cert.pem \
    --tls-key helm.key.pem

echo "move certs"
# you move them so you don't need to include them with every call to helm
cp ca.cert.pem $(helm home)/ca.pem
cp helm.cert.pem $(helm home)/cert.pem
cp helm.key.pem $(helm home)/key.pem

echo "final verification of helm without specifying certs path"
helm ls --tls