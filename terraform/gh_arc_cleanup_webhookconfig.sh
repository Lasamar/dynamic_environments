#!/bin/bash

aws eks --region $1 update-kubeconfig --name $2

kubectl delete validatingwebhookconfiguration validating-webhook-configuration
kubectl delete mutatingwebhookconfiguration mutating-webhook-configuration
kubectl delete mutatingwebhookconfiguration actions-runner-controller-mutating-webhook-configuration
kubectl delete validatingwebhookconfiguration actions-runner-controller-validating-webhook-configuration
