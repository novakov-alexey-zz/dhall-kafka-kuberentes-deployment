{
    Credentials = { name : Text, password : Text },
    SaslMechanisms = < PLAIN | GSSAPI >,
    FilePaths = {
        parentDir: Text,
        clientProps: Text,
        jaasConf: Text,
        krbConf: Text,
        producerScript: Text,
        consumerScript: Text
    }
}