#!/bin/bash

# This script deletes the specified number of kind clusters

set -e
# Define colors
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if number of clusters to delete is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: Number of clusters to delete not provided${NC}"
  echo "Usage: $0 <number_of_clusters> [clusternameprefix]"
  exit 1
fi

# Check if the first parameter is a number
re='^[0-9]+$'
if ! [[ $1 =~ $re ]] ; then
   echo -e "${RED}Error: '$1' is not a number${NC}" >&2; exit 1
fi

number_of_clusters=$1
clusternameprefix=${2:-dns}  # Set default cluster name to 'dns' if not provided

# Loop to delete the specified number of clusters
i=0
while [ $i -lt $number_of_clusters ]
do
  cluster_to_delete="${clusternameprefix}-$i"
  
  # Attempt to delete the cluster
  kind delete cluster --name $cluster_to_delete || { echo -e "${RED}Error: Failed to delete cluster ${cluster_to_delete}${NC}"; }
  
  echo "Successfully deleted cluster: $cluster_to_delete"
  ((i++))
done
