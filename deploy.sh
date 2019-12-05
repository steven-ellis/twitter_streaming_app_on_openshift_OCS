#!/bin/bash
#


# Step 0 - Our master environment
source ../apac_rh_forum_19/ocp.env
source ../apac_rh_forum_19/functions


deploy_kafka()
{
    printInfo "Create the amq-streams namespace"
    oc new-project amq-streams

    watch "echo 'Install AMQ Stream operator from console'; oc get all,csv"


    printInfo "Confirm no PV,PVC"
    oc get pv,pvc

    printInfo "Create Kafka Cluster"
    oc apply -f 01-kafka-cluster.yaml
    watch oc get all



    printInfo "Deploy Prometheus and Grafana"

    oc apply -f 02-prometheus.yaml
    oc apply -f 03-grafana.yaml
    watch oc get all

    printInfo "Verify PV,PVC provisioned by OCS"

    oc get pvc -n amq-streams
    oc get pv -o json | jq -r '.items | sort_by(.spec.capacity.storage)[]| select(.spec.claimRef.namespace=="amq-streams") | [.spec.claimRef.name,.spec.capacity.storage] | @tsv'

    printInfo "Add prometheus as grafana's data source and Kafka/Zookeeper dashboards"
    ./04-grafana-datasource.sh

    printInfo "Grab Grafana URL"

    oc get route grafana-route --no-headers | awk '{print $2}'

}

cleanup_kafka()
{
    printInfo "Need to clean up our Kafka environment"
    
    oc delete project amq-streams

}


case "$1" in
  kafka)
        oc_login
        if projectExists amq-streams; then
	    printWarning "Project amq-streams already deployed - Exiting"
        else
            deploy_kafka
        fi
        ;;
  delete|cleanup|remove)
        oc_login
        if projectExists amq-streams then
            cleanup_kafka
        fi
        ;;
  *)
        echo "Usage: $N {setup|delete}" >&2
        exit 1
        ;;
esac

