let k8s =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.19/package.dhall sha256:6774616f7d9dd3b3fc6ebde2f2efcafabb4a1bf1a68c0671571850c1d138861f

let union = ./krb/typesUnion.dhall
let KrbServer = ./krb/krbServerType.dhall
let Principals = ./krb/principalsType.dhall

let myKrb
    : KrbServer
    = { apiVersion = "krb-operator.novakov-alexey.github.io/v1"
      , kind = "KrbServer"
      , metadata = k8s.ObjectMeta::{ name = Some "my-krb1" }
      , spec.realm = "EXAMPLE.COM"
      }

let myPrincipals
    : Principals
    = { apiVersion = "krb-operator.novakov-alexey.github.io/v1"
      , kind = "Principals"
      , metadata = k8s.ObjectMeta::{
        , labels = Some
            ( toMap
                { `krb-operator.novakov-alexey.github.io/server` = "my-krb1" }
            )
        , name = Some "my-krb1"
        }
      , spec.list
        =
        [ { keytab = "kafka.keytab"
          , name =
              "kafka/krb-cp-kafka-0.krb-cp-kafka-headless.kafka.svc.cluster.local"
          , secret = { name = "kafka-keytab", type = "Keytab" }
          }
        , { keytab = "kafka.keytab"
          , name =
              "kafka/plain-cp-kafka-0.plain-cp-kafka-headless.kafka.svc.cluster.local"
          , secret = { name = "kafka-keytab", type = "Keytab" }
          }
        , { keytab = "kafka-client.keytab"
          , name = "kafka-client"
          , secret = { name = "kafka-client-keytab", type = "Keytab" }
          }
        ]
      }

in  { apiVersion = "v1"
    , kind = "List"
    , items =
      [ union.KrbServer myKrb
      , union.Principals myPrincipals      
      ]
    }
