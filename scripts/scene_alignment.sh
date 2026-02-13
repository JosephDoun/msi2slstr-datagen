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

# Reference to the original Sentinel-3 scene.
S3FILE="$__DIR__/../S3SLSTR.tif"

ULLR () { 
	echo $(gdalinfo $1 | grep -oP \
		"(?<=Upper Left  \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g")\
		$(gdalinfo $1 | grep -oP\
			   "(?<=Lower Right \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g" );
}

EXTENT () { 
	echo $(gdalinfo $1 | grep -oP \
		"(?<=Lower Left  \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g")\
		$(gdalinfo $1 | grep -oP\
			   "(?<=Upper Right \(  )\d+\.\d+, \d+\.\d+(?=\))" | sed "s/,//g" );
}

# Iterate over available tile folders.
if [ ! -e $__DIR__/S2MSI.tmp.tif ];
then 
	scripts/log.sh "Folder lacks a processed Sentinel-2 scene. Skipping." 1>&2;
	exit 1; 
fi

EPSG=$(gdalinfo $__DIR__/S2MSI.tmp.tif | grep -oP "(?<=\"EPSG\",)\d{5}")


scripts/log.sh "EPSG: $EPSG Extents: $(ULLR $__DIR__/S2MSI.tmp.tif | sed "s/\.[0-9]\{3\}//g")" 1>&2;
scripts/log.sh "Generating projected Sentinel-3 patch matching the Sentinel-2 scene." 1>&2;


# Capture footprints.
read -a S2BOX < <(ULLR $__DIR__/S2MSI.tmp.tif | sed "s/\.[0-9]\+//g")
read -a S3BOX < <(ULLR $S3FILE | sed "s/\.[0-9]\+//g")

read -a S2EXTENT < <(EXTENT $__DIR__/S2MSI.tmp.tif | sed "s/\.[0-9]\+//g")
read -a S3EXTENT < <(EXTENT $S3FILE | sed "s/\.[0-9]\+//g")


# Create a binary mask for the reference image.
# Turn s2bin into a 500m mask
# or 2500m mask (corresponding to min tile dimensions)
S2MASK=$__DIR__/s2mask.shp
gdal_calc -A $__DIR__/S2MSI.tmp.tif --A_band=2 --outfile=$__DIR__/s2bin.tmp.tif --calc="1 * (A > 0)" --NoDataValue 0 1>&2;
gdal_translate -tr 2500 2500 -r near $__DIR__/s2bin.tmp.tif $__DIR__/s2bin.resampled.tif
gdal_polygonize $__DIR__/s2bin.resampled.tif $S2MASK 1>&2;


# Sentinel-3 validity mask.
# WARNING: This raster is not projected yet. Its units are lat/lon.
S3MASK=$__DIR__/s3mask.shp
gdal_calc -A $S3FILE \
	--A_band=1 \
	--outfile=$__DIR__/s3bin.tmp.tif \
	--calc="1 * (A > 0)" \
	--NoDataValue 0 1>&2;
gdal_polygonize $__DIR__/s3bin.tmp.tif \
	$__DIR__/s3mask.intermediate.shp 1>&2;
# Project to Sentinel-2 coordinate system.
ogr2ogr -t_srs EPSG:$EPSG \
	$S3MASK $__DIR__/s3mask.intermediate.shp;


# Definition of the final mask to use for clipping.
MASK=$__DIR__/mask.shp
# Use the Sentinel-2 valid footprint geometry
# to clip the Sentinel-3 valid footprint and
# form the intersection geometry used for
# clipping.
ogr2ogr -clipsrc $S2MASK \
	-clipsrcwhere "DN = 1" \
	-where "DN = 1" \
	$MASK $S3MASK 1>&2;


# Cast S3 SRS to Sentinel-2 UTM grid.
# Use bilinear interpolation for cell resolution adjustments.
gdalwarp -r bilinear \
	-srcalpha \
	-dstalpha \
	-multi \
	-cutline $MASK \
	-crop_to_cutline \
	-cwhere "DN = 1"\
	-srcnodata 0 \
	-dstnodata 0 \
	-tr 500 500 \
	-s_srs "EPSG:4326" \
	-t_srs "EPSG:$EPSG" \
	"$S3FILE" \
	"$__DIR__/s3.patch.tmp.tif" \
	-overwrite 1>&2;


# This performs a cropping action to projwin box.
# Shifting should likely not use bilinear interpolation,
# but instead shift absolute neighbouring values.
echo $__DIR__ $(ULLR $__DIR__/S2MSI.tmp.tif) 1>&2;
echo $__DIR__ $(ULLR $__DIR__/s3.patch.tmp.tif) 1>&2;


########################################################
# COREGISTRATION
########################################################
scripts/log.sh "Starting arosics workflow for $__DIR__.";
arosics local \
	-progress 0 \
	-rsp_alg_calc 0 \
	-rsp_alg_deshift 0 \
	-br 8 \
	-bs 3 \
	-fmt_out GTIFF \
	-ws 96 96 \
	-nodata 0 0 \
	-min_reliability 60 \
	$__DIR__/S2MSI.tmp.tif \
	$__DIR__/s3.patch.tmp.tif \
	22 \
	-o "$__DIR__/s3.coreg.tif" 1>&2 && \
	rm $__DIR__/s3.patch.tmp.tif


# If output file was not generated continue to next iteration.
if [[ ! -e "$__DIR__/s3.coreg.tif" ]]
then
	scripts/log.sh "Arosics coregistration workflow failed. Aborting." 1>&2;
	exit 1;
fi


# Center cropping with 4 pixels distance.
# Why do we need that?
scripts/log.sh "Cropping Sentinel-3 to a 210 x 210 pixels scene.";
gdal_translate \
	-srcwin 4 4 210 210 \
	-ot float32 \
	$__DIR__/s3.coreg.tif \
	$__DIR__/S3SLSTR.tmp.tif &&\
    rm $__DIR__/s3.coreg.tif;


# Get refined Sentinel-3 footprint mask here.
# Generate the default mask,
# Resample it to 2.500m (minimal patch size)
# And finally generate the cookie cutter.
gdal_calc -A $__DIR__/S3SLSTR.tmp.tif \
	--overwrite \
	--A_band=1 \
	--outfile=$__DIR__/s3bin.tmp.tif \
	--calc="1 * (A > 0)" \
	--NoDataValue 0 1>&2 && \
	gdal_translate -r nearest \
		-tr 2500 2500 \
		$__DIR__/s3bin.tmp.tif \
		$__DIR__/s3bin.resampled.tif && \
	gdal_polygonize -overwrite \
		$__DIR__/s3bin.resampled.tif $S3MASK 1>&2


# Replace ogr2ogr for gdal_polygonize
# of the mutual raster mask?
# Update intersection mask.
ogr2ogr -clipsrc $S3MASK \
	-clipsrcwhere "DN = 1" \
	-overwrite \
	-where "DN = 1" \
	$MASK $S2MASK 1>&2;


# LAST STEP: Crop S2MSI image to rounded S3 extents.
scripts/log.sh "Cropping Sentinel-2 scene to the exact extents of the generated Sentinel-3 patch.";
echo "From ${S2BOX[@]}";
echo "To   ${S3BOX[@]}";


# Keep the intersection of the Sentinel-2 scene.
# Use S3MASK as cutline.
gdalwarp -r bilinear \
	-multi \
	-cutline $MASK \
	-crop_to_cutline \
	-cwhere "DN = 1"\
	-srcnodata 0 \
	-dstnodata 0 \
	-co "COMPRESS=ZSTD" \
	-co "TILED=YES" \
	-co "PREDICTOR=2" \
	-co "BLOCKXSIZE=16" \
	-co "BLOCKYSIZE=16" \
	-ot int16 \
	"$__DIR__/S2MSI.tmp.tif" \
	"$__DIR__/S2MSI.tif" \
	-overwrite 1>&2 \
	&& rm "$__DIR__/S2MSI.tmp.tif";


gdalwarp -r bilinear \
	-multi \
	-cutline $MASK \
	-crop_to_cutline \
	-cwhere "DN = 1"\
	-srcnodata 0 \
	-dstnodata 0 \
	-co "COMPRESS=ZSTD" \
	-co "PREDICTOR=2" \
	-co "TILED=YES" \
	-co "BLOCKXSIZE=16" \
	-co "BLOCKYSIZE=16" \
	-ot float32 \
	"$__DIR__/S3SLSTR.tmp.tif" \
	"$__DIR__/S3SLSTR.tif" \
	-overwrite 1>&2 \
	&& rm "$__DIR__/S3SLSTR.tmp.tif";


shopt -s extglob

# Cleanup.
# Clear ancillary files.
rm $__DIR__/s2bin.*.tif $__DIR__/s3bin.*.tif;
rm $__DIR__/*.!(tif);
