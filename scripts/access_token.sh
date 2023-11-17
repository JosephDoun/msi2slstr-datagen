# Access token requesting script.

if [[ -z $DATASPACE_USERNAME ]] && [[ -z $REFRESH_TOKEN ]]; then echo "Username to copernicus dataspace not provided. Set the DATASPACE_USERNAME environment variable."; exit 99; fi;
if [[ -z $DATASPACE_PASSWORD ]] && [[ -z $REFRESH_TOKEN ]]; then echo "Password to copernicus dataspace not provided. Set the DATASPACE_PASSWORD environment variable."; exit 100; fi;

if [[ -n $RECEIVE_TIME ]]
then
    REQUEST_TIME=$(date +%s)
    TIME_PASSED=$(( $REQUEST_TIME - $RECEIVE_TIME ))
    MEAN_PASS=$(( $TIME_PASSED / $ACCESS_COUNTS ))
fi

if [[ -n $TIME_PASSED ]] && [[ $TIME_PASSED -lt $((600 - $MEAN_PASS)) ]]
then ((ACCESS_COUNTS+=1)); return; fi;

if [[ -z $REFRESH_TOKEN ]]
then
    TOKEN_RESPONSE=$(curl -d 'client_id=cdse-public' \
                    -d "username=$DATASPACE_USERNAME" \
                    -d "password=$DATASPACE_PASSWORD" \
                    -d 'grant_type=password' \
                    'https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token')
    unset DATASPACE_USERNAME DATASPACE_PASSWORD
else
    TOKEN_RESPONSE=$(curl -d 'client_id=cdse-public' \
                    -d 'grant_type=refresh_token' \
                    -d "refresh_token=$REFRESH_TOKEN" \
                    'https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token')
fi

RECEIVE_TIME=$(date +%s)
ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | \
                    python3 -m json.tool | grep "access_token" | awk -F\" '{print $4}')
REFRESH_TOKEN=$(echo $TOKEN_RESPONSE  | \
                    python3 -m json.tool | grep "refresh_token" | awk -F\" '{print $4}')
ACCESS_COUNTS=1
