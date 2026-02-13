# Script to bundle the Sentinel-2 .jp2 files into a multiband compressed geotiff.

if [ $# -eq 0 ]; then echo Provide a directory using the -d/--dir option;  exit 1; fi;

while [ $# -gt 0 ]
do
        case $1 in
                -d|--dir) __DIR__=$2; shift 2;;
                -s|--safe) s2_dir=$2; shift 2;;
                *) echo Unknown argument \"$1\":\
					Use -d/--dir to provide a directory.; exit 1;;
        esac
done

burn_uniform_angle_rasters () { 
	gdal_create -of GTiff -ot Float32 -bands 1 -burn $1\
		-outsize 1830 1830 -a_srs $2 -a_ullr $3 $4; }

ULLR () { 
	echo $(gdalinfo $1 | grep -oP "(?<=Upper Left  \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g") \
               $(gdalinfo $1 | grep -oP "(?<=Lower Right \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g" );
}

# Get EPSG code.
EPSG () { gdalinfo $1 | grep -oP "(?<=\"EPSG\",)\d{5}" ; }

# The tile of the Sentinel-2 grid system.
TILE=$(echo $s2_dir | grep -oP "(?<=_)\w{6}(?=_\d{8}T\d{6}.SAFE)")

# The id of the Sentinel-2 image.
ID=$(basename $s2_dir | grep -oP ".*(?=.SAFE)");

# The directory to build the Sentinel-2 image.
s2_dir=$__DIR__/$s2_dir

read -d '\n' -a ZENITHS < <(cat $s2_dir/GRANULE/*/MTD_TL.xml |\
	grep -oP "(?<=<ZENITH_ANGLE unit=\"deg\">)[0-9\.]*(?=</ZENITH_ANGLE>)");
read -d '\n' -a AZIMUTHS < <(cat $s2_dir/GRANULE/*/MTD_TL.xml |\
	grep -oP "(?<=<AZIMUTH_ANGLE unit=\"deg\">)[0-9\.]*(?=</AZIMUTH_ANGLE>)");


scripts/log.sh "Tile ID: $ID";
mkdir -p $__DIR__/$TILE;
mv $s2_dir/GRANULE/*/IMG_DATA/*B[0-9][0-9A]*.jp2 $__DIR__/$TILE;

# TODO Can make a python component that get the precise gridded zenith values.

# Separate different resolutions in 3 different merged rasters.
# Upsample to 10m using DSen2-like architecture at later stage.
scripts/log.sh "Building VRT file for merged Sentinel-2 scene."
gdalbuildvrt \
    -resolution highest \
    -srcnodata 0 \
    -vrtnodata 0 \
    -separate \
    $__DIR__/$TILE/merged.vrt \
    $__DIR__/$TILE/*{B01,B02,B03,B04,B05,B06,B07,B08,B8A,B09,B10,B11,B12}.jp2 
# gdalbuildvrt -resolution highest -separate $__DIR__/$TILE/merged.vrt $__DIR__/$TILE/*{B01,B02,B03,B04,B05,B06,B07,B08,B8A,B09,B10,B11,B12}.jp2 
# gdalbuildvrt -resolution highest -separate $__DIR__/$TILE/merged.vrt $__DIR__/$TILE/*{B01,B02,B03,B04,B05,B06,B07,B08,B8A,B09,B10,B11,B12}.jp2 
# gdalbuildvrt -resolution highest -separate $__DIR__/$TILE/merged.vrt $__DIR__/$TILE/*{B01,B02,B03,B04,B05,B06,B07,B08,B8A,B09,B10,B11,B12}.jp2 

scripts/log.sh "Building multiband TIF file for Sentinel-2 scene."

gdal_translate -mo "S2_PRODUCT=$ID" \
        -mo "ZENITH_SOLAR=${ZENITHS[0]}"\
		-mo "AZIMUTH_SOLAR=${AZIMUTHS[0]}"\
        -mo "ZENITH_B01=${ZENITHS[1]}"\
		-mo "AZIMUTH_B01=${AZIMUTHS[1]}"\
        -mo "ZENITH_B02=${ZENITHS[2]}"\
		-mo "AZIMUTH_B02=${AZIMUTHS[2]}"\
        -mo "ZENITH_B03=${ZENITHS[3]}"\
		-mo "AZIMUTH_B03=${AZIMUTHS[3]}"\
        -mo "ZENITH_B04=${ZENITHS[4]}"\
		-mo "AZIMUTH_B04=${AZIMUTHS[4]}"\
        -mo "ZENITH_B05=${ZENITHS[5]}"\
		-mo "AZIMUTH_B05=${AZIMUTHS[5]}"\
        -mo "ZENITH_B06=${ZENITHS[6]}"\
		-mo "AZIMUTH_B06=${AZIMUTHS[6]}"\
        -mo "ZENITH_B07=${ZENITHS[7]}"\
		-mo "AZIMUTH_B07=${AZIMUTHS[7]}"\
        -mo "ZENITH_B08=${ZENITHS[8]}"\
		-mo "AZIMUTH_B08=${AZIMUTHS[8]}"\
        -mo "ZENITH_B8A=${ZENITHS[9]}"\
		-mo "AZIMUTH_B8A=${AZIMUTHS[9]}"\
        -mo "ZENITH_B09=${ZENITHS[10]}"\
		-mo "AZIMUTH_B09=${AZIMUTHS[10]}"\
        -mo "ZENITH_B10=${ZENITHS[11]}"\
		-mo "AZIMUTH_B10=${AZIMUTHS[11]}"\
        -mo "ZENITH_B11=${ZENITHS[12]}"\
		-mo "AZIMUTH_B11=${AZIMUTHS[12]}"\
        -mo "ZENITH_B12=${ZENITHS[13]}"\
		-mo "AZIMUTH_B12=${AZIMUTHS[13]}"\
        $__DIR__/$TILE/merged.vrt $__DIR__/$TILE/S2MSI.tmp.tif &&\
        rm -r $__DIR__/$TILE/*.{vrt,jp2} $s2_dir;


scripts/scene_alignment.sh -d $__DIR__/$TILE;
EXITCODE=$?
if [ $EXITCODE -ne 0 ]
then
    echo Scene alignment for $__DIR__/$TILE failed with code $EXITCODE. Removing.
    rm -r $__DIR__/$TILE
fi

