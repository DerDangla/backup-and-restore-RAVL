source "./utils.sh"
source "../configs/config"

while IFS= read -r location; do
    parse_location "$location"
    remote_files=$(ssh -n ${user}@${hostname} "find $path -type f -not -path '*/.*'")
    # Convert remote_files to an array
    mapfile -t files_array <<<"$remote_files"

    # Check if there are at least two files
    if [ ${#files_array[@]} -ge 2 ]; then
        # Select two random files
        random_files=($(shuf -e "${files_array[@]}" -n 2))

        # Modify the contents of the selected files
        for file in "${random_files[@]}"; do
            ssh -n ${user}@${hostname} "echo 'PHANTOM ATTACK!! RAWR!' >> $file"
            echo "$file FILE WAS ATTACKED BY PHANTOM!!!"
        done
    else
        echo "Not enough files to modify."
    fi

done <"$config_file"
