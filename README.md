[![weekly scheduled query api verification workflow](https://github.com/JosephDoun/msi2slstr-datagen/actions/workflows/test_workflows.yml/badge.svg?branch=main&event=schedule)](https://github.com/JosephDoun/msi2slstr-datagen/actions/workflows/test_workflows.yml) [![query api verification workflow](https://github.com/JosephDoun/msi2slstr-datagen/actions/workflows/test_workflows.yml/badge.svg?branch=main&event=push)](https://github.com/JosephDoun/msi2slstr-datagen/actions/workflows/test_workflows.yml)

# msi2slstr-datagen 
## Scripted workflow for the generation of a msi2slstr training dataset.

This script uses the OData API of the [Copernicus Data Space Ecosystem](https://dataspace.copernicus.eu).
For using it, you will need to create a free account and provide the credentials as environmental variables
as described in help-docs, during script execution or globally.


```shell
msi2slstr.sh script usage help -- intended for bash shell
	
msi2slstr.sh:
$ DATASPACE_USERNAME=<Account email> DATASPACE_PASSWORD=<Account password> ./msi2slstr-datagen.sh [-l lon lat] [-o dir] date ...
  
  Set the environment variables DATASPACE_USERNAME, DATASPACE_PASSWORD to 
  provide credentials to the catalogue.dataspace.copernicus.eu service.

  Options:
	-l, --location lon lat	The longitude and latitude of the intersection to
				use for querying Sentinel-3 images.
				Defaults to 10 50 (Central Europe).
	-t, --time     seconds	The maximum number of seconds of acquisition difference
				that is allowed between Sentinel-3 and Sentinel-2 scenes.
				Defaults to 300 (5 minutes).
	-o, --output   dir      The output directory in which to build the dataset.
				Defaults to "./s2lstr-dataset".
```

Example usage:
`... ./msi2slstr-datagen.sh 2023-01-{1..31}`

The above example will look for appropriate pairs for every day of January 2023 and if found, will proceed with downloading and preparing them.


## Dependencies
- curl
- gdal
- arosics

#### How to cite:
*Doundoulakis, I. (2024) “msi2slstr-datagen: A collection of bash scripts for the generation of Sentinel-2 L1C and Sentinel-3 SLSTR pairs of products.”. Zenodo. doi: 10.5281/zenodo.13760441.*
