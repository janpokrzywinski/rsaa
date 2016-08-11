#!/bin/bash
#
#    Bash script for Rackspace Cloud API authentication.
#    Version 1.3.5
#    Jan Pokrzywinski
#

# Authentication endpoint
Auth_Url=https://identity.api.rackspacecloud.com/v2.0/

# Set file where the auth details are stored
Auth_File=~/.rsaa.conf

# Function that checks for available parsers
select_parser ()
{
# first verify if python is present
if hash python 2>/dev/null
then
    # then check if it can import the json.tool module, if yes then set python as parser, if not specify that there is none
    Check_Python_Module=$(python -c 'import json' 2>&1)
    if [ -z "${Check_Python_Module}" ]
        then
            Parser="python"
        else
            Parser="none"
    fi
else
    Parser="none"
fi

# if there is no python check for jq
if [[ ${Parser} == "none" ]] && (hash jq 2>/dev/null)
then
    Parser="jq"
fi

if [[ ${Parser} == "none" ]]
then
    echo -e "ERROR! No parser available!\nThis script requires either python module json.tool or jq\nFor jq visit http://stedolan.github.io/jq/"
    print_help
    exit 1
fi
}


# Main authentication function. Stores plain JSON response in the AUTH variable
authenticate () 
{
    Rax_Auth=$(curl -sX POST ${Auth_Url}/tokens -d '{"auth":{ "RAX-KSKEY:apiKeyCredentials":{ "username":"'${Username}'", "apiKey":"'${Api_Key}'" } } }' -H "Content-type: application/json")
    Error_Msg='Username or api key is invalid.'
    # verify if the response does not indicate incorrect authentication details.
    Error_Check=$(echo ${Rax_Auth} | grep "${Error_Msg}")
    if [ -n "${Error_Check}" ]
    then
        echo "ERROR: Incorrect authentication details, wrong username or password."
        exit 1
    fi
}


# Function to print message for help

print_help ()
{
    echo -e """Usage: ${0} [OPTIONS] -u Login-Name -p API-Key
  or : ${0} [OPTIONS] -i

  -u, --user\t\t\tUsername
  -p, -k, --key\t\t\tAPI Key
  -t, --token\t\t\tRespond just with API Token
  -i, --me\t\t\tLoad credentials from ${Auth_File} file
  -v, --verbose, --full, -f\tDisplay plain JSON response

To use the credentials from the file create it as a plain text in ${Auth_File}
It should only contain two lines of text in format:
Username
API-Key
            """
}


# Function to print bare output without any data manipulation
print_full ()
{
    echo ${Rax_Auth}
}


# Acquire token
acquire_token ()
{
    if [[ ${Parser} == 'python' ]]
    then
        Auth_Token=$(echo ${Rax_Auth} | python -c 'import json, sys; data = json.loads(sys.stdin.read()); print data["access"]["token"]["id"]')
    elif [[ ${Parser} == 'jq' ]]
    then
        Auth_Token=$(echo ${Rax_Auth} | jq '.access.token.id' | tr -d '"')
    fi
}


# Function to print just the API Token
print_token ()
{
    acquire_token
    echo ${Auth_Token}
}


# Function to print output for Endpoints, Token and sample curl command
print_nice ()
{
# first obtain some specific information by parsing the AUTH variable
    acquire_token
    if [[ ${Parser} == 'python' ]]
    then
        Token_Expires=$(echo ${Rax_Auth} | python -mjson.tool | grep expires | cut -d '"' -f4 | sed 's/T/ /g' | cut -c1-19)
        Default_Reg=$(echo ${Rax_Auth} | python -mjson.tool | grep defaultRegion | cut -d '"' -f4)
        Account_Number=$(echo ${Rax_Auth} | python -mjson.tool | grep -A1 'tenant"' | grep id | cut -d '"' -f4)
    elif [[ ${Parser} == 'jq' ]]
    then
        Token_Expires=$(echo ${Rax_Auth} | jq . | grep expires | cut -d '"' -f4 | sed 's/T/ /g' | cut -c1-19)
        Default_Reg=$(echo ${Rax_Auth} | jq '.access.user' | grep defaultRegion | cut -d '"' -f4)
        Account_Number=$(echo ${Rax_Auth} | jq '.access.token.tenant' | grep id | cut -d '"' -f4)
    fi
# get to pretty printing
    printf "\n\e[1;36m----------- Info ------------\e[0m\n"
    printf "Parser used: ${Parser}\nDDI: ${Account_Number}\nDefault Region: ${Default_Reg}\nAuth URL:\n${Auth_Url}\n"
    printf "\n\e[1;36m--------- Endpoints ---------\e[0m\n"
    if [[ ${Parser} == 'python' ]]
    then
        echo ${Rax_Auth} | python -mjson.tool | grep "URL"| cut -d '"' -f4
    elif [[ ${Parser} == 'jq' ]]    
    then
        echo ${Rax_Auth} | jq '.access.serviceCatalog' | grep "URL"| cut -d '"' -f4
    fi    
    printf "\n\e[1;36m--------- API Token ---------\e[0m\nAUTH_TOKEN=${Auth_Token}\nToken expires: ${Token_Expires}\n\n"
    printf "\e[1;36m--- Example curl requests ---\e[0m\n"
    printf "See https://docs.rackspace.com for full specification, add endpoint URL at the end of each request"
    echo "- Generic silent request:"
    echo 'curl -s -H "X-Auth-Token: ${AUTH_TOKEN}" -H "Content-type: application/json" -X GET '
    echo "- Monitoring entities request:"
    echo -e 'curl -s -H "X-Auth-Token: ${AUTH_TOKEN}" -H "Content-type: application/json" -X GET https://monitoring.api.rackspacecloud.com/v1.0/'${Account_Number}'/entities \n\n'
}


# Function used to read the credentials from the file
auth_from_file ()
{
    # Check if the file exists, if not print error message and halt
    if [ ! -f ${Auth_File} ]; then
        printf "ERROR: Authentication file not found!"
        print_help
        exit 1
    fi
    # If file present then read credentials
    Username=$(head -n1 ${Auth_File})
    Api_Key=$(tail -n1 ${Auth_File})
                   
}


# =====================================
# End of functions start of main script
# =====================================


# Sanity check variables
Full_Auth_Var=false
Token_Auth_Var=false
File_Auth_Var=false
User_Set_Var=false
Pass_Set_Var=false


# check if there are arguments provided, if not print help
if [ "$#" == "0" ]; then
    print_help
    exit 1
fi

# check artuments and set specific variables if needed
while (( "$#" )); do
case "${1}" in
    "--me"|"-i")
        auth_from_file
        File_Auth_Var=true
        ;;
    "-u"|"--user")
        shift
        Username=${1}
        User_Set_Var=true
        ;;
    "-t"|"--token")
        shift
        Token_Auth_Var=true
        ;;
    "-p"|"-k"|"--key")
        shift
        Api_Key=${1}
        Pass_Set_Var=true
        ;;
    "-v"|"--verbose"|"--full"|"-f")
        Full_Auth_Var=true
        ;;
    "--help"|"-h"|"-?")
        print_help
        exit 0
        ;;
    *|-*)
        printf "ERROR: Incorrect argument: ${1} \n"
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
if [ ${File_Auth_Var} == true ]
then
    authenticate
else
    if [ ${User_Set_Var} == true ] && [ ${Pass_Set_Var} == true ]
    then
        authenticate
    else
        printf "ERROR: Missing either Username or API Key!\n"
        print_help
        exit 1
    fi
fi

# First check if just token was requested
if [ ${Token_Auth_Var} == true ]
then
    select_parser
    print_token
    exit 0
fi

# Check if user wants plain output, if not print nice
if [ ${Full_Auth_Var} == true ] 
then
    print_full
else
    select_parser
    print_nice
fi
