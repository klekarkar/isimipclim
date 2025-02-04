import os
import xarray as xr
import requests
from pathlib import Path
from typing import List, Union, Tuple, Optional, Dict
from concurrent.futures import ThreadPoolExecutor
import logging
import subprocess

def create_ncml_files(
    model_choices: Union[str, List[str]],
    scenario: str,
    output_dir: str,
    conda_env: str
) -> None:
    """
    Create ncml files using the climate4R package in the specified conda environment.
    
    Args:
        model_choices: Model name(s) or "all"
        scenario: Scenario name or "all"
        output_dir: Base directory containing the downloaded files
        conda_env: Name of conda environment with climate4R installed
    """
    logger = logging.getLogger(__name__)
    
    valid_models = ["GFDL-ESM4", "MPI-ESM1-2-HR", "IPSL-CM6A-LR", "MRI-ESM2-0", "UKESM1-0-LL"]
    valid_scenarios = ["historical", "ssp126", "ssp585"]
    
    # Handle "all" options
    models = valid_models if model_choices == "all" else ([model_choices] if isinstance(model_choices, str) else model_choices)
    scenarios = valid_scenarios if scenario == "all" else [scenario]
    
    # Create ncml directory
    ncml_dir = Path(output_dir) / "ncml"
    
    for scen in scenarios:
        (ncml_dir / scen).mkdir(parents=True, exist_ok=True)
        
        for model in models:
            source_dir = Path(output_dir) / model / scen
            if not source_dir.exists():
                logger.warning(f"Directory {source_dir} does not exist, skipping...")
                continue
                
            ncml_file = ncml_dir / scen / f"{model}_{scen}.ncml"
            
            # R script to create ncml file
            r_script = f"""
            library(loadeR)
            makeAggregatedDataset(
                source.dir='{source_dir}',
                ncml.file='{ncml_file}'
            )
            """
            
            try:
                # Run R script in conda environment
                cmd = f"conda run -n {conda_env} Rscript -e '{r_script}'"
                subprocess.run(cmd, shell=True, check=True)
                logger.info(f"Successfully created ncml file: {ncml_file}")
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to create ncml file for {model} {scen}: {str(e)}")

def combine_netcdf_files(
    model_choices: Union[str, List[str]],
    scenario: str,
    output_dir: str,
) -> None:
    """
    Combine all NetCDF files for each model into a single file per model.
    Files are combined across time periods and variables, organized by scenario.
    
    Args:
        model_choices: Model name(s) or "all"
        scenario: Scenario name or "all"
        output_dir: Base directory containing the downloaded files
    """
    logger = logging.getLogger(__name__)
    
    valid_models = ["GFDL-ESM4", "MPI-ESM1-2-HR", "IPSL-CM6A-LR", "MRI-ESM2-0", "UKESM1-0-LL"]
    valid_scenarios = ["historical", "ssp126", "ssp585"]
    
    # Handle "all" options
    models = valid_models if model_choices == "all" else ([model_choices] if isinstance(model_choices, str) else model_choices)
    scenarios = valid_scenarios if scenario == "all" else [scenario]
    
    # Create combined directory
    combined_dir = Path(output_dir) / "combined"
    combined_dir.mkdir(parents=True, exist_ok=True)
    
    for scen in scenarios:
        # Create scenario subdirectory
        scen_dir = combined_dir / scen
        scen_dir.mkdir(parents=True, exist_ok=True)
        
        for model in models:
            source_dir = Path(output_dir) / model / scen
            if not source_dir.exists():
                logger.warning(f"Directory {source_dir} does not exist, skipping...")
                continue
            
            # Find all netcdf files for this model/scenario
            nc_files = list(source_dir.glob("*_cropped.nc"))
            if not nc_files:
                logger.warning(f"No NetCDF files found in {source_dir}")
                continue
                
            try:
                logger.info(f"Combining files for {model} {scen}...")
                
                # Open all files as a single dataset
                ds = xr.open_mfdataset(
                    nc_files,
                    combine='by_coords',  # Combines along existing dimensions
                    parallel=True,  # Enable parallel processing
                    preprocess=lambda ds: ds.sortby('time')  # Ensure time dimension is sorted
                )
                
                # Save combined dataset in scenario subdirectory
                output_file = scen_dir / f"{model}_combined.nc"
                ds.to_netcdf(
                    output_file,
                    mode='w',
                    format='NETCDF4',
                    compute=True
                )
                ds.close()
                
                logger.info(f"Successfully created combined file: {output_file}")
                
            except Exception as e:
                logger.error(f"Failed to combine files for {model} {scen}: {str(e)}")

def download_isimip_data(
    model_choices: Union[str, List[str]],
    variables: Union[str, List[str]],
    scenario: str,
    bbox: Optional[Tuple[float, float, float, float]] = None,
    output_dir: str = ".",
    max_workers: int = 5,
    combine_files: bool = False
) -> None:
    """
    Download and process ISIMIP 3 climate data with specified parameters.
    
    Args:
        model_choices: Model name(s) or "all". Valid models: GFDL-ESM4, MPI-ESM1-2-HR, 
                      IPSL-CM6A-LR, MRI-ESM2-0, UKESM1-0-LL
        variables: Climate variable(s). Valid options: hurs, huss, pr, prsn, ps, tas, tasmax, tasmin
        scenario: Climate scenario or "all". Valid options: historical, ssp126, ssp585
        bbox: Optional bounding box for cropping (xmin, xmax, ymin, ymax)
        output_dir: Directory to save downloaded files
        max_workers: Maximum number of concurrent downloads
        combine_files: If True, combine all files for each model into a single NetCDF file
    """
    # Setup logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # Validate and process inputs
    valid_models = {
        "GFDL-ESM4": "gfdl-esm4",
        "MPI-ESM1-2-HR": "mpi-esm1-2-hr",
        "IPSL-CM6A-LR": "ipsl-cm6a-lr",
        "MRI-ESM2-0": "mri-esm2-0",
        "UKESM1-0-LL": "ukesm1-0-ll"
    }
    
    valid_variables = ["hurs", "huss", "pr", "prsn", "ps", "tas", "tasmax", "tasmin"]
    valid_scenarios = ["historical", "ssp126", "ssp585"]

    # Convert inputs to lists if they're strings
    if isinstance(model_choices, str):
        model_choices = [model_choices]
    if isinstance(variables, str):
        variables = [variables]
    
    # Handle "all" options
    if "all" in model_choices:
        model_choices = list(valid_models.keys())
    if scenario == "all":
        scenarios = valid_scenarios
    else:
        scenarios = [scenario]

    # Validate inputs
    for model in model_choices:
        if model not in valid_models:
            raise ValueError(f"Invalid model: {model}. Valid models: {list(valid_models.keys())}")
    
    for var in variables:
        if var not in valid_variables:
            raise ValueError(f"Invalid variable: {var}. Valid variables: {valid_variables}")
    
    for scen in scenarios:
        if scen not in valid_scenarios:
            raise ValueError(f"Invalid scenario: {scen}. Valid scenarios: {valid_scenarios}")

    base_url = "https://files.isimip.org/ISIMIP3b/InputData/climate/atmosphere/bias-adjusted/global/daily"

    def process_file(model: str, variable: str, scen: str, year: int) -> None:
        """Download and process a single file."""
        model_lower = valid_models[model]
        experiment = "r1i1p1f2" if model == "UKESM1-0-LL" else "r1i1p1f1"
        
        # Calculate end year
        if scen == "historical":
            end_year = min(year + 9, 2014)
            if end_year < year:
                return
        else:
            end_year = year + 9

        # Create output directory
        out_dir = Path(output_dir) / model / scen
        out_dir.mkdir(parents=True, exist_ok=True)

        # Construct file names
        file_name = f"{model_lower}_{experiment}_w5e5_{scen}_{variable}_global_daily_{year}_{end_year}"
        url = f"{base_url}/{scen}/{model}/{file_name}.nc"
        output_file = out_dir / f"{file_name}_cropped.nc"

        if output_file.exists():
            logger.info(f"File already exists: {output_file}")
            return

        try:
            # Download and process with xarray
            logger.info(f"Downloading {url}")
            ds = xr.open_dataset(url, engine='netcdf4')

            # Crop if bbox is provided
            if bbox:
                ds = ds.sel(
                    lon=slice(bbox[0], bbox[1]),
                    lat=slice(bbox[2], bbox[3])
                )

            # Save to netcdf
            ds.to_netcdf(output_file)
            ds.close()
            logger.info(f"Successfully processed: {output_file}")

        except Exception as e:
            logger.error(f"Error processing {url}: {str(e)}")

    # Create download tasks
    tasks = []
    for model in model_choices:
        for scen in scenarios:
            for var in variables:
                if scen == "historical":
                    years = range(1971, 2011, 10)
                else:
                    years = range(2021, 2091, 10)
                
                for year in years:
                    tasks.append((model, var, scen, year))

    # Execute downloads in parallel
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        executor.map(lambda x: process_file(*x), tasks)

    # After downloads complete, create ncml files if conda_env is specified
    if conda_env:
        logger.info(f"Creating ncml files using conda environment: {conda_env}")
        create_ncml_files(model_choices, scenario, output_dir, conda_env)

    # After downloads complete, combine files if requested
    if combine_files:
        logger.info("Combining NetCDF files...")
        combine_netcdf_files(model_choices, scenario, output_dir)

# Example usage
if __name__ == "__main__":
    # Example with cropping to a specific region and file combination
    download_isimip_data(
        model_choices="GFDL-ESM4",
        variables=["tas", "pr"],
        scenario="historical",
        bbox=(-10, 40, 35, 70),  # Europe
        output_dir="isimip_data",
        combine_files=True  # Enable file combination
    ) 