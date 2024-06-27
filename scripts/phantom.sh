source "./utils.sh"
source "../configs/config"

while IFS= read -r location; do
                    perform_backup "$location"
               done <"$config_file"

sed -i "$(shuf -i 1-$(wc -l < /home/vagrant/dummy5.txt) -n 1)s/.*/New Content/" /home/vagrant/dummy5.txt