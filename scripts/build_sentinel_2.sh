# Script to bundle the Sentinel-2 .jp2 files into a multiband compressed geotiff.

if [ $# -eq 0 ]; then echo Provide a directory using the -d/--dir option;  exit 1; fi;

while [ $# -gt 0 ]
do
        case $1 in
                -d|--dir) __DIR__=$2; shift 2;;
                -s|--safe) s2_dir=$2; shift 2;;
                *) echo Unknown argument \"$1\": Use -d/--dir to provide a directory.; exit 1;;
        esac
done

burn_uniform_angle_rasters () { gdal_create -of GTiff -ot Float32 -bands 1 -burn $1 -outsize 1830 1830 -a_srs $2 -a_ullr $3 $4; }

ULLR () { echo $(gdalinfo $1 | grep -oP "(?<=Upper Left  \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g") \
               $(gdalinfo $1 | grep -oP "(?<=Lower Right \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g" ); }

EPSG () { gdalinfo $1 | grep -oP "(?<=\"EPSG\",)\d{5}" ; }


TILE=$(echo $s2_dir | grep -oP "(?<=_)\w{6}(?=_\d{8}T\d{6}.SAFE)")
ID=$(basename $s2_dir | grep -oP ".*(?=.SAFE)");
s2_dir=$__DIR__/$s2_dir

read -d '\n' -a ZENITHS < <(cat $s2_dir/GRANULE/*/MTD_TL.xml | grep -oP "(?<=<ZENITH_ANGLE unit=\"deg\">)[0-9\.]*(?=</ZENITH_ANGLE>)");

echo
echo Tile ID: $ID;

mkdir -p $__DIR__/$TILE

# MAKE BANDS FLOAT32 IF ZENITH BANDS TO BE INTEGRATED.
# for __jp2__ in $s2_dir/GRANULE/*/IMG_DATA/*B[0-9][0-9A].jp2
# do
#         gdal_translate -of VRT -ot Float32 $__jp2__ ${__jp2__%.*}_.vrt
# done

mv $s2_dir/GRANULE/*/IMG_DATA/*B[0-9][0-9A]*.jp2 $__DIR__/$TILE;

echo "Building VRT file for merged Sentinel-2 scene."

# TODO ZENITH BANDS APPROACH IS COMMENTED OUT FOR NOW. STICKING TO THE METADATA APPROACH.

# epsg=$(EPSG $__DIR__/$TILE/*B01_.vrt)
# ullr=$(ULLR $__DIR__/$TILE/*B01_.vrt)

# burn_uniform_angle_rasters ${ZENITHS[0]} "EPSG:$epsg" "$ullr" "$__DIR__/$TILE/solar_zenith_.vrt"
# burn_uniform_angle_rasters ${ZENITHS[9]} "EPSG:$epsg" "$ullr" "$__DIR__/$TILE/sat_zenith_.vrt"

# TODO Can make a python component that get the precise gridded zenith values.

gdalbuildvrt -resolution highest\
 -separate $__DIR__/$TILE/merged.vrt\
  $__DIR__/$TILE/*{B01,B02,B03,B04,B05,B06,B07,B08,B8A,B09,B10,B11,B12}.jp2 

echo
echo "Building multiband TIF file for Sentinel-2 scene."

gdal_translate -co "COMPRESS=LZW" -mo "S2_PRODUCT=$ID" \
        -mo "ZENITH_SOLAR=${ZENITHS[0]}"\
        -mo "ZENITH_B01=${ZENITHS[1]}"\
        -mo "ZENITH_B02=${ZENITHS[2]}"\
        -mo "ZENITH_B03=${ZENITHS[3]}"\
        -mo "ZENITH_B04=${ZENITHS[4]}"\
        -mo "ZENITH_B05=${ZENITHS[5]}"\
        -mo "ZENITH_B06=${ZENITHS[6]}"\
        -mo "ZENITH_B07=${ZENITHS[7]}"\
        -mo "ZENITH_B08=${ZENITHS[8]}"\
        -mo "ZENITH_B8A=${ZENITHS[9]}"\
        -mo "ZENITH_B09=${ZENITHS[10]}"\
        -mo "ZENITH_B10=${ZENITHS[11]}"\
        -mo "ZENITH_B11=${ZENITHS[12]}"\
        -mo "ZENITH_B12=${ZENITHS[13]}"\
        $__DIR__/$TILE/merged.vrt $__DIR__/$TILE/S2MSI.tmp.tif &&\
        rm -r $__DIR__/$TILE/*.{vrt,jp2} $s2_dir;


