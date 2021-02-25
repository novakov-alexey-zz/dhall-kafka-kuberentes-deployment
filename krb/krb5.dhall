let k8s =
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.19/package.dhall sha256:6774616f7d9dd3b3fc6ebde2f2efcafabb4a1bf1a68c0671571850c1d138861f

let kdcRealm = env:REALM as Text

let kdcHost = env:KDC_HOST as Text

let krb5Conf =
      ''
      [libdefaults]
      default_realm = ${kdcRealm}
      default_ccache_name=FILE:/tmp/krb
      default_client_keytab_name=/krb5/client.keytab
      default_keytab_name=/krb5/krb5.keytab
      # default_tgs_enctypes = des3-hmac-sha1 des-cbc-crc des-cbc-md5 des3-cbc-sha1 aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 arcfour-hmac
      # default_tkt_enctypes = des3-hmac-sha1 des-cbc-crc des-cbc-md5 des3-cbc-sha1 aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 arcfour-hmac
      # permitted_enctypes = des3-hmac-sha1 des-cbc-crc des-cbc-md5 des3-cbc-sha1 aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 arcfour-hmac
      ignore_acceptor_hostname = true
      rdns = false

      [realms]
      ${kdcRealm} = {
        kdc = ${kdcHost}:88
        admin_server = ${kdcHost}:749
        kpasswd_server = ${kdcHost}:464
        #master_key_type = des3-hmac-sha1
        # supported_enctypes = aes256-cts:normal aes128-cts:normal
        kdc_ports = 88
        ignore_acceptor_hostname = true
        rdns = false
      }

      [domain_realm]
      .example.com = ${kdcRealm}
      example.com = ${kdcRealm}  

      [logging]
      default = STDERR 
      ''

in  k8s.ConfigMap::{
    , metadata = k8s.ObjectMeta::{ name = Some "krb5-conf" }
    , data = Some [ { mapKey = "krb5.conf", mapValue = krb5Conf } ]
    }
