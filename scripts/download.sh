#
#
# SENTINEL-2 AND SENTINEL-3 SLSTR DATA FUSION PROJECT.
#
# SCRIPT THAT USES THE COPERNICUS DHUS API FOR ACCESING SENTINEL-3 IMAGES,
# DOWNLOADS THEM, THEN SEARCHES FOR SENTINEL-2 IMAGES WITHIN ITS FOOTPRINT.
#
# EACH SENTINEL-3/SENTINEL-2 BUNDLE IS SAVED IN A SINGLE DIRECTORY AND
# THEIR COMMON PATCHES WILL CONSTITUTE THAT DATE'S DATA SAMPLES.
#
#
# Arguments:
#       -d  Date formated as YYYY-MM-DD, e.g. 2022-01-01.
#       -g  Geometry point formated as "LAT, LON"
#
#
# Querying Products in the Data Hub archive
# URL EXAMPLES --
#
# "https://scihub.copernicus.eu/dhus/search?q=footprint:%22Intersects(POLYGON((-4.53%2029.85,26.75%2029.85,26.75%2046.80,-4.53%2046.80,-4.53%2029.85)))%22"
# "https://scihub.copernicus.eu/dhus/odata/v1/Products('59a7ee03-da3b-483a-a0e3-95a4445b8e99')/\$value"
#
# NEW API LINK FOR MIGRATION:
# https://catalogue.dataspace.copernicus.eu/odata/v1/Products?
#

shopt -s expand_aliases

log () {
	# Module logger
	echo $0 " -> " $1;
}

ALLOWED_PRODTYPES=("SL_1_RBT___" "SL_2_LST___")
OVRWRT=0;

# Space formating function for URLs.
# Replace white space with url code.
nospace () { echo $1 | sed "s/ /%20/g"; }

validate_option () {
        local OPT_=$1; shift;
        local VAL_=$1; shift;
        local ALL_=("$@");
        
        for val_ in ${ALL_[@]}
        do
                if [ $VAL_ == $val_ ]
                then
                        local valid=1;
                        break;
                fi
        done
        if [[ ! $valid -eq 1 ]]
        then
                log "Invalid value \"$VAL_\" for option $OPT_"
                local IFS=','; echo $0 " -> " "Allowed values:" "${ALL_[*]}";
                exit 1;
        fi
}

# Default datadump directory.
__DATADIR__="s2lstr-dataset";
# Default allowed time difference of Sentinel-2 acquisitions.
MAXTIME=300;
# Default minimum filesize.
MINFILESIZE=$((700*1024*1024))

# Option parsing.
while [ "$#" -gt 0 ];
do
  case "$1" in
          -d|--date)
          FROM=$(date -d "$2" +%F);
		  TO=$(date -d "$FROM + 1 day" +%F);
          shift 2;;
          -l|--loc) LOC=$(nospace "$2"); shift 2;;
		  -o|--out) __DATADIR__=$2; shift 2;;
		  -t|--time) TIME=$2; shift 2;;
          --overwrite) OVRWRT=1; shift 1;;
          --to-date) TO=$2; shift 2;;
          *) echo "unknown option: $1" >&2; exit 1;;
          
          # *) handle_argument "$1"; shift 1;;  
  esac
done

if [[ -z $FROM ]]; then log "Date was not supplied: use -d/--date option."; exit 1; fi;
if [[ -z $LOC ]]; then log "Geometry was not supplied: use -l/--loc option."; exit 1; fi;

# Preset curl options
alias curl='curl -# --retry 10 --fail-early'

# Generate access token
if [[ -z $ACCESS_TOKEN ]]; then source scripts/access_token.sh; fi;

# Wrap GEOM value to request body expected format
LOC="geography'SRID=4326;POINT($LOC)'";

##############
# echo $TO $FROM $ACCESS_TOKEN;
#############

# Query request function that returns server response.
query () {

	##############
	# echo $@;
	#############
	
        Q="https://catalogue.dataspace.copernicus.eu/odata/v1/Products?\$filter="
        Q+="ContentDate/Start+gt+$2T00:00:00.000Z"
        Q+="+and+ContentDate/Start+lt+$3T00:00:00.000Z"
        Q+="+and+Attributes/OData.CSC.StringAttribute/any("
        Q+="att:att/Name+eq+'productType'"
        Q+="+and+att/OData.CSC.StringAttribute/Value+eq+'$1')"
        
        if [[ $1 == "S2MSI1C" ]]
        then
                Q+="+and+Attributes/OData.CSC.DoubleAttribute/any("
                Q+="att:att/Name+eq+'cloudCover'"
				# BUGFIX DoubleAttribute were changed in latest API
				# and are now expecting float format. E.g. Previously
				# expected '15.00' becomes simply 15.00.
                Q+="+and+att/OData.CSC.DoubleAttribute/Value+lt+15.00)"
        fi

        Q+="+and+Odata.CSC.Intersects(area=$4)";
        Q+="&\$orderby=ContentDate/Start+asc";
        Q+="&\$top=30";
        # Q+="&\$expand=Attributes";
        
		curl -D query_header_dump.txt --fail "$Q";
        }

# Function that downloads product from link.
download () {

source scripts/access_token.sh;

curl -D download_header_dump.txt -H "Authorization: Bearer $ACCESS_TOKEN"\
 "https://catalogue.dataspace.copernicus.eu/odata/v1/Products($1)/\$value"\
 --location-trusted -o "$2" | head -n 1 | grep -oP "\d{3}";

}

# Extract date from provided filename.
get_date () { echo $1 | grep -oP "\d*(?=T)" | head -n 1; }

# Extract datetimes from provided query responces.
get_datetimes () { 
echo $1 |  grep -oP "(?<=\"Start\":\")\d{4}-\d{2}-\d{2}T\d\d:\d\d:\d\d\.\d\d\dZ";
}

log "Querying for RBT products".
RBTRESPONSE=$(query "SL_1_RBT___" $FROM $TO $LOC)

##################
# echo $RBTRESPONSE;
##################

log "Querying for LST products."
LSTRESPONSE=$(query "SL_2_LST___" $FROM $TO $LOC)

#################
# echo $LSTRESPONSE;
#################

__GEOM__REGEX__="(?<=\"Footprint\":\")geography[^\"]*'(?=\",)"
__ID____REGEX__="(?<=\"Id\":\")[a-zA-Z0-9_\-]*(?=\",)"
__FNAME_REGEX__="(?<=\"Name\":\")[a-zA-Z0-9_\.]*(?=\",)"
__FSIZE_REGEX__="(?<=\"ContentLength\":)[0-9]+(?=,)"
__ONLNE_REGEX__="(?<=\"Online\":)\w{4,5}"

RBT_QUERY_FOOTPRINT=$(nospace "$(echo $RBTRESPONSE |\
 grep -oP "$__GEOM__REGEX__" | head -n 1)")
RBT_ID=$(echo $RBTRESPONSE | grep -oP "$__ID____REGEX__" | head -n 1)
RBT_FILE=$(echo $RBTRESPONSE | grep -oP "$__FNAME_REGEX__" | head -n 1)
RBT_DATE=$( get_date $RBT_FILE )

LST_QUERY_FOOTPRINT=$(nospace "$(echo $LSTRESPONSE |\
 grep -oP "$__GEOM__REGEX__" | head -n 1)")
LST_ID=$(echo $LSTRESPONSE | grep -oP "$__ID____REGEX__" | head -n 1)
LST_FILE=$(echo $LSTRESPONSE | grep -oP "$__FNAME_REGEX__" | head -n 1)
LST_DATE=$(get_date $LST_FILE)

# Get query response for S2MSI1C products.
L1CRESPONSE=$(query "S2MSI1C" "$FROM" "$TO" "$RBT_QUERY_FOOTPRINT")

###########################
# echo $L1CRESPONSE;
##########################

# Extract dates of products for comparison.
RBTSTART=${RBT_FILE:16:15}
LSTSTART=${LST_FILE:16:15}

# Assert product dates match.
if [ ! $RBTSTART == $LSTSTART ]; 
then
	log "RBT $RBTSTART and LST $LSTSTART product start times do not match, aborting."; 
	
	cat <<-EOF
	
	UNDEFINED BEHAVIOUR // AVOID USAGE // SELECT LATER DATE
	
	# NOTE for future versions.

	If you are trying to generate data for an earlier year e.g. 2019
	the acquisition operations and data generation workflows of the platform
	may have been different.

	That is because RBT acquisitions and corresponding LST acquisitions did 
	not share the same starting time signature earlier. LST products had
	a longer acquisition window and acquired images for multiple RBT footprints.
	
	As a result, acquisition start times for matching products may differ.

	THE USED API SEEMS TO BE FUNCTIONING PROPERLY ONLY FOR 2023 AND LATE 2022.
	EOF

	exit 111; 
fi

log "Sentinel-3 RBT Product -> $RBT_FILE"
log "Sentinel-3 LST Product -> $LST_FILE"

REFERENCETIME=$(get_datetimes "$RBTRESPONSE" | head -n 1)
L1CONLINESTATUS=( $(echo $L1CRESPONSE | grep -oP $__ONLNE_REGEX__) )
S2IDS=( $(echo $L1CRESPONSE | grep -oP "$__ID____REGEX__") )
S2FILESIZE=( $(echo $L1CRESPONSE | grep -oP "$__FSIZE_REGEX__") )
S2FNAMES=( $(echo $L1CRESPONSE | grep -oP "$__FNAME_REGEX__") )

TIMEDIFFS=(); i=0;
for datetime in $(get_datetimes "$L1CRESPONSE")
do
        DIFF=$((`date -ud "$datetime" +%s` - `date -ud $REFERENCETIME +%s`))
        DIFF=$(echo $DIFF | grep -oP "\d*")
        TIMEDIFFS[$i]=$DIFF; ((i++));
done

S2FOOTPRINTS=(); i=0;
IFS=$'\n'
for __geometry in $(echo $L1CRESPONSE | grep -oP "$__GEOM__REGEX__")
do
        S2FOOTPRINTS[$i]=$(nospace "$__geometry"); ((i++));
done
unset IFS;

# Extract relative orbit for directory tree convention.
# Technically speaking DATE + RELORBIT + POINT should be unique.
# NOT USED. RBT_DATE IS USED INSTEAD.
# RELORBIT=$(echo $RBT_FILE | grep -oP "\d{4}_\d{3}_\d{3}_\d{4}" |\
#  grep -oP "\d{3}_\d{4}" | grep -oP "\d{3}(?=_)");

# Define directory path.
__PATH__="$__DATADIR__/$RBT_DATE/$(date -ud $REFERENCETIME +%Y%m%dT%H%M%S)"

# If exists, exit.
if [ -d $__PATH__ ] && [ $OVRWRT -ne 1 ];
then 
        log "Directory already exists. Exiting."; 
        exit 11;
elif [ ${#S2IDS[@]} -eq 0 ]
then
        log "No Sentinel-2 scenes matched the query. Exiting.";
        exit 22;
else 
        mkdir -p $__PATH__; 
fi


# Download S2 products. Collect inaccessible ids.
log "Downloading Sentinel-2 images for $FROM";


S2OFFLINE=(); flag=0;
for i in "${!S2FOOTPRINTS[@]}"
do
        if [ $RBT_DATE == $(get_date ${S2FNAMES[$i]}) ] &&\
         [[ ${S2FILESIZE[$i]%.*} -ge $MINFILESIZE ]] &&\
          [[ ${TIMEDIFFS[$i]} -le $MAXTIME ]] &&\
           [ ! -d $__PATH__/${S2FNAMES[$i]} ]
        then
                STATUS=$(download "${S2IDS[$i]}" "$__PATH__/${S2FNAMES[$i]}.zip")
                if [[ $STATUS -eq 301 ]] && [[ $? -eq 0 ]]
                then
						# Start background building process
						# of Sentinel-2 image.
                        { 
                        unzip -o "$__PATH__/${S2FNAMES[$i]}.zip"\
                         -d "$__PATH__" 1> /dev/null &&\
                         rm "$__PATH__/${S2FNAMES[$i]}.zip" &&\
                         scripts/build_sentinel_2.sh -d $__PATH__\
                          -s ${S2FNAMES[$i]} 1> /dev/null;
                        } &

                        log "Downloaded ${S2FNAMES[$i]} with size 
						$((${S2FILESIZE[$i]} / 1024 / 1024)) MB."
                        
						((flag++))

                # Store offline if code 202 (indicates successful order).
                # This behavior changed. To change in the future.
				# CURRENTLY DEPRECATED
                # elif [[ $STATUS -eq 202 ]] && [[ $? -eq 0 ]]
                # then
                #         echo
                #         echo Sentinel-2 product offline. Archive request successful.;
                #         echo
                #         S2OFFLINE[$i]=${S2IDS[$i]};
                
				else
                        log "WARNING: Uncaught status $STATUS";
                        log "Product Failure. Aborting."
                        rm -r $__PATH__ && exit 33;
                fi
        fi
done

if [[ $flag -eq 0 ]]
then	
        log "No Sentinel-2 scenes met criteria.";
			
		cat <<-EOF
		
		All Sentinel-2 images were acquired more than $(($MAXTIME/60)) 
		minutes apart or were less than $(($MINFILESIZE/1024/1024))mb in size.

		Sentinel-2 acquisition time differences (seconds): ${TIMEDIFFS[@]}
		Sentinel-2 filesizes (Bytes): ${S2FILESIZE[@]}
		
		EOF
		
        rmdir -p $__PATH__ 2> /dev/null
        exit 33;
fi

# Download S3 products.
log "Downloading Sentinel-3 products for $FROM."

# Download endpoints return code 301 on successful request.
CODE=301;
while :
do
        [[ $STATUSRBT -ne $CODE ]] &&\
        STATUSRBT=$(download "$RBT_ID" "$__PATH__/$RBT_FILE.zip");

        [[ $STATUSLST -ne $CODE ]] &&\
        STATUSLST=$(download "$LST_ID" "$__PATH__/$LST_FILE.zip");

        if [[ $STATUSRBT -eq $CODE ]] &&\
         [[ $STATUSLST -eq $CODE ]] &&\
         [[ $? -eq 0 ]]
        then

                { 
                unzip -o "$__PATH__/$RBT_FILE.zip"\
                        -d "$__PATH__" &&\
                        rm "$__PATH__/$RBT_FILE.zip";
                } &
                PROC1=$!
                {
                unzip -o "$__PATH__/$LST_FILE.zip"\
                        -d "$__PATH__" &&\
                        rm "$__PATH__/$LST_FILE.zip";
                } &
                PROC2=$!

                wait $PROC1 && wait $PROC2

                if [[ $? -eq 0 ]]
                then
                        scripts/build_sentinel_3.sh -d $__PATH__ &
                        PROC3=$!
                fi

                break;
        fi

        log "There are likely offline products. Trying again at $(date -d "now + 15 minutes" +%T)."

        sleep 900
done

# DEPRECATED // TO REIMPLEMENT IN CASE CATALOGUE.DATASPACE.COPERNICUS.EU ADOPTS OFFLINE PRODUCT POLICY
# check_online () {
# for i in "${!S2OFFLINE[@]}"
# do      
#         if [[ -n ${S2OFFLINE[$i]} ]]
#         then
#                 STATUS=$(download "${S2OFFLINE[$i]}" "$__PATH__/${S2IDS[$i]}.zip")
#                 if [[ $STATUS -eq 301 ]] && [[ $? -eq 0 ]]
#                 then
#                         unzip "$__PATH__/${S2FNAMES[$i]}.zip" -d $__PATH__ &&\
#                         rm "$__PATH__/${S2FNAMES[$i]}.zip" &&\
#                         unset S2OFFLINE[$i];
#                         echo 
#                         echo "Successfully downloaded ${S2FNAMES[$i]}"\
#                         "with size ${S2FILESIZE[$i]}."
#                         echo
#                 elif [[ $STATUS -eq 202 ]] && [[ $? -eq 0 ]]
#                 then
#                         echo "Product still offline, retrieval on going."
#                 else
#                         echo "WARNING: Unhandled status $STATUS";
#                         echo "Product request is likely to have failed."
#                 fi
#         fi
# done
# }

# while [[ ${S2OFFLINE[@]} ]]
# do
#         echo
#         echo "There are likely offline Sentinel-2 products. Trying again at $(date -d 'now + 15 minutes' +%T).";
#         echo
#         sleep 900;
#         check_online
# done
#

log "Finished $FROM."

log "Awaiting image building background processes..."

wait $PROC3 && log "Success." || (log "Failure." && exit 12);
wait

