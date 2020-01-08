#!/bin/bash
IFS='
'

# ========================
# ====HELPER FUNCTIONS====
# ========================
# check if !string! is in array
containsElement () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# ==============
# ====CONFIG====
# ==============
PORTAINER_USER=${PORTAINER_USER:-"fallback"}
PORTAINER_PASSWORD=${PORTAINER_PASSWORD:-"fallback"}
PORTAINER_URL=${PORTAINER_URL:-"fallback"}
FOLDER=${FOLDER:-"fallback"}
ENVIRONMENT=${ENVIRONMENT:-"fallback"}
REPOSITORY_URL=${REPOSITORY_URL:-"fallback"}


# ======================
# ====CHECKUP STACKS====
# ======================

TOKEN_RESPONSE=$(curl -L -s -X POST -H "Content-Type: application/json;charset=UTF-8" -d "{\"username\":\"$PORTAINER_USER\",\"password\":\"$PORTAINER_PASSWORD\"}" "$PORTAINER_URL/api/auth")

if [[ ! $TOKEN_RESPONSE = *"jwt"* ]]; then
  exit 1
fi

TOKEN=$(echo $TOKEN_RESPONSE | awk -F '"' '{print $4}')

INFO=$(curl -L -s -H "Authorization: Bearer $TOKEN" "$PORTAINER_URL/api/endpoints/1/docker/info")
CID=$(echo "$INFO" | awk -F '"Cluster":{"ID":"' '{print $2}' | awk -F '"' '{print $1}')
STACKS=$(curl -L -s -H "Authorization: Bearer $TOKEN" "$PORTAINER_URL/api/stacks")
ALLOWED_STACKS=(stack1 stack2)
ALLOWED_SERVICES=(service1 service2)

exampleVariables=$(grep -v "^#\|^$" < .env.example | cut -d = -f 1 | sort)

for stack in $(echo "$STACKS" | jq -c '.[]')
do
  sid=$(echo $stack | jq ".Id")
  sid="${sid%\"}"
  sid="${sid#\"}"
  name=$(echo $stack | jq ".Name")
  name="${name%\"}"
  name="${name#\"}"

  if containsElement "$name" "${ALLOWED_STACKS[@]}"; then

      stackFile=$(curl -s \
                "$PORTAINER_URL/api/stacks/$sid/file" \
                -X GET \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json;charset=UTF-8" \
                      | jq '.StackFileContent' -r \
                      | ruby -r yaml -r json -e 'puts YAML.load($stdin.read).to_json')

      services=$(echo "$stackFile" | jq '.services' | jq 'keys')

      for service in $(echo "$services" | jq -c '.[]' | tr -d '"')
      do
          if containsElement "$service" "${ALLOWED_SERVICES[@]}"; then
              stackVariables=$(echo "$stackFile" \
                                   | jq ".services.$service.environment" \
                                   | jq -c '.[]' \
                                   | tr -d '"'\
                                   | cut -d = -f 1 \
                                   | sort)
              if [ "$stackVariables" = "$exampleVariables" ]; then
                  echo 'equal'
              else
                  echo "########################"
                  echo "########################"
                  echo "$service has differences"
                  echo "########################"
                  echo "########################"
                  diff --suppress-common-lines <( echo "$stackVariables" ) <( echo "$exampleVariables" ) | sed 's/</example variables are missing: /' | sed 's/>/stack variables are missing: /'
              fi
          fi
      done
  fi

done
