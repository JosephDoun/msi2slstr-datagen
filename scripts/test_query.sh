# Script to test query validity; And verify API functionality;

# Status code extraction; 
run_query_get_status_code () {
		curl -D - "$1" 2> /dev/null | grep HTTP | grep -Eo [0-9]{3};
}

# Fixed parameters;
FROM="2022-12-11";
TO="2023-01-11";
LOCATION="geography'SRID=4326;POINT(10%2050)'";

# Test S2MSI1C product request;
Q=$(./scripts/query_format.sh "S2MSI1C" $FROM $TO $LOCATION)
STATUS=$(run_query_get_status_code "$Q")
if [[ $STATUS -ne 200 ]]; then exit 1; fi;

# Test RBT product request; 
Q=$(./scripts/query_format.sh "SL_1_RBT____" $FROM $TO $LOCATION);
STATUS=$(run_query_get_status_code $Q)
if [[ $STATUS -ne 200 ]]; then exit 2; fi;

# Test LST product request;
Q=$(./scripts/query_format.sh "SL_2_LST____" $FROM $TO $LOCATION);
STATUS=$(run_query_get_status_code $Q)
if [[ $STATUS -ne 205 ]]; then exit 3; fi;


