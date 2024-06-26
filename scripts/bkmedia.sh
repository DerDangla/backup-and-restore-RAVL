#!/bin/bash
####################################
#
# Backup and Restore script.
# Backup doesn't store hidden files with regex: */.*
# Assumption that the following are installed in the backup directory server: md5 rsync
#
####################################

# Configuration file containing server and directory information
config_file="../config/locations.cfg"
logs_dir="../logs"
backup_dir="../backup"

source "./utils.sh"

# List location function - list out all locations from location.cfg file with preceding line number


# Function to sanitize directory names for filenames
#sanitize() {
#     echo "$1" | sed 's|/|_|g' | sed 's|^_||' | sed 's|_$||'
#}

# Function to create backup folder
#create_backup_dir() {
#     if [[ ! -d "./backup/$hostname/$sanitized_folder" ]]; then
#          echo "Creating ./backup/$hostname/$sanitized_folder folder."
#          mkdir -p ./backup/$hostname/$sanitized_folder
#     fi
#}

# Function to generate checksum
#generate_checksum() {
#     local file="$1"
#     if [[ ${hostname} == "localhost" ]]; then
#          md5sum "$file" | cut -d'/' -f1 | xargs
#     else
#          ssh -n ${user}@${hostname} "md5 -q '$file'"
#     fi
#}

# Function to create or update the checksum file
#create_or_update_checksum_file() {
#     local checksum_file="$1" remote_files

#     if [[ ! -f $checksum_file ]]; then
#          touch $checksum_file
#     fi

#     remote_files=$(ssh -n ${user}@${hostname} "find $path -type f -not -path '*/.*'")

#     while IFS= read -r file; do
#          local checksum
#          checksum=$(generate_checksum "$file")

          # Check if the file is already in the checksum_file
#          if grep -q "$file" "$checksum_file"; then
               # Update the existing line with the new checksum and timestamp
#               sed -i "s|.*$file.*|$checksum $file $backup_filename|" "$checksum_file"
#          else
               # Append new entry if the file is not found in the checksum_file
#               echo "$checksum $file $backup_filename" >>"$checksum_file"
#          fi
#     done <<< "$remote_files"
#}

# Utility function to parse the location string
#parse_location() {
#     local location="$1"
#     user=$(echo $location | cut -d'@' -f1)
#     hostname=$(echo $location | cut -d'@' -f2 | cut -d':' -f1)
#     path=$(echo $location | cut -d':' -f2)
#}

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
                    mv "$file" "${file}.phantom"
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

     # Find all filenames that contain .phantom
     local phantom_files=$(grep '\.phantom' "$checksum_file" | awk '{print $2}')

     echo "Performing Restore with Integrity for location: $location"

     if [[ -f $phantom_files ]]; then
          echo "Integrity issue detected"
          while IFS= read -r file; do
               local base_filepath_name=$(echo "$file" | sed 's/\.phantom$//')
               local matching_lines=$(grep "$base_filepath_name" "$checksum_file" | grep -v '\.phantom')
               local restore_filename=$(echo "$matching_lines" | awk '{print $3}')
               echo "Tar.gz files for $base_filepath_name:"
               echo "$restore_filename"
               local base_filename=$(basename "$phantom_files" .phantom)
               rsync -avz --progress $backup_dir/$hostname/$sanitized_folder/$restore_filename $location
               local extract="tar -xzf $path/$restore_filename -C $path --wildcards './$base_filename' && rm $path/$restore_filename"
               ssh -n $user@$hostname "$extract"
               ssh -n $user@$hostname rm -rf $file
               grep -v "$file" "$checksum_file" >"$checksum_file.tmp" && mv "$checksum_file.tmp" "$checksum_file"
               echo "Restored specific file $base_filename for $location"
          done <<< "$phantom_files"

     else
          echo "No Integrity issue found."
     fi

     echo "Restore with Integrity completed for location: $location"
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
               done < "$config_file"
          else
               echo "Invalid arguments. Usage: script_name [-B|--backup] [-L|--line] [line_number] or script_name [-B|--backup] or script_name [-R|--restore] [backup_version] [-L|--line] [line_number] or script_name [-R|--restore] [backup_version]"
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
               done < "$config_file"
          elif [[ $# -eq 2 ]]; then
               while IFS= read -r location; do
                    perform_restore "$location" "$2"
               done < "$config_file"
          else
               echo "Invalid arguments. Usage: script_name [-B|--backup] [-L|--line] [line_number] or script_name [-B|--backup] or script_name [-R|--restore] [backup_version] [-L|--line] [line_number] or script_name [-R|--restore] [backup_version]"
               exit 1
          fi
     else
          echo "Invalid arguments. Usage: script_name [-B|--backup] [-L|--line] [line_number] or script_name [-B|--backup]"
          exit 1
     fi
 }
 
 main "$@" 2>&1 | tee -a $logs_dir/$(date +'%Y%m%d_%H%M%S').log