let kubernetes =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/package.dhall sha256:532e110f424ea8a9f960a13b2ca54779ddcac5d5aa531f86d82f41f8f18d7ef1

let namespace = env:NAMESPACE as Text ? "test"

let kdcRealm = env:REALM as Text ? "EXAMPLE.COM"

let adminUser = "admin"

let adminPassword = "admin-secret"

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
        username="${adminUser}"
        password="${adminPassword}";
      };
      ''

let helmReleaseName = env:HELM_RELEASE_NAME ? "krb"

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
        username="${adminUser}"
        password="${adminPassword}";
      };
      ''

let zkJaasConf =
      ''
      Server {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        user_super="zookeeper"
        user_${adminUser}="${adminPassword}";
      };
      ''

let plainKafkaCm =
      kubernetes.ConfigMap::{
      , metadata = kubernetes.ObjectMeta::{
        , name = Some "plain-kafka-jaas-configmap"
        }
      , data = Some [ { mapKey = "jaas.conf", mapValue = kafkaPlainJaasConf } ]
      }

let krbKafkaCm =
      kubernetes.ConfigMap::{
      , metadata = kubernetes.ObjectMeta::{
        , name = Some "krb-kafka-jaas-configmap"
        }
      , data = Some [ { mapKey = "jaas.conf", mapValue = kafkaGssApiJaasConf } ]
      }

let zkCm =
      kubernetes.ConfigMap::{
      , metadata = kubernetes.ObjectMeta::{ name = Some "zk-jaas-configmap" }
      , data = Some [ { mapKey = "jaas.conf", mapValue = zkJaasConf } ]
      }

in  [ plainKafkaCm, krbKafkaCm, zkCm ]
