#!/bin/bash
#
# To Deploy Kafka
#  ./deploy.sh kafka
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

deploy_mongodb()
{
    printInfo "1. Deploy MongoDB template"
    
    oc create -f 05-ocs-mongodb-persistent-template.yaml -n openshift
    oc -n openshift get template mongodb-persistent-ocs

    printInfo "2. Create MongoDB app"
    oc new-app -n amq-streams --name=mongodb --template=mongodb-persistent-ocs \
        -e MONGODB_USER=demo \
        -e MONGODB_PASSWORD=demo \
        -e MONGODB_DATABASE=twitter_stream \
        -e MONGODB_ADMIN_PASSWORD=admin

    printInfo "3. Exec into MongoDB POD"

    printInfo "Now run the Following inside the MongoDB POD"
    echo "mongo -u demo -p demo twitter_stream"
    echo "db.redhat.insert({name:'Red Hat Enterprise Linux',product_name:'RHEL',type:'linux-x86_64',release_date:'05/08/2019',version:8})"
    echo "db.redhat.find().pretty()"
    echo "exit"

    oc -n amq-streams rsh $(oc get  po --selector app=mongodb -n amq-streams --no-headers | awk '{print $1}')

}

deploy_python_backend ()
{
    oc project amq-streams

    printInfo "1. Allow container to run as root"
    oc adm policy add-scc-to-user anyuid -z default


    printInfo "2. Deploy backend API APP"
    oc new-app --name=backend --docker-image=karansingh/kafka-demo-backend-service --env IS_KAFKA_SSL='False' --env MONGODB_ENDPOINT='mongodb:27017' --env KAFKA_BOOTSTRAP_ENDPOINT='cluster-kafka-bootstrap:9092' --env 'KAFKA_TOPIC=topic1' --env AYLIEN_APP_ID='YOUR_KEY_HERE' --env AYLIEN_APP_KEY='YOUR_KEY_HERE' --env TWTR_CONSUMER_KEY='YOUR_KEY_HERE' --env TWTR_CONSUMER_SECRET='YOUR_KEY_HERE' --env TWTR_ACCESS_TOKEN='YOUR_KEY_HERE' --env TWTR_ACCESS_TOKEN_SECRET='YOUR_KEY_HERE' --env MONGODB_HOST='mongodb' --env MONGODB_PORT=27017 --env MONGODB_USER='demo' --env MONGODB_PASSWORD='demo' --env MONGODB_DB_NAME='twitter_stream' -o yaml > 06-backend.yaml

    oc apply -f 06-backend.yaml ; oc expose svc/backend

    printInfo "3. watch the logs"

    # We need a bit of a wait here for the container to come up
    oc logs -f $(oc get po --selector app=backend --no-headers | awk '{print $1}')

}


deploy_frontend()
{
    oc project amq-streams

    printInfo "1.  Grab the backend route"

    oc get route backend --no-headers | awk '{print $2}'

    # Now instead of patching the code we should be using a generic container
    # And injecting the route

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
  mongodb)
        oc_login
        deploy_mongodb
        ;;
  python)
        oc_login
        deploy_python_backend 
        ;;
  delete|cleanup|remove)
        oc_login
        if projectExists amq-streams; then
            cleanup_kafka
        fi
        ;;
  *)
        echo "Usage: $N {setup|delete}" >&2
        exit 1
        ;;
esac

