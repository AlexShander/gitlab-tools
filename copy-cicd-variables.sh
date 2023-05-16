#!/bin/bash

declare -r GITLAB_SERVER=gitlab.com
# Enable the -u option to treat unset variables as errors
set -ue

for ARG in "$@"; do
  # Extract the key and value from the argument
  KEY=$(echo "$ARG" | cut -d= -f1)
  VALUE=$(echo "$ARG" | cut -d= -f2)
  # Set the key and value as environment variables
  export "$KEY"="$VALUE"
done

# Define a function to handle unset variables
handle_unset() {
  echo "Error: Variable unset or null. 
The list of mandatory variables:
  PRIVATE_TOKEN=aaacccc-vvvvvvv-hhhhhh
  SOURCE_PROJECT_ID=10000
  TARGET_PROJECT_ID=20000"
  exit 1
}

# Set the trap for the ERR signal
trap 'handle_unset' EXIT
# Set script variables from command line
PRIVATE_TOKEN=${PRIVATE_TOKEN}
SOURCE_PROJECT_ID=${SOURCE_PROJECT_ID}
TARGET_PROJECT_ID=${TARGET_PROJECT_ID}
trap '' EXIT

transfer_variables() {
  # Get the list of variables from the source project
  HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" \
                       --silent \
                       --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
                       --header 'Content-Type: application/json' \
                       --header 'Accept: application/json' \
                       "https://${GITLAB_SERVER}/api/v4/projects/$SOURCE_PROJECT_ID/variables")
  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  if [ ! $HTTP_STATUS -eq 200  ]; then
    echo "Error [HTTP status: $HTTP_STATUS]"
    exit 1
  fi
  # Loop through the variables and set them in the target project
  while read -r line; do
    VAR_KEY=$(echo "$line" | jq -r '.key')
    VAR_VALUE=$(echo "$line" | jq -r '.value')
    VAR_PROTECTED=$(echo "$line" | jq -r '.protected')
    VAR_MASKED=$(echo "$line" | jq -r '.masked')
    VAR_ENVIRONMENT_SCOPE=$(echo "$line" | jq -r '.environment_scope')
    VAR_VARIABLE_TYPE=$(echo "$line" | jq -r '.variable_type')
    set -x
    HTTP_PUSH_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" \
         --silent \
         --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
         --data-urlencode "key=$VAR_KEY" --data-urlencode "value=$VAR_VALUE" \
         --data-urlencode "protected=$VAR_PROTECTED" --data-urlencode "masked=$VAR_MASKED" \
         --data-urlencode "environment_scope=$VAR_ENVIRONMENT_SCOPE" --data-urlencode "variable_type=$VAR_VARIABLE_TYPE" \
         --request POST \
         "https://${GITLAB_SERVER}/api/v4/projects/$TARGET_PROJECT_ID/variables")
    HTTP_PUSH_BODY=$(echo $HTTP_PUSH_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
    HTTP_PUSH_STATUS=$(echo $HTTP_PUSH_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    if [ ! $HTTP_PUSH_STATUS -eq 201  ]; then
      echo "Error [HTTP status: $HTTP_PUSH_STATUS]"
      echo "Message: $HTTP_PUSH_BODY"
      exit 1
    fi
  done <<< "$(echo "$HTTP_BODY" | jq -c '.[]')"
}

transfer_variables
