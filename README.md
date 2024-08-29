<p align="center">
  <img src="ravl-logo.webp" />
</p>

-----------

This is a simple backup and restore script that detects ghost files and restore it to original state. Update read me

# Pre-requisites

1. Ensure that coreutils (for checksum) and rsync are installed in your configured location
2. ssh keys are setup between servers

# How to use

1. Download the folders and contents of /config and /scripts
2. Configure your locations.cfg file with your respective [user]@[hostname]:/path/to/folder/
3. Configure your config file with your desired logs and backup folders
4. run ./scripts/bkmedia.sh

<b>Note: Backup function doesn't store hidden files with regex: \*/.\* </b>

<details>
	<summary>Built-in help message</summary>

```
This backup and restore script is used for performing backup and restoration to all or specified location in locations.cfg file.
It has functionality to detect files modified by bad actors and restore it to original state

Syntax:

 For Locations: script_name.sh
 For Backup: script_name.sh [-B|--backup] or [-B|--backup] [-L|--line] [location number]
 For Restore: script_name.sh [-R|--restore] [version] or [-R|--restore] [version] [-L|--line] [location number]
 For Restore with Integrity: script_name.sh [-R|--restore] [-I|--integrity] or [-R|--restore] [-I|--integrity] [-L|--line] [location number]

Options:

 SWITCH                                                            FUNCTION
 [no command]                                                      List all locations and its line number
 [-B|--backup]                                                     Backup all location
 [-B|--backup] [-L] [location number]                              Backup specific location
 [-R|--restore] [version]                                          Restore specific version for all location
 [-R|--restore] [version] [-L|--line] [location number]            Restore specific version for specific location
 [-R|--restore] [-I|--integrity]                                   Restore phantom file to original state for all location
 [-R|--restore] [-I|--integrity] [-L|--line] [location number]     Restore phantom file to original state for specific location

```

</details>

# Future improvements

1. Modify backup script to add retention period for backed up files. (retention period to be configured in config file)
2. Add logic and configuration for max size of all files in the folder and split the zip file
3. Use any cloud (such as s3) to store your backup files.
4. Parallel processing to handle multiple files at the same time to reduce overall runtime.




