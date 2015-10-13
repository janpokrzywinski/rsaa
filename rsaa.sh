#!/bin/bash
#
#    Bash script for Rackspace Cloud API authentication.
#    Version 1.3.4
#    Jan Pokrzywinski
#

# Authentication endpoint
AUTHURL=https://identity.api.rackspacecloud.com/v2.0/

# Set file where the auth details are stored
AUTHFILE=~/.rsaa.conf

# Function that checks for available parsers
select_parser ()
{
check_python_module=$(python -c 'import json.tool' 2>&1)
if [ -z "$check_python_module" ]; then
   parser="python"
elif [ -f /usr/bin/jq ]; then
   parser="jq"
else
   echo -e "ERROR! No parser available!\nThis script requires either python module json.tool or jq\nFor jq visit http://stedolan.github.io/jq/"
    print_help
    exit 1
fi
}


# Main authentication function. Stores plain JSON response in the AUTH variable
authenticate () 
{
    AUTH=$(curl -sX POST $AUTHURL/tokens -d '{"auth":{ "RAX-KSKEY:apiKeyCredentials":{ "username":"'$USERNAME'", "apiKey":"'$APIKEY'" } } }' -H "Content-type: application/json")
    ERROR_MSG='Username or api key is invalid.'
    # verify if the response does not indicate incorrect authentication details.
    ERROR_CHECK=$(echo $AUTH | grep "$ERROR_MSG")
    if [ -n "$ERROR_CHECK" ]
    then
        echo "ERROR: Incorrect authentication details, wrong username or password."
        exit 1
    fi
}


# Function to print message for help

print_help ()
{
    echo -e """Usage: $0 [OPTIONS] -u Login-Name -p API-Key
  or : $0 [OPTIONS] -f

  -u, --user\t\t\tUsername
  -p, -k, --key\t\t\tAPI Key
  -t, --token\t\t\tRespond just with API Token
  -i, --me\t\t\tLoad credentials from $AUTHFILE file
  -v, --verbose, --full, -f\tDisplay plain JSON response

To use the credentials from the file create it as a plain text in $AUTHFILE
It should only contain two lines of text in format:
Username
APIKey
            """
}


# Function to print bare output without any data manipulation
print_full ()
{
    echo $AUTH
}


# Function to print just the API Token
print_token ()
{
    if [[ $parser == 'python' ]]
    then
        TOKEN=$(echo $AUTH | python -mjson.tool | grep -A5 token | grep id | cut -d '"' -f4)
    elif [[ $parser == 'jq' ]]
    then
        TOKEN=$(echo $AUTH | jq '.access.token.id' | tr -d '"')
    fi
    echo $TOKEN
}


# Function to print output for Endpoints, Token and sample curl command
print_nice ()
{
# first obtain some specific information by parsing the AUTH variable
    if [[ $parser == 'python' ]]
    then
        TOKEN=$(echo $AUTH | python -mjson.tool | grep -A5 token | grep id | cut -d '"' -f4)
        TOKEN_EXPIRES=$(echo $AUTH | python -mjson.tool | grep expires | cut -d '"' -f4 | sed 's/T/ /g' | cut -c1-19)
        DEFAULT_REG=$(echo $AUTH | python -mjson.tool | grep defaultRegion | cut -d '"' -f4)
        ACCOUNT_NUMBER=$(echo $AUTH | python -mjson.tool | grep -A1 'tenant"' | grep id | cut -d '"' -f4)
    elif [[ $parser == 'jq' ]]
    then
        TOKEN=$(echo $AUTH | jq '.access.token.id' | tr -d '"')
        TOKEN_EXPIRES=$(echo $AUTH | jq . | grep expires | cut -d '"' -f4 | sed 's/T/ /g' | cut -c1-19)
        DEFAULT_REG=$(echo $AUTH | jq '.access.user' | grep defaultRegion | cut -d '"' -f4)
        ACCOUNT_NUMBER=$(echo $AUTH | jq '.access.token.tenant' | grep id | cut -d '"' -f4)
    fi
# get to pretty printing
    printf "\n\e[1;36m----------- Info ------------\e[0m\n"
    printf "Parser used: $parser\nDDI: $ACCOUNT_NUMBER\nDefault Region: $DEFAULT_REG\nAuth URL:\n$AUTHURL\n"
    printf "\n\e[1;36m--------- Endpoints ---------\e[0m\n"
    if [[ $parser == 'python' ]]
    then
        echo $AUTH | python -mjson.tool | grep "URL"| cut -d '"' -f4
    elif [[ $parser == 'jq' ]]    
    then
        echo $AUTH | jq '.access.serviceCatalog' | grep "URL"| cut -d '"' -f4
    fi    
    printf "\n\e[1;36m--------- API Token ---------\e[0m\nTOKEN=$TOKEN\nToken expires: $TOKEN_EXPIRES\n\n"
    printf "\e[1;36m--- Example curl requests ---\e[0m\n"
    echo "See https://docs.rackspace.com for full specification, add endpoint URL at the end of each request"
    echo "- Generic silent request:"
    echo 'curl -s -H "X-Auth-Token: $TOKEN" -H "Content-type: application/json" -X GET '
    echo "- Monitoring entities request:"
    printf 'curl -s -H "X-Auth-Token: $TOKEN" -H "Content-type: application/json" -X GET https://monitoring.api.rackspacecloud.com/v1.0/'$ACCOUNT_NUMBER'/entities \n\n'
}


# Function used to read the credentials from the file
auth_from_file ()
{
    # Check if the file exists, if not print error message and halt
    if [ ! -f $AUTHFILE ]; then
        echo "ERROR: Authentication file not found!"
        print_help
        exit 1
    fi
    # If file present then read credentials
    USERNAME=$(head -n1 $AUTHFILE)
    APIKEY=$(tail -n1 $AUTHFILE)
                   
}


# =====================================
# End of functions start of main script
# =====================================


# Sanity check variables
Full_Auth_var=false
Token_Auth_var=false
File_Auth_var=false
User_set_var=false
Pass_set_var=false


# check if there are arguments provided, if not print help
if [ "$#" == "0" ]; then
    print_help
    exit 1
fi

# check artuments and set specific variables if needed
while (( "$#" )); do
case "$1" in
    "--me"|"-i")
        auth_from_file
        File_Auth_var=true
        ;;
    "-u"|"--user")
        shift
        USERNAME=$1
        User_set_var=true
        ;;
    "-t"|"--token")
        shift
        Token_Auth_var=true
        ;;
    "-p"|"-k"|"--key")
        shift
        APIKEY=$1
        Pass_set_var=true
        ;;
    "-v"|"--verbose"|"--full"|"-f")
        Full_Auth_var=true
        ;;
    "--help"|"-h"|"-?")
        print_help
        exit 0
        ;;
    *|-*)
        printf "ERROR: Incorrect argument: $1 \n"
        print_help
        exit 1
        ;;
esac
# move to next argument:
shift

done

# ================================================
# Start of the authentication and providing output
# ================================================

# first check if parsers available and select parser
# Check authentication provided
if [ $File_Auth_var == true ]
then
    authenticate
else
    if [ $User_set_var == true ] && [ $Pass_set_var == true ]
    then
        authenticate
    else
        printf "ERROR: Missing either Username or API Key!\n"
        print_help
        exit 1
    fi
fi

# First check if just token was requested
if [ $Token_Auth_var == true ]
then
    select_parser
    print_token
    exit 0
fi

# Check if user wants plain output, if not print nice
if [ $Full_Auth_var == true ] 
then
    print_full
else
    select_parser
    print_nice
fi
