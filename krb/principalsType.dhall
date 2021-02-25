{ apiVersion : Text
, kind : Text
, metadata :
    ( https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.19/types.dhall
    ).ObjectMeta
, spec :
    { list :
        List
          { name : Text, keytab : Text, secret : { type : Text, name : Text } }
    }
}
