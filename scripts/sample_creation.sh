# Script for the generation of samples (tiles).

if [ $# -eq 0 ]; then echo "Use -d/--dir to provide a directory."; exit 1; fi

while [ $# -gt 0 ]
do
        case $1 in
                -d|--dir) __DIR__=$2; shift 2;;
                -ps|--pixelsize) PXLSIZES2=$2; PXLSIZES3=$3; shift 3;;
                *) echo Unknown argument "$1". Use -d/--dir to provide a directory.; exit 1;;
        esac
done;

echo
echo Initiating sample generation for $( basename $__DIR__ ).

mkdir $__DIR__/{S2,S3}_patches

INJECT_MD () {
        # Write metadata iteratively to every input file.
        local -n METADATA=$1
        shift 1;
        for __patch__ in $@
        do
                gdal_edit.py ${METADATA[@]} $__patch__
        done
}

i=1;
for s2_dir in $__DIR__/??????
do      
        
        read -d '\n' -a S2MD < <(gdalinfo $s2_dir/S2MSI_*.tif | grep -P "ZENITH|PRODUCT" | sed "s/^\ */-mo\ /;")
        read -d '\n' -a S3MD < <(gdalinfo $s2_dir/S3SLSTR_*.tif | grep PRODUCT | sed "s/^\ */-mo\ /;")

        S2BASE=$(basename $s2_dir/S2MSI_*.tif); S2BASE=${S2BASE%.*};
        S3BASE=$(basename $s2_dir/S3SLSTR_*.tif); S3BASE=${S3BASE%.*};

        gdal_retile.py -ps 100 100 -co "COMPRESS=LZW" -overlap 50 -targetDir $__DIR__/S2_patches $s2_dir/S2MSI_*.tif &&\
        gdal_retile.py -ps 2 2 -co "COMPRESS=LZW" -overlap 1 -targetDir $__DIR__/S3_patches $s2_dir/S3SLSTR_*.tif &&\
        rm -r $s2_dir;
        
        INJECT_MD S2MD $__DIR__/S2_patches/$S2BASE*.tif &
        INJECT_MD S3MD $__DIR__/S3_patches/$S3BASE*.tif &

        ((i++));
done

rm $__DIR__/S3SLSTR.tif

wait
echo Sample generation finished for $(basename $__DIR__).

