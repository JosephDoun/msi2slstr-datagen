# Purpose:
# Build a georeferenced TIF of a combined S3 SLSTR product.
#
# This module processes pairs of Sentinel-3 RBT and LST SAFE directories
# to generate single combined TIF images containing:
#       1. 11 upsampled bands of RBT S3 product.
#       2. An upsampled LST band from the corresponding LST product.
#       3. Sensor and solar zenith angles as additional bands.

# If parameters not provided exit.
if [ $# -eq 0 ]; then echo Use -d/--dir to specify data directory.; exit 1; fi

# Parse parameters.
# __DIR__ variable holds the root directory containing
# the RBT and LST products of same date.
while [[ $# -gt 0 ]]
do
        case "$1" in
                -d|--dir) __DIR__="$2"; shift 2;;
                *) echo Unknown argument. Use -d/--dir to specify data directory.;
                exit 1;;
        esac
done

# Variable containing the path to the RBT product.
RBT=$(echo $__DIR__/S3*SL_1_RBT*)

# Variable containing the path to the LST product.
LST=$(echo $__DIR__/S3*SL_2_LST*)

# If product directories do not exist throw error and exit.
# Current exit code for this case: 11.
if [ ! -d $RBT ] && [ ! -d $LST ];
then
        scripts/log.sh "ERROR: Sentinel-3 directories not found. Exiting."; 
        exit 11; 
fi;

# Declare and create tmp directory for intermediate products.
__TMP__=$__DIR__/tmp
mkdir -p $__TMP__

# Move all NETCDFs of interest to the temporary directory.
mv $RBT/{geod*,S*radiance,S*BT,F*BT}_[iaf]n.nc $LST/LST_in.nc $__TMP__;

subdataset_name () {
# Parse input parameter to return mapped name of contained subdataset.
# Parameter $1: String describing the file of interest.
# Returns: The subdataset name inside file.
        case $1 in
                # Radiance files echo name without file extension.
                S*_radiance_an.nc|[SF]*_BT_*.nc) echo ${1%.*};;
                # LST_in file returns `LST`
                LST_in.nc) echo LST;;
                # Geodetic files return
                geodetic_*.nc) echo $1 | grep -o [afit][nx];;
                geometry_tn.nc) echo solar_zenith_tn;;
        esac
}


buildvrt () { 
# Builds a vrt file describing a Sentinel-3 band.
# Change: Float64 output type to Float32
gdal_translate -unscale -of VRT -a_nodata "-32768" -ot Float32 $1 $__TMP__/$2.vrt;
}

geolocation () {
# Georeference data injection function.
# It inserts the georeference bands according to the VRT specification
# to be used for generating a georeferenced tiff upon transformation.
# NOTE: This can be instead injected with gdal_translate more correctly.
        echo "`cat <<EOF
\ \ <Metadata Domain=\"GEOLOCATION\">\n\
    <MDI key=\"X_DATASET\">$__TMP__/lon_$1.vrt</MDI>\n\
    <MDI key=\"X_BAND\">1</MDI>\n\
    <MDI key=\"Y_DATASET\">$__TMP__/lat_$1.vrt</MDI>\n\
    <MDI key=\"Y_BAND\">1</MDI>\n\
    <MDI key=\"Z_DATASET\">$__TMP__/elev_$1.vrt</MDI>\n\
    <MDI key=\"Z_BAND\">1</MDI>\n\
    <MDI key=\"PIXEL_OFFSET\">0</MDI>\n\
    <MDI key=\"PIXEL_STEP\">1</MDI>\n\
    <MDI key=\"LINE_OFFSET\">0</MDI>\n\
    <MDI key=\"LINE_STEP\">1</MDI>\n\
  </Metadata>
EOF
`"
}

# Iterate over NETCDF datasets contained in the tmp directory.
# First handle geodetic, emission and radiance datasets.
for __file__ in $__TMP__/{geod*,LST,S*radiance,S*BT,F*BT}_[iaf]n.nc
do
        # Log file currently handled.
        scripts/log.sh "$__file__";

        if [ -f $__file__ ]
        then
                # Detach filename from path.
                BASE=$(basename $__file__)
                
				if [ ${BASE%%_*} == "geodetic" ]
                then
                        GRID=$(subdataset_name $BASE)
                        buildvrt NETCDF:$__file__:longitude_$GRID lon_$GRID
                        buildvrt NETCDF:$__file__:latitude_$GRID lat_$GRID
                        buildvrt NETCDF:$__file__:elevation_$GRID elev_$GRID
                else
                        NAME=$(subdataset_name $BASE)
                        GRID=${BASE##*_}
                        GRID=${GRID%.*}
                        
                        scripts/log.sh "$NAME $GRID"
                        buildvrt NETCDF:$__file__:$NAME $NAME
                        
                        scripts/log.sh "$__TMP__/$NAME.vrt"

                        # Inject geolocation array info.
                        sed -i "2 i $(geolocation $GRID)" $__TMP__/$NAME.vrt
                        
                        echo
                        gdalwarp -geoloc $__TMP__/$NAME.vrt $__TMP__/$NAME.tif -overwrite;
                        echo
                fi
        fi
done;

# Move geodetic datasets to tmp directory.
mv $RBT/geometry_tn.nc $RBT/geodetic_tx.nc $__TMP__;

# SOLAR ANCILLARY DATA
buildvrt "NETCDF:$__TMP__/geodetic_tx.nc:longitude_tx" lon_tx
buildvrt "NETCDF:$__TMP__/geodetic_tx.nc:latitude_tx" lat_tx

# Build zenith angles tifs.
for zenith in {solar_zenith_tn,solar_azimuth_tn,sat_zenith_tn,sat_azimuth_tn}
do
        buildvrt "NETCDF:$__TMP__/geometry_tn.nc:$zenith" $zenith
        sed -i "2 i $(geolocation tx)" $__TMP__/$zenith.vrt
        gdalwarp -geoloc $__TMP__/$zenith.vrt $__TMP__/$zenith.tif -overwrite
done

# Build merger VRT for complete S3 end-product.
gdalbuildvrt -resolution highest \
-separate $__TMP__/merged.vrt \
$__TMP__/{S1,S2,S3,S4,S5,S6,S7,S8,S9,F1,F2,LST,solar_zenith,solar_azimuth,sat_zenith,sat_azimuth}*.tif

# Inject metadata and build end-product.
# Clean leftover directories.
# Include copernicus identifier as metadata in TIF.
gdal_translate -mo "S3_RBT_PRODUCT=$(basename $RBT)" \
-mo "S3_LST_PRODUCT=$(basename $LST)" \
-a_srs EPSG:4326 \
$__TMP__/merged.vrt $__DIR__/S3SLSTR.tif &&\
rm -r $RBT && rm -r $LST &&\
rm -r $__TMP__;

