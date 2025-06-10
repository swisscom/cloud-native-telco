#!/bin/bash

# This script creates the specified number of kind clusters

set -e
# Define colors
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if number of clusters to create is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: Number of clusters to create not provided${NC}"
  echo "Usage: $0 <number_of_clusters> [clustername]"
  exit 1
fi

# Check if the first parameter is a number
re='^[0-9]+$'
if ! [[ $1 =~ $re ]] ; then
   echo -e "${RED}Error: '$1' is not a number${NC}" >&2; exit 1
fi

number_of_clusters=$1
clustername=${2:-dns}  # Set default cluster name to 'dns' if not provided
mkdir -p tmp

# Loop to create the specified number of clusters
for (( i=0; i<$number_of_clusters; i++ ))
do
  config_file="templates/cluster-cfg.yaml"
  temp_config="tmp/cluster-$i-cfg.yaml"

  if [ -f "$config_file" ]; then
    # Make a temporary copy of the configuration file
    cp "$config_file" "$temp_config"

    # Modify apiServerPort in the copied config file
    sed -i'' -e "s/apiServerPort: 6443/apiServerPort: $((6443 + i))/g" "$temp_config"
    rm "$temp_config"-e

    # check if cluster exists
    if kind get clusters | grep -q "^${clustername}-${i}$"; then
      echo "Cluster ${clustername}-${i} already exists. Skipping creation."
      continue
    fi
    kind create cluster --name $clustername-$i --config $temp_config || { echo -e "${RED}Error: Failed to create cluster ${clustername}-${i}${NC}"; rm -f "$temp_config"; exit 1; }

  else
    echo -e "${RED}Error: Configuration file $config_file not found${NC}"
    exit 1
  fi
done
