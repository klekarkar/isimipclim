#!/bin/bash

# Help documentation
usage() {
    echo "Usage: $0 -m model_choices -v variable -s scenario [-x xmin xmax] [-y ymin ymax]"
    echo
    echo "Download ISIMIP 3 climate data with specified parameters."
    echo
    echo "Options:"
    echo "  -m   model_choices    Specify the model choices: GFDL-ESM4, MPI-ESM1-2-HR, IPSL-CM6A-LR, MRI-ESM2-0, UKESM1-0-LL, all"
    echo "  -v   variable         Specify one or more variables separated by space: hurs, huss, pr, prsn, ps, tas, tasmax, tasmin. Enclose multiple variables separated by a space in quotes"
    echo "  -s   scenario         Specify the scenario: historical, ssp126, ssp585, all"
    echo "  -x   xmin             Specify the minimum longitude value for cropping (optional)"
    echo "  -x   xmax             Specify the maximum longitude value for cropping (optional)"
    echo "  -y   ymin             Specify the minimum latitude value for cropping (optional)"
    echo "  -y   ymax             Specify the maximum latitude value for cropping (optional)"
    exit 1
}

# Validate model_choices
validate_model_choices() {
    local model=$1
    if [[ $model != "GFDL-ESM4" && $model != "MPI-ESM1-2-HR" && $model != "IPSL-CM6A-LR" && $model != "MRI-ESM2-0" && $model != "UKESM1-0-LL" && $model != "all" ]]; then
        echo "Error: Invalid model_choices. Choose one of the following: GFDL-ESM4, MPI-ESM1-2-HR, IPSL-CM6A-LR, MRI-ESM2-0, UKESM1-0-LL, all"
        usage
    fi
}

# Validate variable
validate_variable() {
    local var=$1
    local variables=()
    IFS=' ' read -r -a variables <<< "$var"
    for variable in "${variables[@]}"; do
        if [[ $variable != "hurs" && $variable != "huss" && $variable != "pr" && $variable != "prsn" && $variable != "ps" && $variable != "tas" && $variable != "tasmax" && $variable != "tasmin" ]]; then
            echo "Error: Invalid variable. Choose one of the following: hurs, huss, pr, prsn, ps, tas, tasmax, tasmin"
            usage
        fi
    done
}

# Validate scenario
validate_scenario() {
    local scen=$1
    if [[ $scen != "historical" && $scen != "ssp126" && $scen != "ssp585" && $scen != "all" ]]; then
        echo "Error: Invalid scenario. Choose one of the following: historical, ssp126, ssp585, all"
        usage
    fi
}

# Set default values for xlim and ylim
xlim=(-180 180)
ylim=(-90 90)

while getopts ":h:m:v:s:x:y:" opt; do
    case ${opt} in
        h)
            usage
            ;;
        m)
            validate_model_choices $OPTARG
            model_choices=$OPTARG
            ;;
        v)
            validate_variable $OPTARG
            variable=$OPTARG
            ;;
        s)
            validate_scenario $OPTARG
            scenario=$OPTARG
            ;;
        x)
            xlim=($OPTARG)
            ;;
        y)
            ylim=($OPTARG)
            ;;
        \?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
        :)
            echo "Invalid Option: -$OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Check if all required arguments are provided
if [[ -z $model_choices || -z $variable || -z $scenario ]]; then
    echo "Error: Missing arguments. All options (-m, -v, -s) must be specified."
    usage
fi

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    echo "wget could not be found, please install it"
    exit 1
fi

# Check if cdo is installed
if ! command -v cdo &> /dev/null; then
    echo "cdo could not be found, please install it"
    exit 1
fi

# Ask user for conda environment
echo "Please specify a conda environment to activate if ncml files are to be generated. Type 'no' if you only want to download the data. The required conda env installation instruction can be retrieved here https://github.com/SantanderMetGroup/climate4R"
read -p "Conda environment: " conda_env

if [[ $conda_env == "no" ]]; then
    echo "Skipping conda environment activation and create_ncml function."
else
    echo "Activating conda environment $conda_env..."

    # Activate the specified conda environment
    source activate "$conda_env"

    # Check if activation was successful
    if [[ $? -ne 0 ]]; then
        echo "Failed to activate conda environment $conda_env. Exiting."
        exit 1
    fi

    echo "Successfully activated conda environment $conda_env."
fi

# Define the model, variable, and scenario options
declare -A model_map=( ["GFDL-ESM4"]="gfdl-esm4" ["MPI-ESM1-2-HR"]="mpi-esm1-2-hr" ["IPSL-CM6A-LR"]="ipsl-cm6a-lr" ["MRI-ESM2-0"]="mri-esm2-0" ["UKESM1-0-LL"]="ukesm1-0-ll" )
declare -a variable_map=("hurs" "huss" "pr" "prsn" "ps" "tas" "tasmax" "tasmin")
declare -a scenario_map=("historical" "ssp126" "ssp585")

# Function to download files and crop them
download_model_files() {
    local model=$1
    local variables=() # Declare an array for variables
    IFS=' ' read -r -a variables <<< "$2" # Split the variables string into an array
    local scenarios=() # Declare an array for scenarios
    if [[ "$3" == "all" ]]; then
        scenarios=("historical" "ssp126" "ssp585")
    else
        scenarios=("$3")
    fi
    local xmin=$4
    local xmax=$5
    local ymin=$6
    local ymax=$7

    # Set the base URL
    base_url="https://files.isimip.org/ISIMIP3b/InputData/climate/atmosphere/bias-adjusted/global/daily"

    # Convert model to lowercase
    local lower_model=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    for variable in "${variables[@]}"; do
        for scenario in "${scenarios[@]}"; do # Loop over scenarios
            mkdir -p "${model}/${scenario}"

            if [[ "$model" == "UKESM1-0-LL" ]]; then
                experiment="r1i1p1f2"
            else
                experiment="r1i1p1f1"
            fi

            if [[ "$scenario" == "historical" ]]; then
                for year in $(seq 1971 10 2011); do
                    end_year=$((year+9))
                    [[ "$end_year" -gt 2014 ]] && end_year=2014
                    url="${base_url}/${scenario}/${model}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}.nc"
                    file="${model}/${scenario}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}.nc"

                    if [[ ! -f "$file" ]]; then
                        wget "$url" -P "${model}/${scenario}" || { echo "Failed to download $url"; }
                    else
                        echo "File $file already exists, skipping download."
                    fi

                    # Crop the file using cdo based on the provided xlim and ylim values
                    output_file="${model}/${scenario}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}_cropped.nc"
            
                    cdo_cmd="cdo sellonlatbox,${xmin},${xmax},${ymin},${ymax} $file $output_file"

                    echo "Executing cdo command: $cdo_cmd"
                  
                    eval "$cdo_cmd"
                    if [ $? -ne 0 ]; then
                        echo "Error executing cdo command: $cdo_cmd"
                    else
                        echo "Cropping successful: $output_file"
                        rm -f "$file"
                    fi
                done
            else
                # Similar logic for downloading and cropping files for other scenarios
                 for year in $(seq 2021 10 2091); do
                    end_year=$((year+9))
                    url="${base_url}/${scenario}/${model}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}.nc"
                    file="${model}/${scenario}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}.nc"

                    if [[ ! -f "$file" ]]; then
                        wget "$url" -P "${model}/${scenario}" || { echo "Failed to download $url"; }
                    else
                        echo "File $file already exists, skipping download."
                    fi

                    # Crop the file using cdo based on the provided xlim and ylim values
                    output_file="${model}/${scenario}/${lower_model}_${experiment}_w5e5_${scenario}_${variable}_global_daily_${year}_${end_year}_cropped.nc"
            
                    cdo_cmd="cdo sellonlatbox,${xmin},${xmax},${ymin},${ymax} $file $output_file"

                    echo "Executing cdo command: $cdo_cmd"
                  
                    eval "$cdo_cmd"
                    if [ $? -ne 0 ]; then
                        echo "Error executing cdo command: $cdo_cmd"
                    else
                        echo "Cropping successful: $output_file"
                        rm -f "$file"
                    fi
                done
            fi
        done
    done
}


# Export the function so that it can be accessed by parallel
export -f download_model_files

# Debug statements
echo "Model choices: ${model_choices[@]}"
echo "Variable: ${variable[@]}"
echo "Scenario: $scenario"
echo "longitude values used for cropping: ${xlim[@]}"
echo "latitude values used for cropping: ${ylim[@]}"

# Downloading files
if [[ "${model_choices[0]}" == "all" ]]; then
    echo "Downloading files for all models. This can take a while..."
    echo "model_choices: ${!model_map[@]}"
    parallel --jobs 5 --delay 1 "download_model_files {} '${variable}' '$scenario' '${xlim[0]}' '${xlim[1]}' '${ylim[0]}' '${ylim[1]}'" ::: "${!model_map[@]}"

else
    for model in "${model_choices[@]}"; do
        echo "Downloading files for model: $model. This can take a while ..."
        parallel --jobs 1 --delay 1 "download_model_files {} '${variable}' '$scenario' '${xlim[0]}' '${xlim[1]}' '${ylim[0]}' '${ylim[1]}'" ::: "$model"

    done
fi

create_ncml() {
    local models=()
    if [[ "$1" == "all" ]]; then
        models=("GFDL-ESM4" "MPI-ESM1-2-HR" "IPSL-CM6A-LR" "MRI-ESM2-0" "UKESM1-0-LL")
    else
        models=("$1")
    fi

    local scenarios=() 
    if [[ "$2" == "all" ]]; then
        scenarios=("historical" "ssp126" "ssp585")
    else
        scenarios=("$2")
    fi

    for model in "${models[@]}"; do
        for scenario in "${scenarios[@]}"; do
            if [[ -d "${model}/${scenario}" ]]; then
                mkdir -p "ncml/${scenario}"
                Rscript -e "library(loadeR); 
                makeAggregatedDataset(source.dir=paste0('./', '${model}', '/', '${scenario}'), ncml.file=paste0('./ncml/', '${scenario}', '/', '${model}', '_',  '${scenario}', '.ncml' ))"
            else
                echo "Directory ${model}/${scenario} does not exist."
            fi
        done
    done
}

export -f create_ncml

if [[ $conda_env == "no" ]]; then
    echo "Skipping ncml file creation."
else
    create_ncml $model_choices $scenario
fi
