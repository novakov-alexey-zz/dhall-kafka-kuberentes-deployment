let k8s =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.19/package.dhall sha256:6774616f7d9dd3b3fc6ebde2f2efcafabb4a1bf1a68c0671571850c1d138861f

let union =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.19/typesUnion.dhall sha256:827f0423034337f5a27b99cb30c56229fa8d35ea58d15a0f5a2d5de66bb86142

let kafka = ./kafka/dhall/types.dhall

let namespace = env:NAMESPACE as Text ? "kafka"

let saslMechanism
    : kafka.SaslMechanisms
    = env:SASL_MECHANISM ? PLAIN

let kdcRealm = env:REALM as Text

let jaasCreds
    : kafka.Credentials
    = { name = "kafkabroker", password = "kafkabroker-secret" }

let filePaths
    : kafka.FilePaths
    = { parentDir = "/etc/kafka"
      , clientProps = "client.properties"
      , jaasConf = "jaas.conf"
      , krbConf = "krb5.conf"
      , producerScript = "producer.sh"
      , consumerScript = "consumer.sh"
      }

let jaasPlainConf =
      ''
      KafkaClient {
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="${jaasCreds.name}"
        password="${jaasCreds.password}";
      };

      Client {
        org.apache.zookeeper.server.auth.DigestLoginModule required
        username="${jaasCreds.name}"
        password="${jaasCreds.password}";
      };
      ''

let jaasGssApiConf =
      ''
      KafkaClient {
        com.sun.security.auth.module.Krb5LoginModule required
        useKeyTab=true
        keyTab="${filePaths.parentDir}/keytabs/kafka-client.keytab"
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

      ssl.truststore.location=${filePaths.parentDir}/secrets/truststore.jks
      ssl.truststore.password=${keystorePass}

      ssl.keystore.location=${filePaths.parentDir}/secrets/keystore.jks
      ssl.keystore.password=${keystorePass}

      ssl.key.password=${keystorePass}
      ssl.endpoint.identification.algorithm=${ingoreIdentification}
      ''

let cmName = "${id}-kafka-client-conf"

let clientConfMap =
      k8s.ConfigMap::{
      , metadata = k8s.ObjectMeta::{ name = Some cmName }
      , data = Some
        [ { mapKey = filePaths.jaasConf, mapValue = jaasConf }
        , { mapKey = filePaths.clientProps, mapValue = clientProps }
        ]
      }

let mountTo =
      λ(mountPath : Text) →
      λ(name : Text) →
      λ(path : Optional Text) →
        k8s.VolumeMount::{
        , mountPath
        , name
        , readOnly = Some True
        , subPath = path
        }

let mount =
      λ(name : Text) →
      λ(fileName : Text) →
      λ(path : Optional Text) →
        mountTo "${filePaths.parentDir}/${fileName}" name path

let helmReleaseName = env:HELM_RELEASE_NAME as Text ? "plain"

let testScriptVariables =
      ''
      export ZOOKEEPERS=${helmReleaseName}-cp-zookeeper:2181
      export KAFKAS=${helmReleaseName}-cp-kafka-0.${helmReleaseName}-cp-kafka-headless.${namespace}.svc.cluster.local:9092             
      export KAFKA_OPTS="-Djava.security.auth.login.config=${filePaths.parentDir}/${filePaths.jaasConf} -Dsun.security.krb5.debug=true -Djava.security.krb5.conf=/etc/${filePaths.krbConf}"
      ''

let testTopic = "test-rep-one"

let producerScript =
      ''
      ${testScriptVariables}
      kafka-run-class org.apache.kafka.tools.ProducerPerformance --print-metrics \
        --topic ${testTopic} --num-records 6000000 --throughput 100000 --record-size 100 \
        --producer-props bootstrap.servers=$KAFKAS buffer.memory=67108864 batch.size=8196 \
        --producer.config ${filePaths.parentDir}/${filePaths.clientProps}
      ''

let consumerScript =
      ''
      ${testScriptVariables}
      kafka-console-consumer --topic ${testTopic} --bootstrap-server $KAFKAS --consumer.config ${filePaths.parentDir}/${filePaths.clientProps}
      ''

let scriptCmName = "${id}-kafka-client-script-conf"

let testScriptConfMap =
      k8s.ConfigMap::{
      , metadata = k8s.ObjectMeta::{ name = Some scriptCmName }
      , data = Some
        [ { mapKey = filePaths.producerScript, mapValue = producerScript }
        , { mapKey = filePaths.consumerScript, mapValue = consumerScript }
        ]
      }

let cmVolume =
      λ(name : Text) →
      λ(keyAndPath : Text) →
        k8s.ConfigMapVolumeSource::{
        , name = Some name
        , items = Some
          [ { key = keyAndPath, path = keyAndPath, mode = None Integer } ]
        }

let commonMounts =
      [ mount "jaas-conf" filePaths.jaasConf (Some filePaths.jaasConf)
      , mount "client-props" filePaths.clientProps (Some filePaths.clientProps)
      , mount
          "producer-script"
          filePaths.producerScript
          (Some filePaths.producerScript)
      , mount
          "consumer-script"
          filePaths.consumerScript
          (Some filePaths.consumerScript)
      , mount "client-jks" "secrets" (None Text)
      ]

let krbMounts =
      [ mount "client-keytab" "keytabs" (None Text)
      , mountTo "/etc/${filePaths.krbConf}" "krb5-conf" (Some filePaths.krbConf)
      ]

let podMounts =
      merge
        { PLAIN = commonMounts, GSSAPI = commonMounts # krbMounts }
        saslMechanism

let commonVolumes =
      [ k8s.Volume::{
        , name = "jaas-conf"
        , configMap = Some (cmVolume cmName filePaths.jaasConf)
        }
      , k8s.Volume::{
        , name = "client-props"
        , configMap = Some (cmVolume cmName filePaths.clientProps)
        }
      , k8s.Volume::{
        , name = "producer-script"
        , configMap = Some (cmVolume scriptCmName filePaths.producerScript)
        }
      , k8s.Volume::{
        , name = "consumer-script"
        , configMap = Some (cmVolume scriptCmName filePaths.consumerScript)
        }
      , k8s.Volume::{
        , name = "client-jks"
        , secret = Some k8s.SecretVolumeSource::{
          , secretName = Some "kafka-client-jks"
          }
        }
      ]

let krbVolumes =
      [ k8s.Volume::{
        , name = "client-keytab"
        , secret = Some k8s.SecretVolumeSource::{
          , secretName = Some "kafka-client-keytab"
          }
        }
      , k8s.Volume::{
        , name = "krb5-conf"
        , configMap = Some (cmVolume "krb5-conf" filePaths.krbConf)
        }
      ]

let podVolumes =
      merge
        { PLAIN = commonVolumes, GSSAPI = commonVolumes # krbVolumes }
        saslMechanism

let pod =
      k8s.Pod::{
      , metadata = k8s.ObjectMeta::{
        , name = Some "${id}-kafka-client"
        , labels = Some (toMap { app = "cp-kafka-client" })
        }
      , spec = Some k8s.PodSpec::{
        , containers =
          [ k8s.Container::{
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
      [ union.Pod pod
      , union.ConfigMap clientConfMap
      , union.ConfigMap testScriptConfMap
      ]
    }
