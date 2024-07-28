#!/usr/bin/bash
# Entry point for dataset generation.

gdal-config --version > /dev/null || echo "GDAL does not appear to be installed. Please install it."
curl --version > /dev/null || echo "Curl does not appear to be installed. Please install it."
arosics --version > /dev/null || echo "Curl does not appear to be installed. Please install it."


log () {
	echo $0 " -> " "$@";
}


SCRIPT=$(basename $0);
IFS='' read -r -d '' HELP <<EOF

$SCRIPT script usage help -- intended for bash shell
	
$SCRIPT:
$ DATASPACE_USERNAME=<Account email> DATASPACE_PASSWORD=<Account password> ./$SCRIPT [-l lon lat] [-o dir] date ...
  
  Set the environment variables DATASPACE_USERNAME, DATASPACE_PASSWORD to 
  provide credentials to the catalogue.dataspace.copernicus.eu service.

  Options:
	-l, --location lon lat	The longitude and latitude of the intersection to
				use for querying Sentinel-3 images.
				Defaults to 10 50 (Central Europe).
	-t, --time     seconds	The maximum seconds of acquisition difference that
				are allowed between Sentinel-3 and Sentinel-2 scenes.
				Defaults to 300 (5 minutes).
	-o, --output   dir      The output directory in which to build the dataset.
				Defaults to "./s2lstr-dataset".
EOF


# Default loc at approximate center of Europe.
__LOC__="10 50";
# Default datadump directory.
__DIR__="s2lstr-dataset";
# Default maximum acquisition time difference for Sentinel-2 scenes (5 minutes).
__TIME__=300;


# Parameter parsing.
case $1 in
		-h|--help) echo "$HELP"; exit 0;;
        -l|--location) __LOC__=$2; shift 2;;
		-t|--time) __TIME__=$2; shift 2;;
		-o|--output) __DIR__=$2; shift 2;;
		-*) echo Unknown argument "$1". Run ./make_dataset.sh -h/--help for additional information.;
        exit 1;;
esac


# Iterate over provided dates.
for DATE in $@
do
        # Cast date to correct format.
        DATE=$(date --date $DATE +%Y-%m-%d)
        
		if [[ ! $? ]]; then log "Invalid date. Skipping."; continue; fi;

        log "Starting download for $DATE.";
        
        scripts/download.sh -d "$DATE" -l "$__LOC__" -t "$__TIME__" -o "$__DIR__";
		
		DOWNLOAD_ERROR=$?
		if [[ $DOWNLOAD_ERROR -eq 99 ]] || [[ $DOWNLOAD_ERROR -eq 100 ]]; then exit $DOWNLOAD_ERROR; fi;
 		if [[ $DOWNLOAD_ERROR -eq 111 ]]; then log "ERROR DURING DOWNLOAD -- ABORTING"; exit $DOWNLOAD_ERROR; fi;

        log "Download process finished.";
        
        for dir in $__DIR__/$(date --date $DATE +%Y%m%d)/*;
        do
                scripts/scene_alignment.sh -d $dir &
                PROC=$!;
        done
done

log "Waiting for background scene alignment workflows..."

wait $PROC && log "Process finished for dates $@." || log "Failed with code $?" && exit 1;
wait

log "Finished.";

