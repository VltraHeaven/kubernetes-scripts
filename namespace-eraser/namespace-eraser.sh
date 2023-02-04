#!/bin/bash 

################################################################################
#SCRIPT NAME    : namespace-eraser                                                                                           
#DESCRIPTION	: Scripted deletion of a Kubernetes namespaces and its resources                                                                               
#USAGE          : ./namespace-eraser <namespace>                                                                                          
#AUTHOR       	: Julio Hawthorne                                                
################################################################################

#Set options
shopt -s nocasematch


useage="USAGE: ./namespace-eraser <namespace>"

validate_namespace() {
    local namespace
    namespace="$(kubectl get ns "$1" --no-headers -oname | awk -F '/' '{print $2}')"
    case "$namespace" in
        "$1") echo "namespace/$namespace found";;
        *) exit 1;;
    esac
} 

discover_resources() {
    local namespace="$1"
    local discover_res 
    discover_res="$(kubectl api-resources --verbs=list --namespaced -o name\
        | xargs -I % sh -c "kubectl get --show-kind --ignore-not-found % -n $namespace -o name\
        | grep -i -v 'Warn'\
        | grep -i -v 'Deprecat'\
        | grep -i -v 'configmap/kube-root-ca'\
        | grep -i -v 'secret/default-token'\
        | grep -i -v 'configmap/istio-ca-root-cert'\
        | grep -i -v 'resourcequota/default'\
        | grep -i -v 'serviceaccount/default'\
        | grep -i -v 'event'\
        | grep -i -v 'ReplicaSet'\
        | grep -E -i -v '^pod/.*-[0-9A-Za-z]{10}-[0-9A-Za-z]{5}$'\
        | grep -E -i -v '^pod/.*-[0-9A-Za-z]{5}$'\
        | grep -E -i -v '^pod/.*-[0-9]{1}$'\
        | grep -i -v 'podmetrics.metrics.k8s.io'\
        | tee /dev/tty")"
    echo "$discover_res"
}

get_resource() {
    # Usage: get_resource <namespace> <kind/name> 
    local get_res
    get_res="$(kubectl get -n "$1" "$2" --no-headers -oname | awk '{print $1}')"
    echo "$get_res"
}

delete_resource() {
    # Usage: delete_resource <namespace> <kind/name> <--flags>
    local del_res
    local namespace

    del_res="$(get_resource "$1" "$2")"
    namespace="$1"

    if [ -n "$del_res" ]; then
        echo Deleting "$del_res"
        kubectl delete -n "$namespace" "$del_res" --timeout=10s
    fi
}

remove_finalizers() {
    # Usage: remove_finalizers <namespace>(optional) <kind/name>
    local finalizers
    if [ -n "$2" ]; then
        finalizers="$(kubectl get -n "$1" "$2" -o jsonpath='{.metadata.finalizers}')"
    else
        finalizers="$(kubectl get "$1" -o jsonpath='{.metadata.finalizers}')"
    fi
    if [ -n "$finalizers" ] && [ -n "$2" ]; then
        kubectl patch -n "$1" "$2" -p '{"metadata":{"finalizers":null}}' --type=merge
    elif [ -n "$finalizers" ]; then
        kubectl patch "$1" -p '{"metadata":{"finalizers":null}}' --type=merge
    fi
}

is_cluster_namespace() {
    local is_cluster_ns
    is_cluster_ns="$(kubectl get clusters.management.cattle.io "$1")"
    if [ -z "$is_cluster_ns" ]; then
        echo false
    else
        echo true
    fi
}

erase_namespace() {
    local namespace="$1"
    local resource_list="$2"
    while IFS= read -r line; do
        delete_resource "$namespace" "$line"
    done <<< "$resource_list"

    echo "Validating successful resource termination..."
    while IFS= read -r line; do
        r="$(get_resource "$namespace" "$line")"
        if [ -n "$r" ]; then
            local count=4
            while [ "$count" -gt 0 ]; do
                ((count--))
                echo "Deleting any discovered finalizers on $line..."
                remove_finalizers "$namespace" "$line"
                echo "Attempting forceful deletion of $line..."
                kubectl delete -n "$namespace" "$line" --force
                r="$(get_resource "$namespace" "$line")"
                if [ -z "$r" ]; then
                    count=0
                else
                    echo "Force delete of $line unsuccessful, $count attempts remaining..."
                fi
            done
            r="$(get_resource "$namespace" "$line")"
            if [ -n "$r" ]; then
                echo "$line deleted successfully"
            else
                echo "Deletion of $line unsuccessful, this may disrupt namespace deletion. Continuing..."
            fi
        else
            echo "$line deleted successfully"
        fi
    done <<< "$resource_list"

    echo "Checking if this is a cluster namespace..."
    if [ "$(is_cluster_namespace "$namespace")" = true ]; then
        local cluster_ns
        cluster_ns="clusters.management.cattle.io/$namespace"
        echo "Deleting $cluster_ns..."
        kubectl delete "$cluster_ns" --timeout=10s
        echo "Validating $cluster_ns deletion..."
        if [ "$(is_cluster_namespace "$namespace")" = true ]; then
            echo "Cluster deletion unsuccessful. Attempting finalizer removal..."
            remove_finalizers "$cluster_ns"
        fi
    fi

    echo "Deleting namespace/$namespace..."
    kubectl delete ns "$namespace" --force
    local validate_ns_delete
    validate_ns_delete="$(validate_namespace "$namespace")"
    if [ -n "$validate_ns_delete" ]; then
        echo "$namespace removal unsuccessful"
    else
        echo "$namespace removed successfully"
    fi
}

main() {
    local NS
    NS="$1"
    echo "Validating namespace..."
    validate_namespace "$NS"
    
    echo "Discovering resources in namespace/$NS, this may take some time..."
    local res
    res="$(discover_resources "$NS")"
    
    echo "Do you wish to delete namespace/$NS and it's discovered resources?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) erase_namespace "$NS" "$res"
                  exit 0;;
            No  ) exit 0;;
        esac
    done
}

case "$1" in
    "") printf 'Missing namespace arg \n%s\n' "$useage"
        exit 1;;
    *) main "$1";;
esac