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


echo $Q;

