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
source "../config/scripts.cfg"

# Import utility functions
source "./utils.sh"

# Help function
help() {
     echo "The script aims to perform backup and restore to any or specified location in locations.cfg file."
     echo
     echo "Syntax for Backup: script_name.sh [-B|--backup] or [-B|--backup] [-L|--line] [location number]"
     echo "Syntax for Restore: script_name.sh [-R|--restore] [version] or [-R|--restore] [version] [-L|--line] [location number]"
     echo "Syntax for Restore with Integrity: script_name.sh [-R|--restore] [-I|--integrity] or [-R|--restore] [-I|--integrity] [-L|--line] [location number]"
     echo
     echo "Options:"
     echo "[-B|--backup]                                                     Backup all location"
     echo "[-B|--backup] [-L] [location number]                              Backup specific location"
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

     local backup_filename="$(date +'%Y%m%d_%H%M%S').tar.gz"
     local checksum_file="$backup_dir/$hostname/$sanitized_folder/checksums.txt"

     if [[ -f $checksum_file ]]; then
          local remote_files=$(ssh -n ${user}@${hostname} "find $path -type f -not -path '*/.*'")
          # Integrity check
          while IFS= read -r file; do
               local original_checksum=$(grep "$file" "$checksum_file" | awk '{ print $1 }')
               local new_checksum=$(generate_checksum "$file")
               if [[ -n "$original_checksum" && "$original_checksum" != "$new_checksum" ]]; then
                    ssh -n ${user}@${hostname} mv "$file" "${file}.phantom"
                    echo "Original checksum: $original_checksum"
                    echo "New checksum: $new_checksum"
                    echo "Discrepancy detected in file: $file"
               fi
          done <<<"$remote_files"
     fi

     create_or_update_checksum_file "$checksum_file"

     local compress="touch $path/$backup_filename && tar --exclude=$backup_filename --exclude='*/.*' -zcf $path/$backup_filename -C $path ."
     ssh -n ${user}@${hostname} $compress
     rsync -avz --progress --remove-source-files $location/$backup_filename $backup_dir/$hostname/$sanitized_folder

     echo "Backup completed for $location"
}

# Perform Restore
perform_restore() {
     local location="$1"
     local version="$2"
     parse_location "$location"
     local sanitized_folder=$(sanitize "$path")
     local restore_filename=$(ls -t $backup_dir/$hostname/$sanitized_folder | grep -v 'checksums.txt' | sed -n ${version}p)

     echo "Restoring backup from $restore_filename to $location"
     rsync -avz --progress $backup_dir/$hostname/$sanitized_folder/$restore_filename $location
     extract="tar -xzf $path/$restore_filename -C $path && rm $path/$restore_filename"
     ssh -n $user@$hostname $extract

     echo "Restore completed for $location"
}

# Perform Restore with Integrity
perform_restore_with_integrity() {
     local location="$1"
     parse_location "$location"
     local sanitized_folder=$(sanitize "$path")
     local checksum_file="$backup_dir/$hostname/$sanitized_folder/checksums.txt"

     local remote_files=$(ssh -n ${user}@${hostname} "find ${path} -type f -name '*.phantom'")

     # Find all filenames that contain .phantom
     local phantom_files=$(grep '\.phantom' "$checksum_file" | awk '{print $2}')

     if [ -z "${remote_files}" ]; then
          echo "No phantom files found on remote server: $location"
     else
          while IFS= read -r file; do
               local base_filepath_name=$(echo "$file" | sed 's/\.phantom$//')
               local matching_lines=$(grep "$base_filepath_name" "$checksum_file" | grep -v '\.phantom')
               local restore_filename=$(echo "$matching_lines" | awk '{print $3}')
               echo "Tar.gz files for $base_filepath_name:"
               echo "$restore_filename"
               local base_filename=$(basename "$file" .phantom)
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
               echo "Deleteing $file from $location"
               ssh -n $user@$hostname rm -rf $file
               local phantom_files=$(grep '\.phantom' "$checksum_file" | awk '{print $2}')
               for file in $phantom_files; do
                    grep -v "$file" "$checksum_file" >"$checksum_file.tmp" && mv "$checksum_file.tmp" "$checksum_file"
               done
               echo "Restored specific file $base_filename for $location"
          done <<<"$remote_files"
     fi
}

# Main Code Logic
main() {
     # Validate and ensure that the configuration file exists
     if [[ ! -f $config_file ]]; then
          echo "Error: Configuration file $config_file not found."
          exit 1
     fi

     create_dir_if_not_exists "$logs_dir"

     if [[ $# -eq 0 ]]; then
          list_locations
          exit 0
     fi

     if [[ $1 =~ ^(-B|--backup) ]]; then
          if [[ $# -eq 3 && $2 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $3p $config_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number."
                    exit 1
               fi
               perform_backup "$location"
          elif [[ $# -eq 1 ]]; then
               while IFS= read -r location; do
                    perform_backup "$location"
               done <"$config_file"
          else
               echo "Invalid arguments."
               echo "For Usage, Run command: script_name.sh [-H|--help]"
               exit 1
          fi
     elif [[ $1 =~ ^(-R|--restore) ]]; then
          if [[ $# -eq 4 && $2 =~ ^(-I|--integrity) && $3 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $4p $config_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number."
                    exit 1
               fi
               perform_restore_with_integrity "$location"
          elif [[ $# -eq 4 && $3 =~ ^(-L|--line) ]]; then
               local location=$(sed -n $4p $config_file)
               if [[ -z $location ]]; then
                    echo "Error: Invalid line number."
                    exit 1
               fi
               perform_restore "$location" "$2"
          elif [[ $# -eq 2 && $2 =~ ^(-I|--integrity) ]]; then
               while IFS= read -r location; do
                    perform_restore_with_integrity "$location"
               done <"$config_file"
          elif [[ $# -eq 2 ]]; then
               while IFS= read -r location; do
                    perform_restore "$location" "$2"
               done <"$config_file"
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
