# Script for automated image coregistration.
# Crop the corresponding S3 parcel to a S2 footprint.
# Apply correlation based coregistration.
#
# Parameters:
#       -d/--dir: The directory holding the images set for alignment.
#

# Exit if directory parameter not provided.
if [ $# -eq 0 ]; then echo $0 " -> " Use -d/--dir to provide a directory.; exit 1; fi

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

S3FILE=$__DIR__/S3SLSTR.tif

ULLR () { echo $(gdalinfo $1 | grep -oP "(?<=Upper Left  \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g") \
               $(gdalinfo $1 | grep -oP "(?<=Lower Right \(  )\d*\.\d{3}, \d*\.\d{3}(?=\))" | sed "s/,//g" ); }

N=1;
for s2dir in $__DIR__/??????
do      
        if [ ! -f $s2dir/S2MSI.tmp.tif ];
        then 
        scripts/log.sh "Folder appears processed or invalid. Skipping."; continue; 
        fi
        
        EPSG=$(gdalinfo $s2dir/S2MSI.tmp.tif | grep -oP "(?<=\"EPSG\",)\d{5}")

        scripts/log.sh "EPSG: $EPSG Extents:\
			$(ULLR $s2dir/S2MSI.tmp.tif | sed "s/\.[0-9]\{3\}//g")"
        scripts/log.sh "Generating projected Sentinel-3\
			patch matching the Sentinel-2 scene." 1>&2;
        
        # Cast S3 SRS to Sentinel-2 UTM grid.
        gdalwarp -r bilinear -tr 500 500 -s_srs EPSG:4326 \
        -t_srs EPSG:$EPSG $S3FILE $s2dir/s3.tmp.tif -co "COMPRESS=LZW" \
        -overwrite;


        # This performs a cropping action to projwin box.
        gdal_translate -projwin $(ULLR $s2dir/S2MSI.tmp.tif) \
        -projwin_srs EPSG:$EPSG $s2dir/s3.tmp.tif $s2dir/s3.patch.tmp.tif \
        -co "COMPRESS=LZW" &&\
        rm $s2dir/s3.tmp.tif
        
        # TODO Extend to check Sentinel-3 patch has sufficient valid values.
        # TODO Change check if patch it empty to condition patch valid samples > acceptable percentage.

        scripts/log.sh "Checking Sentinel-3 patch validity.";
        
        VALID=$(gdalinfo -stats $s2dir/s3.patch.tmp.tif |\
         grep -oP "(?<=STATISTICS_VALID_PERCENT=)\d+" | head -n 1)
        
		if [ $VALID -lt 50 ];
        then 
                scripts/log.sh "Sentinel-3 patch out of sensor geometry. Removing directory."
                rm -r $s2dir && continue;
        else
                scripts/log.sh "Image OK."
                rm $s2dir/s3.patch.tmp.tif.aux.xml;
        fi


        # Here we can perform the coregistration and produce
        # a coregistered S3SLSTR_N.tif.
		scripts/log.sh "Starting arosics workflow for $s2dir.";

        arosics local -rsp_alg_calc 1 -rsp_alg_deshift 1 -br 9 -bs 3 -fmt_out GTIFF -ws 32 32\
         -nodata "0" "-32768" -max_shift 5 -min_reliability 0\
          $s2dir/S2MSI.tmp.tif $s2dir/s3.patch.tmp.tif 2\
          -o "$s2dir/s3_coreg.tif" 2> /dev/null && rm $s2dir/s3.patch.tmp.tif

        # If output file was not generated continue to next iteration.
        [[ ! -f "$s2dir/s3_coreg.tif" ]] &&\
			scripts/log.sh "Arosics workflow failed. Skipping." && continue;
        
        scripts/log.sh "Cropping Sentinel-3 to a 210 x 210 pixels scene." 1>&2;

        gdal_translate -srcwin 4 4 210 210\
        -co "COMPRESS=LZW" $s2dir/s3_coreg.tif $s2dir/S3SLSTR_$N.tif &&\
          rm $s2dir/s3_coreg.tif

        read -a S2BOX < <(ULLR $s2dir/S2MSI.tmp.tif | sed "s/\.[0-9]\+//g")
        read -a S3BOX < <(ULLR $s2dir/S3SLSTR_$N.tif | sed "s/\.[0-9]\+//g")
        
        # LAST STEP: Crop S2MSI image to rounded S3 extents.
        scripts/log.sh "Cropping Sentinel-2 scene to the exact extents of the generated Sentinel-3 patch.";
		
        scripts/log.sh "From '${S2BOX[@]}'";
        scripts/log.sh "To   '${S3BOX[@]}'";

        gdal_translate -co "COMPRESS=DEFLATE" -co "TILED=YES"\
			-co "PREDICTOR=2" -co "BLOCKXSIZE=16"\
			-co "BLOCKYSIZE=16" -projwin ${S3BOX[@]}\
         $s2dir/S2MSI.tmp.tif $s2dir/S2MSI_$N.tif &&\
         rm $s2dir/S2MSI.tmp.tif;

        ((N++));
done

# Sentinel-3 file not necessary.
# rm $S3FILE;

# Check there are subdirectories remaining (directory is empty).
# Otherwise remove root directory of S3 acquisition.
# if [ -z "$(ls -A $__DIR__)" ]; then rmdir $__DIR__; fi

