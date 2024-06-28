##################################################
#
# Utility functions for Backup and Restore script
#
##################################################

# List location function - list out all locations from location.cfg file with preceding line number
list_locations() {
     local line_number=1
     while IFS= read -r location; do
          echo "$line_number | $location"
          ((line_number++))
     done <$locations_file
}

# Function to sanitize directory names for filenames | how to use: santize "/your/home/directory/""
sanitize() {
     echo "$1" | sed 's|/|_|g' | sed 's|^_||' | sed 's|_$||'
}

# Function to create backup folder | how to use: create_backup_dir "$backup_dir/$hostname/$sanitized_folder"
create_dir_if_not_exists() {
     local dir="$1"
     if [[ ! -d "$dir" ]]; then
          echo "Creating $dir folder."
          mkdir -p "$dir"
     fi
}

#Function to generate checksum | how to use: generate_checksum "/path/to/your/file.txt"
generate_checksum() {
     local file="$1" md5_cmd

     if ssh -n ${user}@${hostname} "command -v md5sum" &>/dev/null; then
          md5_cmd="md5sum $file | cut -d'/' -f1 | xargs"
     else
          md5_cmd="md5 -q $file"
     fi

     ssh -n ${user}@${hostname} "$md5_cmd"
}

# Function to create or update the checksum file | how to use: create_or_update_checksum_file "/path/to/your/checksum.txt"
create_or_update_checksum_file() {
     local checksum_file="$1" remote_files

     if [[ ! -f $checksum_file ]]; then
          touch $checksum_file
          echo "Checksum file generated for $location"
     fi

     remote_files=$(ssh -n ${user}@${hostname} "find $path -type f -not -path '*/.*' -not -name '*.phantom'")
     
     echo "Updating checksum....."
     while IFS= read -r file; do
          local checksum
          checksum=$(generate_checksum "$file")

          # Check if the file is already in the checksum_file
          if grep -q "$file" "$checksum_file"; then
               # Update the existing line with the new checksum and zip
               sed -i "s|.*$file.*|$checksum $file $backup_filename|" "$checksum_file"
          else
               # Append new entry if the file is not found in the checksum_file
               echo "$checksum $file $backup_filename" >>"$checksum_file"
          fi
     done <<<"$remote_files"
     
     echo "Completed checksum update"
}

# Function to parse the location string | how to use: parse_location "user@hostname:/location/to/file"
parse_location() {
     local location="$1"
     user=$(echo $location | cut -d'@' -f1)
     hostname=$(echo $location | cut -d'@' -f2 | cut -d':' -f1)
     path=$(echo $location | cut -d':' -f2)
}
