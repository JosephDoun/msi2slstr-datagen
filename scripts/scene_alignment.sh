# Script for automated image coregistration.
# Crop the corresponding S3 parcel to a S2 footprint.
# Apply correlation based coregistration.
#
# Parameters:
#       -d/--dir: The directory holding the images set for alignment.
#

# Exit if directory parameter not provided.
if [ $# -eq 0 ];
then 
	echo $0 " -> " Use -d/--dir to provide a directory to process.; 
	exit 1; 
fi

# Parse parameters.
# __DIR__ holds the provided directory path.
while [ $# -gt 0 ]
do
        case $1 in
                -d|--dir) __DIR__=$2; shift 2;;
                *) echo Unknown argument "$1": Use -d/--dir to provide a directory.;
                exit 1;;
        esac
done

# Reference SEN3 image to be s
S3FILE=$__DIR__/../S3SLSTR.tif

ULLR () { 
	echo $(gdalinfo $1 | grep -oP \
		"(?<=Upper Left  \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g")\
		$(gdalinfo $1 | grep -oP\
			   "(?<=Lower Right \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g" );
}

# Iterate over available tile folders.
if [ ! -e $__DIR__/S2MSI.tmp.tif ];
then 
	scripts/log.sh "Folder appears processed or invalid. Skipping." 1>&2;
	exit 33; 
fi
        
EPSG=$(gdalinfo $__DIR__/S2MSI.tmp.tif | grep -oP "(?<=\"EPSG\",)\d{5}")


scripts/log.sh "EPSG: $EPSG Extents: $(ULLR $__DIR__/S2MSI.tmp.tif | sed "s/\.[0-9]\{3\}//g")"
scripts/log.sh "Generating projected Sentinel-3 patch matching the Sentinel-2 scene.";



# Cast S3 SRS to Sentinel-2 UTM grid.
gdalwarp -r bilinear -tr 500 500 -s_srs EPSG:4326 \
        -t_srs EPSG:$EPSG $S3FILE $__DIR__/s3.tmp.tif \
        -overwrite;


# This performs a cropping action to projwin box.
gdal_translate -projwin $(ULLR $__DIR__/S2MSI.tmp.tif) \
        -projwin_srs EPSG:$EPSG $__DIR__/s3.tmp.tif $__DIR__/s3.patch.tmp.tif &&\
        rm $__DIR__/s3.tmp.tif
        



##################################################
# VALID VALUES CHECK
# ################################################
scripts/log.sh "Checking Sentinel-3 patch validity.";

VALID=$(gdalinfo -stats $__DIR__/s3.patch.tmp.tif |\
grep -oP "(?<=STATISTICS_VALID_PERCENT=)\d+" | head -n 1)
        
if [ $VALID -lt 50 ];
then 
	echo $0 value validity of image at $VALID %.;
	scripts/log.sh "Sentinel-3 patch out of sensor geometry. Removing directory." 1>&2;
    rm -r $__DIR__;
	exit 93;
else
	scripts/log.sh "Image OK."
	rm $__DIR__/s3.patch.tmp.tif.aux.xml;
fi



########################################################
# CORREGISTRATION
########################################################
scripts/log.sh "Starting arosics workflow for $__DIR__.";

arosics local -rsp_alg_calc 0 -rsp_alg_deshift 0 -br 9 -bs 3\
			-fmt_out GTIFF -ws 64 64\
         -nodata "0" "-32768" -min_reliability 10\
          $__DIR__/S2MSI.tmp.tif $__DIR__/s3.patch.tmp.tif 2\
          -o "$__DIR__/s3_coreg.tif" 2> /dev/null &&\
		  rm $__DIR__/s3.patch.tmp.tif

# If output file was not generated continue to next iteration.
if [[ ! -e "$__DIR__/s3_coreg.tif" ]]
then
	scripts/log.sh "Arosics workflow failed. Skipping." 1>&2;
	exit 90;
fi
       
scripts/log.sh "Cropping Sentinel-3 to a 210 x 210 pixels scene.";

gdal_translate -co "COMPRESS=ZSTD" -co "PREDICTOR=2" -co "TILED=YES" \
			-co "BLOCKXSIZE=16" -co "BLOCKYSIZE=16" -srcwin 4 4 210 210\
			-ot float32 $__DIR__/s3_coreg.tif $__DIR__/S3SLSTR.tif &&\
          rm $__DIR__/s3_coreg.tif

read -a S2BOX < <(ULLR $__DIR__/S2MSI.tmp.tif | sed "s/\.[0-9]\+//g")
read -a S3BOX < <(ULLR $__DIR__/S3SLSTR.tif | sed "s/\.[0-9]\+//g")
        
# LAST STEP: Crop S2MSI image to rounded S3 extents.
scripts/log.sh "Cropping Sentinel-2 scene to the exact extents of the generated Sentinel-3 patch.";
		
echo "From ${S2BOX[@]}";
echo "To   ${S3BOX[@]}";

gdal_translate -co "COMPRESS=ZSTD" -co "TILED=YES"\
			-co "PREDICTOR=2" -co "BLOCKXSIZE=16"\
			-co "BLOCKYSIZE=16" -ot int16 -projwin ${S3BOX[@]}\
         $__DIR__/S2MSI.tmp.tif $__DIR__/S2MSI.tif &&\
         rm $__DIR__/S2MSI.tmp.tif;



