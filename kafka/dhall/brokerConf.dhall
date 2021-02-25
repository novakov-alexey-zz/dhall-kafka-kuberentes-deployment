let k8s =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/package.dhall sha256:532e110f424ea8a9f960a13b2ca54779ddcac5d5aa531f86d82f41f8f18d7ef1

let kafka = ./kafka/manifest/types.dhall

let namespace = env:NAMESPACE as Text ? "kafka"

let kdcRealm = env:REALM as Text

let helmReleaseName = env:HELM_RELEASE_NAME ? "krb"

let adminCred
    : kafka.Credentials
    = { name = "admin", password = "admin-secret" }

let kafkaPlainJaasConf =
      ''
      KafkaServer {
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="kafkabroker"
        password="kafkabroker-secret"
        user_kafkabroker="kafkabroker-secret"  
        user_client="client-secret";
      };

      Client {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        username="${adminCred.name}"
        password="${adminCred.password}";
      };
      ''

let kafkaGssApiJaasConf =
      ''
      KafkaServer {
        com.sun.security.auth.module.Krb5LoginModule required
        useKeyTab=true
        storeKey=true
        keyTab="/etc/security/keytabs/kafka.keytab"
        principal="kafka/${helmReleaseName}-cp-kafka-0.${helmReleaseName}-cp-kafka-headless.${namespace}.svc.cluster.local@${kdcRealm}";
      };

      Client {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        username="${adminCred.name}"
        password="${adminCred.password}";
      };
      ''

let zkJaasConf =
      ''
      Server {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        user_super="zookeeper"
        user_${adminCred.name}="${adminCred.password}";
      };
      ''

let jaasFileName = "jaas.conf"

let plainKafkaCm =
      k8s.ConfigMap::{
      , metadata = k8s.ObjectMeta::{
        , name = Some "plain-kafka-jaas-configmap"
        }
      , data = Some [ { mapKey = jaasFileName, mapValue = kafkaPlainJaasConf } ]
      }

let krbKafkaCm =
      k8s.ConfigMap::{
      , metadata = k8s.ObjectMeta::{
        , name = Some "krb-kafka-jaas-configmap"
        }
      , data = Some
        [ { mapKey = jaasFileName, mapValue = kafkaGssApiJaasConf } ]
      }

let zkCm =
      k8s.ConfigMap::{
      , metadata = k8s.ObjectMeta::{ name = Some "zk-jaas-configmap" }
      , data = Some [ { mapKey = jaasFileName, mapValue = zkJaasConf } ]
      }

in  [ plainKafkaCm, krbKafkaCm, zkCm ]
