# Kafka Security using Dhall

This example is using:

- [Confluent Helm charts](https://github.com/confluentinc/cp-helm-charts) for Kafka as base deployment. Helm charts are changed to support custom volumes in Statefulsets. Custom version is here: [kafka/helm](./kafka/helm)
- Dhall configuration for configmaps of Kafka broker and client pods

There are two security options configured in Helm charts and Dhall scripts:

- SASL_SSL, SASL mechanism: PLAIN
- SASL_SSL, SASL mechanism: GSSAPI

Required software:

- [dhall-to-yaml](https://docs.dhall-lang.org/tutorials/Getting-started_Generate-JSON-or-YAML.html#installation)
- kubectl
- helm 3.x
- GNU Make

## Common steps

Keytabs are coupled with Helm charts volumes (improvement is needed). You can create them manually as secrets or use Kerberos operator to start new 
Kerberos server inside K8s (not for production use obviously).

Start Kerberos operator:

```bash
make deploy-krb-operator
```

Create Kerberos instance and principals:

```bash
make deploy-krb-instance
```

Create configmaps

```bash
make kafka-create-configs
```

## Security Option 1: Install SASL_SSL, PLAIN

Install Kafka:

```bash
deploy-kafka
```

Install Kafka client pod for testing purpose:

```bash
make deploy-kafka-client
```

### Test deployment

Now exec to Client pod and run:

```bash
cd /etc/kafka
sh producer.sh
```

In another terminal window, exec to Client pod again and run:

```bash
cd /etc/kafka
sh consumer.sh
```

Expected result:
- producer script start to generate text data
- consumer script starts to consume that text data

## Security Option 2: Install SASL_SSL, GSSAPI

Install Kafka:

```bash
make deploy-kafka-krb
```

Install Kafka client pod for testing purpose:

```bash
make deploy-kafka-krb-client
```

### Test deployment

Test procedure from the above option 1 is applicable here as well.