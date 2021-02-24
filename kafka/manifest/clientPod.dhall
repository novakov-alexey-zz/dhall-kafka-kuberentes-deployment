let kubernetes =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/package.dhall sha256:532e110f424ea8a9f960a13b2ca54779ddcac5d5aa531f86d82f41f8f18d7ef1

let k8s =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/typesUnion.dhall sha256:765d1b084fb57e29471622b85b9b43d65a5baef3427bc1bfbfdaaf1e40c8e813

let SaslMechanisms = ./kafka/manifest/saslMechanisms.dhall

let namespace = env:NAMESPACE as Text ? "test"

let saslMechanism
    : SaslMechanisms
    = env:SASL_MECHANISM ? PLAIN

let kdcRealm = env:REALM as Text ? "EXAMPLE.COM"

let jassUser = "kafkabroker"
let jaasPassword = "kafkabroker-secret"

let kafkaPath = "/etc/kafka"

let jaasPlainConf =
      ''
      KafkaClient {
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="${jassUser}"
        password="${jaasPassword}";
      };

      Client {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        username="${jassUser}"
        password="${jaasPassword}";
      };
      ''

let jaasGssApiConf =
      ''
      KafkaClient {
        com.sun.security.auth.module.Krb5LoginModule required
        useKeyTab=true
        keyTab="${kafkaPath}/keytabs/kafka-client.keytab"
        storeKey=true
        useTicketCache=false
        serviceName="kafka"
        principal="kafka-client@${kdcRealm}";
      };
      ''

let keystorePass = "confluent"

let ingoreIdentification = " "

let mechanism = merge { PLAIN = "PLAIN", GSSAPI = "GSSAPI" } saslMechanism

let id = merge { PLAIN = "plain", GSSAPI = "krb" } saslMechanism

let jaasConf =
      merge { PLAIN = jaasPlainConf, GSSAPI = jaasGssApiConf } saslMechanism

let clientProps =
      ''
      sasl.mechanism=${mechanism}
      sasl.kerberos.service.name=kafka
      security.protocol=SASL_SSL

      ssl.truststore.location=${kafkaPath}/secrets/truststore.jks
      ssl.truststore.password=${keystorePass}

      ssl.keystore.location=${kafkaPath}/secrets/keystore.jks
      ssl.keystore.password=${keystorePass}

      ssl.key.password=${keystorePass}
      ssl.endpoint.identification.algorithm=${ingoreIdentification}
      ''

let cmName = "${id}-kafka-client-conf"

let clientPropsFile = "client.properties"

let jaasConfFile = "jaas.conf"

let clientConfMap =
      kubernetes.ConfigMap::{
      , metadata = kubernetes.ObjectMeta::{ name = Some cmName }
      , data = Some
        [ { mapKey = jaasConfFile, mapValue = jaasConf }
        , { mapKey = clientPropsFile, mapValue = clientProps }
        ]
      }

let mountTo =
      λ(mountPath : Text) →
      λ(name : Text) →
      λ(path : Optional Text) →
        kubernetes.VolumeMount::{
        , mountPath
        , name
        , readOnly = Some True
        , subPath = path
        }

let mount =
      λ(name : Text) →
      λ(fileName : Text) →
      λ(path : Optional Text) →
        mountTo "${kafkaPath}/${fileName}" name path

let krbConfFile = "krb5.conf"

let producerFile = "producer.sh"

let consumerFile = "consumer.sh"

let helmReleaseName = env:HELM_RELEASE_NAME as Text ? "plain"

let testScriptVariables =
      ''
      export ZOOKEEPERS=${helmReleaseName}-cp-zookeeper:2181
      export KAFKAS=${helmReleaseName}-cp-kafka-0.${helmReleaseName}-cp-kafka-headless.${namespace}.svc.cluster.local:9092             
      export KAFKA_OPTS="-Djava.security.auth.login.config=${kafkaPath}/${jaasConfFile} -Dsun.security.krb5.debug=true -Djava.security.krb5.conf=/etc/${krbConfFile}"
      ''

let testTopic = "test-rep-one"

let producerScript =
      ''
      ${testScriptVariables}
      kafka-run-class org.apache.kafka.tools.ProducerPerformance --print-metrics \
        --topic ${testTopic} --num-records 6000000 --throughput 100000 --record-size 100 \
        --producer-props bootstrap.servers=$KAFKAS buffer.memory=67108864 batch.size=8196 \
        --producer.config ${kafkaPath}/${clientPropsFile}
      ''

let consumerScript =
      ''
      ${testScriptVariables}
      kafka-console-consumer --topic ${testTopic} --bootstrap-server $KAFKAS --consumer.config ${kafkaPath}/${clientPropsFile}
      ''

let scriptCmName = "${id}-kafka-client-script-conf"

let testScriptConfMap =
      kubernetes.ConfigMap::{
      , metadata = kubernetes.ObjectMeta::{ name = Some scriptCmName }
      , data = Some
        [ { mapKey = producerFile, mapValue = producerScript }
        , { mapKey = consumerFile, mapValue = consumerScript }
        ]
      }

let cmVolume =
      λ(name : Text) →
      λ(keyAndPath : Text) →
        kubernetes.ConfigMapVolumeSource::{
        , name = Some name
        , items = Some
          [ { key = keyAndPath, path = keyAndPath, mode = None Integer } ]
        }

let commonMounts =
      [ mount "jaas-conf" jaasConfFile (Some jaasConfFile)
      , mount "client-props" clientPropsFile (Some clientPropsFile)
      , mount "producer-script" producerFile (Some producerFile)
      , mount "consumer-script" consumerFile (Some consumerFile)
      , mount "client-jks" "secrets" (None Text)
      ]

let krbMounts =
      [ mount "client-keytab" "keytabs" (None Text)
      , mountTo "/etc/${krbConfFile}" "krb5-conf" (Some krbConfFile)
      ]

let podMounts =
      merge
        { PLAIN = commonMounts, GSSAPI = commonMounts # krbMounts }
        saslMechanism

let commonVolumes =
      [ kubernetes.Volume::{
        , name = "jaas-conf"
        , configMap = Some (cmVolume cmName jaasConfFile)
        }
      , kubernetes.Volume::{
        , name = "client-props"
        , configMap = Some (cmVolume cmName clientPropsFile)
        }
      , kubernetes.Volume::{
        , name = "producer-script"
        , configMap = Some (cmVolume scriptCmName producerFile)
        }
      , kubernetes.Volume::{
        , name = "consumer-script"
        , configMap = Some (cmVolume scriptCmName consumerFile)
        }
      , kubernetes.Volume::{
        , name = "client-jks"
        , secret = Some kubernetes.SecretVolumeSource::{
          , secretName = Some "kafka-client-jks"
          }
        }
      ]

let krbVolumes =
      [ kubernetes.Volume::{
        , name = "client-keytab"
        , secret = Some kubernetes.SecretVolumeSource::{
          , secretName = Some "kafka-client-keytab"
          }
        }
      , kubernetes.Volume::{
        , name = "krb5-conf"
        , configMap = Some (cmVolume "krb5-conf" krbConfFile)
        }
      ]

let podVolumes =
      merge
        { PLAIN = commonVolumes, GSSAPI = commonVolumes # krbVolumes }
        saslMechanism

let pod =
      kubernetes.Pod::{
      , metadata = kubernetes.ObjectMeta::{ name = Some "${id}-kafka-client" }
      , spec = Some kubernetes.PodSpec::{
        , containers =
          [ kubernetes.Container::{
            , name = "kafka-client"
            , image = Some "confluentinc/cp-kafka:5.5.0"
            , command = Some [ "sh", "-c", "exec tail -f /dev/null" ]
            , volumeMounts = Some podMounts
            }
          ]
        , volumes = Some podVolumes
        }
      }

in  { apiVersion = "v1"
    , kind = "List"
    , items =
      [ k8s.Pod pod
      , k8s.ConfigMap clientConfMap
      , k8s.ConfigMap testScriptConfMap
      ]
    }
