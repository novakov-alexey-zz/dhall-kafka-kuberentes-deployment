# .ONESHELL:
# .SHELL := /bin/bash

args = `arg="$(filter-out $@,$(MAKECMDGOALS))" && echo $${arg:-${1}}`

export NAMESPACE=kafka

## Kafka
PLAIN_RELEASE=plain
KRB_RELEASE=krb
export REALM = "EXAMPLE.COM"
export KDC_HOST = "my-krb1"

create-namespace:
	kubectl create ns $(NAMESPACE) || exit 0

to-dhall:
	# yaml-to-dhall '(./krb/types.dhall).KrbServer' --file ./krb/my-krb-server-1.yaml	 
	yaml-to-dhall '(./krb/types.dhall).Principals' --file ./krb/my-principals-1.yaml	 

######################### Dev Kerberos for K8s ####################################################################
deploy-krb-operator:	
	wget -O- -q https://raw.githubusercontent.com/novakov-alexey/krb-operator/master/manifest/rbac.dhall | dhall-to-yaml | kubectl create -n $(NAMESPACE) -f -
	wget -O- -q https://raw.githubusercontent.com/novakov-alexey/krb-operator/master/manifest/kube-deployment.dhall | \
    	dhall-to-yaml | kubectl create -n $(NAMESPACE) -f -

undeploy-krb-operator:
	wget -O- -q https://raw.githubusercontent.com/novakov-alexey/krb-operator/master/manifest/rbac.dhall | \
 		dhall-to-yaml | kubectl delete -n $(NAMESPACE) -f -
	wget -O- -q https://raw.githubusercontent.com/novakov-alexey/krb-operator/master/manifest/kube-deployment.dhall | \
		dhall-to-yaml | kubectl delete -n $(NAMESPACE) -f -
	kubectl delete crd krbservers.krb-operator.novakov-alexey.github.io
	kubectl delete crd principalss.krb-operator.novakov-alexey.github.io

deploy-krb-instance:
	dhall-to-yaml --documents < ./krb/krb-instance.dhall | kubectl create -n $(NAMESPACE) -f -	

undeploy-krb-instance:
	dhall-to-yaml --documents < ./krb/krb-instance.dhall | kubectl delete -n $(NAMESPACE) -f -

#################### KAFKA Deployment Common ###################################################################### 
###################################################################################################################

kafka-broker-jks:
	kubectl delete secret kafka-broker-jks -n $(NAMESPACE) || exit 0
	kubectl create secret generic kafka-broker-jks \
      --from-file=kafka-keystore.jks=./kafka/secret/kafka.broker1.keystore.jks \
      --from-file=kafka-truststore.jks=./kafka/secret/kafka.broker1.truststore.jks \
      --from-file=credentials=./kafka/secret/dev-credentials.txt -n $(NAMESPACE)
kafka-client-jks:
	kubectl delete secret kafka-client-jks -n $(NAMESPACE) || exit 0 
	kubectl create secret generic kafka-client-jks \
	  --from-file=keystore.jks=./kafka/secret/kafka.producer.keystore.jks \
	  --from-file=truststore.jks=./kafka/secret/kafka.producer.truststore.jks -n $(NAMESPACE)
kafka-create-configs: kafka-broker-jks kafka-client-jks	
	dhall-to-yaml --documents < ./krb/krb5.dhall | kubectl create -n $(NAMESPACE) -f -
	dhall-to-yaml --documents < ./kafka/dhall/brokerConf.dhall | kubectl create -n $(NAMESPACE) -f -
kafka-delete-configs:	
	dhall-to-yaml --documents < ./krb/krb5.dhall | kubectl delete -n $(NAMESPACE) -f -
	dhall-to-yaml --documents < ./kafka/dhall/brokerConf.dhall | kubectl delete -n $(NAMESPACE) -f -
kafka-build-deps:
	cd kafka/helm/cp-kafka && helm dep update
	cd kafka/helm/cp-kafka && helm dep build
kafka-reset-configs: kafka-delete-configs kafka-create-configs		

##################### Security Option 1: SASL_SSL, SASL mechanism: PLAIN
#### Broker
deploy-kafka:
	helm install $(PLAIN_RELEASE) ./kafka/helm/cp-kafka --values ./kafka/helm/cp-kafka/sasl-plain-values.yaml -n $(NAMESPACE)
undeploy-kafka:
	helm del $(PLAIN_RELEASE) -n $(NAMESPACE) || exit 0
 	kubectl delete pvc -l release=$(PLAIN_RELEASE),app=cp-zookeeper -n $(NAMESPACE)
	kubectl delete pvc -l release=$(PLAIN_RELEASE),app=cp-kafka -n $(NAMESPACE)

#### Client
deploy-kafka-client:
	SASL_MECHANISM="<PLAIN|GSSAPI>.PLAIN" \
		dhall-to-yaml < ./kafka/dhall/clientPod.dhall | kubectl create -n $(NAMESPACE) -f -
undeploy-kafka-client:	
	SASL_MECHANISM="<PLAIN|GSSAPI>.PLAIN" \
		dhall-to-yaml < ./kafka/dhall/clientPod.dhall | kubectl delete -n $(NAMESPACE) -f -

#################### Security Option 2: SASL_SSL, SASL mechanism: GSSAPI
#### Broker
deploy-kafka-krb:	
	kubectl apply -f ./krb/krb5.yaml -n $(NAMESPACE) || echo 'krb5.conf already exists, ignoring'
	helm install $(KRB_RELEASE) ./kafka/helm/cp-kafka --values ./kafka/helm/cp-kafka/sasl-kerberos-values.yaml -n $(NAMESPACE)
undeploy-kafka-krb:
	helm del $(KRB_RELEASE) -n $(NAMESPACE)
	kubectl delete pvc -l release=$(KRB_RELEASE),app=cp-zookeeper -n $(NAMESPACE)
	kubectl delete pvc -l release=$(KRB_RELEASE),app=cp-kafka -n $(NAMESPACE)

#### Client
deploy-kafka-krb-client:
	SASL_MECHANISM="<PLAIN|GSSAPI>.GSSAPI" \
	HELM_RELEASE_NAME="$(KRB_RELEASE)" \
		dhall-to-yaml < ./kafka/dhall/clientPod.dhall | kubectl create -n $(NAMESPACE) -f -
undeploy-kafka-krb-client:	
	SASL_MECHANISM="<PLAIN|GSSAPI>.GSSAPI" \
	HELM_RELEASE_NAME=$(KRB_RELEASE) \
		dhall-to-yaml < ./kafka/dhall/clientPod.dhall | kubectl delete -n $(NAMESPACE) -f -
#################### KAFKA Deployment End ###################################################################### 

################ Kafka Schema Registry 

deploy-schema-registry:
	helm install dev-registry helm/cp-schema-registry -f ./kafka/helm/cp-schema-registry/values.yaml -n $(NAMESPACE)
undeploy-schema-registry:
	helm del dev-registry -n $(NAMESPACE)
