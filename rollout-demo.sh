#!/bin/bash

# LaunchDarkly Progressive Rollout Demo Script
# This script demonstrates a progressive rollout from 0% to 100% over 40 seconds
# Usage: ./rollout-demo.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Load from .env file
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please ensure your .env file exists with LD_API_TOKEN, LD_PROJECT_KEY, LD_ENVIRONMENT_KEY, and FLAG_KEY"
    exit 1
fi

# Check required environment variables
if [ -z "$LD_API_TOKEN" ] || [ -z "$LD_PROJECT_KEY" ] || [ -z "$LD_ENVIRONMENT_KEY" ] || [ -z "$FLAG_KEY" ]; then
    echo -e "${RED}Error: Missing required environment variables${NC}"
    echo "Please add the following to your .env file:"
    echo "LD_API_TOKEN=your_api_token_here"
    echo "LD_PROJECT_KEY=your_project_key_here (usually 'default')"
    echo "LD_ENVIRONMENT_KEY=your_environment_key_here (e.g., 'production', 'test')"
    echo "FLAG_KEY=your_flag_key_here"
    echo ""
    echo "You can find these values in your LaunchDarkly dashboard:"
    echo "- API Token: Account Settings > Authorization > Personal API tokens"
    echo "- Project Key: Projects > [Your Project] > Settings"
    echo "- Environment Key: Environments > [Your Environment] > Settings"
    echo "- Flag Key: Feature Flags > [Your Flag] > Settings"
    exit 1
fi

# LaunchDarkly API base URL
API_BASE="https://app.launchdarkly.com/api/v2"
FLAG_URL="$API_BASE/flags/$LD_PROJECT_KEY/$FLAG_KEY"

# Function to turn flag ON and set rollout percentage
turn_flag_on_and_set_percentage() {
    local percentage=$1
    local step_name=$2
    
    echo -e "${BLUE}Turning flag ON and setting rollout to ${percentage}% - ${step_name}${NC}"
    
    # First turn flag on
    local flag_on_payload=$(cat <<FLAGON_EOF
{
  "comment": "Demo rollout - ${step_name}",
  "environmentKey": "$LD_ENVIRONMENT_KEY",
  "instructions": [
    {
      "kind": "turnFlagOn"
    }
  ]
}
FLAGON_EOF
    )
    
    local flag_response=$(curl -s -w "%{http_code}" \
        -X PATCH \
        -H "Authorization: $LD_API_TOKEN" \
        -H "Content-Type: application/json; domain-model=launchdarkly.semanticpatch" \
        -d "$flag_on_payload" \
        "$FLAG_URL")
    
    local flag_http_code="${flag_response: -3}"
    
    if [ "$flag_http_code" -eq 200 ]; then
        echo -e "${GREEN}✓ Flag is now ON${NC}"
        
        # Now set the rollout percentage
        local rollout_payload=$(cat <<ROLLOUT_EOF
[
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/0/weight",
    "value": $((percentage * 1000))
  },
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/1/weight", 
    "value": $((100000 - percentage * 1000))
  }
]
ROLLOUT_EOF
        )
        
        local rollout_response=$(curl -s -w "%{http_code}" \
            -X PATCH \
            -H "Authorization: $LD_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$rollout_payload" \
            "$FLAG_URL")
        
        local rollout_http_code="${rollout_response: -3}"
        
        if [ "$rollout_http_code" -eq 200 ]; then
            echo -e "${GREEN}✓ Successfully set to ${percentage}%${NC}"
        else
            echo -e "${RED}✗ Failed to set rollout to ${percentage}%${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗ Failed to turn flag on${NC}"
        exit 1
    fi
}

# Function to update flag targeting (for subsequent rollout changes)
update_flag_targeting() {
    local percentage=$1
    local step_name=$2
    
    echo -e "${BLUE}Setting rollout to ${percentage}% - ${step_name}${NC}"
    
    # JSON payload for percentage rollout (using JSON Patch format)
    local json_payload=$(cat <<ROLLOUT_EOF
[
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/0/weight",
    "value": $((percentage * 1000))
  },
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/1/weight", 
    "value": $((100000 - percentage * 1000))
  }
]
ROLLOUT_EOF
    )
    
    # Make API call
    local response=$(curl -s -w "%{http_code}" \
        -X PATCH \
        -H "Authorization: $LD_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$FLAG_URL")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}✓ Successfully set to ${percentage}%${NC}"
    else
        echo -e "${RED}✗ Failed to update flag (HTTP $http_code)${NC}"
        echo "Response: $response_body"
        exit 1
    fi
}

# Function to turn flag off and set rollout to 0%
turn_flag_off_and_set_0_percent() {
    echo -e "${YELLOW}Turning flag OFF and setting rollout to 0%${NC}"
    
    # First turn flag off
    local json_payload=$(cat <<TURNOFF_EOF
{
  "comment": "Demo rollout - Starting at 0%",
  "environmentKey": "$LD_ENVIRONMENT_KEY",
  "instructions": [
    {
      "kind": "turnFlagOff"
    }
  ]
}
TURNOFF_EOF
    )
    
    local response=$(curl -s -w "%{http_code}" \
        -X PATCH \
        -H "Authorization: $LD_API_TOKEN" \
        -H "Content-Type: application/json; domain-model=launchdarkly.semanticpatch" \
        -d "$json_payload" \
        "$FLAG_URL")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}✓ Flag is now OFF${NC}"
        
        # Now set rollout to 0% (in case flag gets turned on later)
        local rollout_payload=$(cat <<ROLLOUT0_EOF
[
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/0/weight",
    "value": 0
  },
  {
    "op": "replace",
    "path": "/environments/$LD_ENVIRONMENT_KEY/fallthrough/rollout/variations/1/weight", 
    "value": 100000
  }
]
ROLLOUT0_EOF
        )
        
        local rollout_response=$(curl -s -w "%{http_code}" \
            -X PATCH \
            -H "Authorization: $LD_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$rollout_payload" \
            "$FLAG_URL")
        
        local rollout_http_code="${rollout_response: -3}"
        
        if [ "$rollout_http_code" -eq 200 ]; then
            echo -e "${GREEN}✓ Rollout set to 0%${NC}"
        else
            echo -e "${RED}✗ Failed to set rollout to 0%${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to turn flag off (HTTP $http_code)${NC}"
        echo "Response: $response_body"
        exit 1
    fi
}

# Main demo sequence
echo -e "${BLUE}🚀 Starting LaunchDarkly Progressive Rollout Demo${NC}"
echo -e "${BLUE}Flag: $FLAG_KEY${NC}"
echo -e "${BLUE}Project: $LD_PROJECT_KEY${NC}"
echo -e "${BLUE}Environment: $LD_ENVIRONMENT_KEY${NC}"
echo ""

# Step 0: Turn flag off and set rollout to 0%
turn_flag_off_and_set_0_percent
echo -e "${YELLOW}Waiting 5 seconds before starting rollout...${NC}"
sleep 5

# Step 1: Turn flag on and set to 25% rollout
turn_flag_on_and_set_percentage 25 "Initial rollout"
echo -e "${YELLOW}Waiting 10 seconds...${NC}"
sleep 10

# Step 2: 50% rollout
update_flag_targeting 50 "Expanding rollout"
echo -e "${YELLOW}Waiting 10 seconds...${NC}"
sleep 10

# Step 3: 75% rollout
update_flag_targeting 75 "Majority rollout"
echo -e "${YELLOW}Waiting 10 seconds...${NC}"
sleep 10

# Step 4: 100% rollout
update_flag_targeting 100 "Full rollout"

echo ""
echo -e "${GREEN}🎉 Progressive rollout demo complete!${NC}"
echo -e "${GREEN}Your image should now be fully visible at 100% rollout.${NC}"
echo ""
echo -e "${BLUE}Visit your visualization at: http://localhost:8080${NC}"
