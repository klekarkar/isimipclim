# Automatically download and process ISIMIP3a-b climate data
The script folder contains the function that needs to be called from a shell to download and then aggregate (optional) the netCDF files into ncml files. For this last step, it is necessary to have a conda environment with R and climate4R packages installed. 

## How to run the function
Open a terminal, place the isimip.sh script anywhere and run:

```
bash isimip.sh
```
```
Download climate data with specified parameters.

Options:
  -m   model_choices    Specify the model choices: GFDL-ESM4, MPI-ESM1-2-HR, IPSL-CM6A-LR, MRI-ESM2-0, UKESM1-0-LL, all
  -v   variable         Specify one or more variables separated by space: hurs, huss, pr, prsn, ps, tas, tasmax, tasmin. Enclose multiple variables in quotes (e.g tas hurs)
  -s   scenario         Specify the scenario: historical, ssp126, ssp585, all
  -x   xmin             Specify the minimum longitude value for cropping (optional)
  -x   xmax             Specify the maximum longitude value for cropping (optional)
  -y   ymin             Specify the minimum latitude value for cropping (optional)
  -y   ymax             Specify the maximum latitude value for cropping (optional)


```
Example:

```
bash ismip.sh -m all -v tas -s historical -x -120 -100 -y 30 40

Please specify a conda environment to activate if ncml files are to be generated. Type 'no' if you want to only download the data.
Conda environment: 


```

This would Download for all models and scenarios, the daily data for tas. Generating ncml files requires the installation of R and climate4R packages (loadeR in particular). 
