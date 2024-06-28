####################################
#
# Backup and Restore script
#
# Backup function doesn't store hidden files with regex: */.*
# Assumption that the following are installed in the backup directory server:
#      coreutils (for checksum)
#      rsync
#
####################################

# Import configurations file
source "../configs/config"

# Import utility functions
source "./utils.sh"

# Help function
help() {
     echo "This backup and restore script is used for performing backup and restoration to all or specified location in locations.cfg file."
     echo "It has functionality to detect files modified by bad actors and restore it to original state"
     echo
     echo Syntax:
     echo
     echo "For Locations: script_name.sh"
     echo "For Backup: script_name.sh [-B|--backup] or [-B|--backup] [-L|--line] [location number]"
     echo "For Restore: script_name.sh [-R|--restore] [version] or [-R|--restore] [version] [-L|--line] [location number]"
     echo "For Restore with Integrity: script_name.sh [-R|--restore] [-I|--integrity] or [-R|--restore] [-I|--integrity] [-L|--line] [location number]"
     echo
     echo "Options:"
     echo
     echo "SWITCH                                                            FUNCTION"
     echo "[no command]                                                      List all locations and its line number"
     echo "[-B|--backup]                                                     Backup all location"
     echo "[-B|--backup] [-L|--line] [location number]                       Backup specific location"
     echo "[-R|--restore] [version]                                          Restore specific version for all location"
     echo "[-R|--restore] [version] [-L|--line] [location number]            Restore specific version for specific location"
     echo "[-R|--restore] [-I|--integrity]                                   Restore phantom file to original state for all location"
     echo "[-R|--restore] [-I|--integrity] [-L|--line] [location number]     Restore phantom file to original state for specific location"
     echo
}

# Perform Back Up
perform_backup() {
     local location="$1"
     parse_location "$location"

     local sanitized_folder=$(sanitize "$path")
     create_dir_if_not_exists "$backup_dir/$hostname/$sanitized_folder"

     local backup_filename="$(date +'%Y%m%d_%H%M%S').tar.gz" #define the backup filename
     local checksum_file="$backup_dir/$hostname/$sanitized_folder/checksums.txt"

     echo "Start backup process for $location"

     if [[ -f $checksum_file ]]; then
          local remote_files=$(ssh -n ${user}@${hostname} "find $path -type f -not -path '*/.*'")
          # Perform integrity check for each file in the location
          while IFS= read -r file; do
               local original_checksum=$(grep "$file" "$checksum_file" | awk '{ print $1 }')
               local new_checksum=$(generate_checksum "$file")
               # If the original checksum is not empty - meaning that the file is not new
               # and the original and new checksum are not equals
               if [[ -n "$original_checksum" && "$original_checksum" != "$new_checksum" ]]; then
                    ssh -n ${user}@${hostname} mv "$file" "${file}.phantom" #rename the impacted file to add .phantom
                    echo "Discrepancy detected in file: $file"
                    echo "Original checksum: $original_checksum"
                    echo "New checksum: $new_checksum"
               fi
          done <<<"$remote_files"
     fi

     create_or_update_checksum_file "$checksum_file"

echo "Executing backup..."
     # Compress the files in the folder into one zip file
     local compress="touch $path/$backup_filename && tar --exclude=$backup_filename --exclude='*.phantom' --exclude='*/.*' -zcf $path/$backup_filename -C $path ."
     ssh -n ${user}@${hostname} $compress

     # Move the zip file to the backup directory
     rsync -avz --progress --remove-source-files $location/$backup_filename $backup_dir/$hostname/$sanitized_folder

     echo "Completed backup for $location"
}

# Perform Restore
perform_restore() {
     local location="$1"
     local version="$2"
     parse_location "$location"
     local sanitized_folder=$(sanitize "$path")
     local restore_filename=$(ls -t $backup_dir/$hostname/$sanitized_folder | grep -v 'checksums.txt' | sed -n ${version}p)

     if [ -z "$restore_filename" ]; then
          echo "No version $version exists for $location"
     else
     echo "Start restore process for $location"
          echo "Restoring backup from $restore_filename"
          rsync -avz --progress $backup_dir/$hostname/$sanitized_folder/$restore_filename $location
          extract="tar -xzf $path/$restore_filename -C $path && rm $path/$restore_filename"
          ssh -n $user@$hostname $extract
          echo "Completed restore for $location"
     fi

}

# Perform Restore with Integrity
perform_restore_with_integrity() {
     local location="$1"
     parse_location "$location"
     local sanitized_folder=$(sanitize "$path")
     local checksum_file="$backup_dir/$hostname/$sanitized_folder/checksums.txt"

     local remote_phantom_files=$(ssh -n ${user}@${hostname} "find ${path} -type f -name '*.phantom'")

     if [ -z "${remote_phantom_files}" ]; then #check if no phantom file in the location
          echo "No phantom files found on remote server: $location"
     else
     echo "Start restore process for $location"
          while IFS= read -r file; do
               local base_filepath_name=$(echo "$file" | sed 's/\.phantom$//')
               local matching_lines=$(grep "$base_filepath_name" "$checksum_file" | grep -v '\.phantom')
               local restore_filename=$(echo "$matching_lines" | awk '{print $3}')
               echo "Restoring file: $base_filepath_name"
               echo "Source zip file: $restore_filename"
               local base_filename=$(basename "$file" .phantom)
               echo "Extracting $base_filepath_name to $location"
               rsync -avz --progress $backup_dir/$hostname/$sanitized_folder/$restore_filename $location
               local extract_gnu="tar -xzf $path/$restore_filename -C $path --wildcards './$base_filename' && rm $path/$restore_filename"
               local extract_bsd="tar -xzf $path/$restore_filename -C $path './$base_filename' && rm $path/$restore_filename"
               ssh -n $user@$hostname "
                   if tar --version 2>&1 | grep -q GNU; then
                       $extract_gnu
                   else
                       $extract_bsd
                   fi
               "
               echo "Deleting $file from $location"
               ssh -n $user@$hostname rm -rf $file
               echo "Completed restoring $base_filename to its original state for $location"
          done <<<"$remote_phantom_files"
     fi
}

# Main Code Logic
main() {
     # Validate and ensure that the configuration file exists
     if [[ ! -f $locations_file ]]; then
          echo "Error: Locations file ./configs/$locations_file not found."
          exit 1
     fi

     create_dir_if_not_exists "$logs_dir"

     if [[ $# -eq 0 ]]; then
          list_locations
          exit 0
     fi

     if [[ $1 =~ ^(-B|--backup) ]]; then
          if [[ $# -eq 3 && $2 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $3p $locations_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number. To find valid line number, run the command: ./bkmedia.sh OR ./bkmedia.sh [-H|--help]"
                    exit 1
               fi
               perform_backup "$location"
          elif [[ $# -eq 1 ]]; then
               while IFS= read -r location; do
                    perform_backup "$location"
               done <"$locations_file"
          else
               echo "Invalid arguments."
               echo "For Usage, Run command: script_name.sh [-H|--help]"
               exit 1
          fi
     elif [[ $1 =~ ^(-R|--restore) ]]; then
          if [[ $# -eq 4 && $2 =~ ^(-I|--integrity) && $3 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $4p $locations_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number."
                    exit 1
               fi
               perform_restore_with_integrity "$location"
          elif [[ $# -eq 4 && $3 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $4p $locations_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number."
                    exit 1
               fi
               perform_restore "$location" "$2"
          elif [[ $# -eq 2 && $2 =~ ^(-I|--integrity) ]]; then
               while IFS= read -r location; do
                    perform_restore_with_integrity "$location"
               done <"$locations_file"
          elif [[ $# -eq 2 ]]; then
               while IFS= read -r location; do
                    perform_restore "$location" "$2"
               done <"$locations_file"
          else
               echo "Invalid arguments."
               echo "For Usage, Run command: script_name.sh [-H|--help]"
               exit 1
          fi
     elif [[ $1 =~ ^(-H|--help) ]]; then
          help
     else
          echo "Invalid arguments."
          echo "For Usage, Run command: script_name.sh [-H|--help]"
          exit 1
     fi
}

main "$@" 2>&1 | tee -a $logs_dir/$(date +'%Y%m%d_%H%M%S').log
