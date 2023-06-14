#!bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display the script's usage
show_help() {
  echo -e "${YELLOW}Usage: bash organizer.sh [srcdir] [destdir] [options]"
  echo "Options:"
  echo "  --help              Display this help message"
  echo "  -s [type]           Sort files based on 'ext' for extension or 'date' for creation date${NC},"
  echo "  -d                  Delete the files from the destination"
  echo "  -l [log_file]       The name of the lof file is required"
  echo "  -p                  Disable the progress bar"
  echo "  -e [ext1,ext2,...]  Exclude file types or directories from being organized.Arguments should be comma separated."
  echo "  -i [ext1,ext2,...]  Include file types or directories from being organized.Arguments should be comma separated."
  echo "                      Both include and exclude cannot be used together. Use the no_extension tag for handling files without extension"
  echo "  -f [max_size]       Sets the upperlimit for the size if the files to copy, the max size should be given in this format: <integer>[B|KB|MB|GB]"
  echo -e "$NC"
  exit 1
}

handle_error(){
  echo -e "${RED} Some kind of error was incurred, please ensure you have the correct usage${NC}"
  show_help

}

get_ext(){
  local file=$1
  local name=`basename $file`
  if [ $2 = "date" ]; then
    echo $(get_date $1)

  elif [[ ! "$name" == *.* ]]; then
    echo "no_extension"
  else 
    echo ${name##*.}
  fi
}

#gets the date in the required format
get_date(){
  creation_time=$(stat -c %x "$1")

  # Extract day, month, and year from the creation time
  IFS=' ' read -ra date_parts <<< "$creation_time"
  IFS='-' read -ra date <<< "${date_parts[0]}"
  day=${date[0]}
  month=${date[1]}
  year=${date[2]}

  # Rearrange the date parts to ddmmyyyy format
  formatted_date="${year}${month}${day}"
  echo $formatted_date
}

#This function is used to get the available filename on the basis of the files present in the 
#destination folder
get_available_filename(){
  local file=$1
  local dest=$2
  local ext=$3
  let num=1
  local name=`basename $file`

  if [[ ! "$name" == *.* ]]; then
    name_check=$name
    while [ -f $dest"/"$ext"/"$name_check ]; do
      name_check="${name}_$num" # Append increment number
      let num=$num+1
    done
    echo $name_check   
  else
    extension=${name##*.}
    name="${name%.*}" # Remove extension
    name_check=$name

    # Loop until a unique file name is found
    while [ -f $dest"/"$ext"/"$name_check"."$extension ]; do
      name_check="${name}_$num" # Append increment number
      let num=$num+1
    done
    
    echo $name_check"."$extension
  fi
  
}
let check_time=$((2**63 - 1))
# Function to print progress bar
print_progress() {
  local width=50  # Width of the progress bar
  local progress=$1
  local completed=$((progress * width / 100))
  local remaining=$((width - completed))  
  local bar=$(printf '%*s' "$completed" | tr ' ' '#') #creates a string of specified length and then replaces it with #
  local space=$(printf '%*s' "$remaining" )

  # Calculate elapsed time
  local elapsed_time=$(($(date +%s) - start_time))
  # Calculate estimated time of completion
  if [ $progress -ne 0 ]; then
    local total_time=$((elapsed_time * 100 / progress))
    local remaining_time=$((total_time - elapsed_time))
    #echo "$remaining_time $check_time"
    echo -n
    if [ $remaining_time -le $check_time ]; then 
    	echo -ne "${RED}Progress: [$bar$space] $progress% |${CYAN} Estimated Time: $remaining_time seconds remaining\r${NC}"
   		check_time=$remaining_time 
    fi
  fi
}

convert_to_bytes() {
  local input=$1
  local size=$(echo "$input" | grep -oE '[0-9]+')
  local unit=$(echo "$input" | grep -oE '[A-Za-z]+')

  case $unit in
    B) size=$((size * 1));;
    KB) size=$((size * 1024));;
    MB) size=$((size * 1024 * 1024));;
    GB) size=$((size * 1024 * 1024 * 1024));;
    TB) size=$((size * 1024 * 1024 * 1024 * 1024));;
    *) echo "Invalid unit: $unit"; exit 1;;
  esac

  echo "$size"
}

#creating empty temporary files needed for function
#There was some issue with touch so I didn't use it
echo > test | grep '[^ ]' > output
cat output > extensions.txt
cat output > moved_files.txt
cat output > added_folders.txt
cat output > all_files.txt
rm test output
#trap handle_error ERR
#help function

if [ "$#" -lt 2 ]; then
  if [[ $1 == "--help" ]]; then
    show_help
    exit 1
  else 
    echo -e "${RED}Invalid Options"
    show_help
    exit 1
  fi
fi

#We will first extract the src and dest directories from the command line
src=$1
dest=$2


#check if dest exists
if [ ! -d $dest ]; then
  echo -e "${RED}Destination folder doesn't exist${NC}"
  sleep 0.5
  echo -en "${YELLOW}Creating destination folder${NC}\r"
  sleep 0.75
  echo -en "${YELLOW}Creating destination folder.${NC}\r"
  sleep 0.75
  echo -en "${YELLOW}Creating destination folder..${NC}\r"
  sleep 0.75
  echo -e "${YELLOW}Creating destination folder...${NC}\r"
  sleep 0.75
  mkdir -p $dest
  echo -e "${GREEN}$dest created${NC}"
  sleep 0.5
fi

#check if src exists
if [ ! -d $src ]; then
  echo -e "${RED}Source doesn't exist, please enter valid source${NC}"
  exit 1
fi
shift 2

sort_type="ext"
delete="false"
create_logfile="false"
exclude_list=()
enable_exclude="false"
include_list=()
enable_include="fasle"
disable_progress="false"
enable_max_size="false"

while getopts ":s:l:e:i:f:dp" opt; do
  case $opt in 
    d)
      echo -e -n "${RED}"
      read -p "Are you sure you want to delete orignal files [Y]es or [N]o: " choice
      if [ $choice = "Y" ]; then  
        delete="true"
      elif [ $choice = "y" ]; then  
        delete="true"
      fi
      echo -e -n "${NC}"
      ;;
    p)
      disable_progress="true"
      ;;
    f)
      size_arg=$OPTARG
      # Validate file size format using regex
      if ! [[ $size_arg =~ ^[0-9]+(B|KB|MB|GB)$ ]]; then
        echo -e "${RED}Invalid file size format. Please use the format <number>[B|KB|MB|GB].${NC}"
        exit 1
      fi
      enable_max_size="true"
      size_arg=$(convert_to_bytes $size_arg)
      ;;

    s)
      if [[ -z "$OPTARG" || "$OPTARG" == -* ]]; then
        echo -e "${RED}-$opt requires an argument.${NC}"
        show_help
        exit 1
      fi
      sort_type=$OPTARG
      ;;
    l)
      if [[ -z "$OPTARG" || "$OPTARG" == -* ]]; then
        echo -e "${RED}-$opt requires an argument.${NC}"
        show_help
        exit 1
      fi
      create_logfile="true"
      log_file=$OPTARG
      if [ -f $log_file  ]; then
        rm $log_file
      fi
      ;;
    e)
      if [[ "$enable_include" = "true" ]]; then
        echo -e "${RED}Both include and exclude option can't be used together${NC}"
        show_help
        exit 1
      fi
      if [[ -z "$OPTARG" || "$OPTARG" == -* ]]; then
        echo -e "${RED}-$opt requires arguments separated by commas.${NC}"
        show_help
        exit 1
      fi
      IFS=',' read -ra args <<< "$OPTARG"  # Split the comma-separated values into an array
      exclude_list+=("${args[@]}")  # Append the array elements to the main array
      enable_exclude="true"
      ;;
    i)
      if [[ "$enable_exclude" = "true" ]]; then
        echo -e "${RED}Both include and exclude option can't be used together${NC}"
        show_help
        exit 1
      fi
      if [[ -z "$OPTARG" || "$OPTARG" == -* ]]; then
        echo -e "${RED}-$opt requires arguments separated by commas.${NC}"
        show_help
        exit 1
      fi
      IFS=',' read -ra args <<< "$OPTARG"  # Split the comma-separated values into an array
      include_list+=("${args[@]}")  # Append the array elements to the main array
      enable_include="true"
      ;;

    :)
      echo -e "${RED} -$OPTARG requires an argument:"
      show_help
      exit 1
      ;;  
    \?)
      echo -e "${RED}Invalid option: -$OPTARG" 
      show_help
      exit 1
      ;;
  esac
done

if [ ! -d "$src/unzipped_files" ]; then
  echo -ne "${YELLOW}Creating temporary folder for unzipping Zipped files\r"
  sleep 0.75
  echo -ne "${YELLOW}Creating temporary folder for unzipping Zipped files.\r"
  sleep 0.75
  echo -ne "${YELLOW}Creating temporary folder for unzipping Zipped files..\r"
  sleep 0.75
  echo -e "${YELLOW}Creating temporary folder for unzipping Zipped files...\r"
  sleep 0.5
  mkdir -p "$src/unzipped_files"
fi

#unzipping the zipped folders
for file in $(find "$src" -type f -name "*.zip"); do
  # Unzip the files
  echo -e "${GREEN}Unzipping `basename $file` ${CYAN}"
  unzip -q -o "$file" -d "$src/unzipped_files"
done

find $src -type f | sed -n '/\/[^./]\+\.[^./]\+$/p' >> all_files.txt
find $src -type f | sed -n '/\/[^./]\+$/p' >> all_files.txt

total_files=$(wc -l < "all_files.txt")
start_time=$(date +%s)
current_file=0
echo
echo -e "${YELLOW}Copying the files now..."
echo -e "${RED}"
sleep 0.5

#first I took file from the source then piped it to the sed command 
#to get the files which have an extension                                  
for file in `cat "all_files.txt"`

do
  #check whether the user wants a progress bar or not
  if [ $disable_progress = "false" ]; then
    # Update progress
    ((current_file++))
    progress=$((current_file * 100 / total_files))

    # Display progress bar
    print_progress "$progress"
  fi

  #exctracted basename from file
  name=`basename $file`

  #get whether to sort about date or extension
  ext=`get_ext $file $sort_type`  
  #now we check whether we need to copy the file or not
  copy_files="true"
  if [ $enable_exclude = "true" ]; then
    for f in "${exclude_list[@]}"
    do
      if [ $f = "no_extension" ]; then
        if [[ ! "$name" == *.* ]]; then
          copy_files="false"
        fi
      elif [ $f = ${name##*.} ]; then
        copy_files="false"
      fi
    done
  fi

  if [ $enable_include = "true" ]; then
    copy_files="false"
    for f in "${include_list[@]}"
    do
      if [ $f = "no_extension" ]; then
        if [[ ! "$name" == *.* ]]; then
          copy_files="true"
        fi
      elif [ $f = ${name##*.} ]; then
        copy_files="true"
      fi
    done
  fi

  if [ $enable_max_size = "true" ];then
    file_size=$(stat -c %s "$file")
    if [ $file_size -gt $size_arg ]; then
      copy_files="false"
    fi
  fi


  if [ $copy_files = "true" ]; then

    #make extension folders to copy files
    echo $ext >> extensions.txt                        
    if [ ! -d "$dest/$ext" ]; then
      echo $ext>>added_folders.txt
    fi
    mkdir -p "$dest/$ext"

    #creating the logfile
    if [ $create_logfile = "true" ]; then
      echo "`get_available_filename $file $dest $ext` moved from $src to $dest/$ext" >> $log_file
    fi

    #copying the file
    echo `get_available_filename $file $dest $ext` >> moved_files.txt
    cp $file $dest"/"$ext"/"`get_available_filename $file $dest $ext`
    
    #delete the moved files if option was given
    if [ $delete = "true" ]; then
      rm $file 
    fi

  fi
done
echo -e "${NC}"
echo 

cat extensions.txt|sort|uniq > extensions1.txt   #created a file containing all the extensions
cat added_folders.txt|sort|uniq > added_folders1.txt
#time to print the Summary and other user friendly messages
sleep 0.5
echo -e "${RED}--------------------------SUMMARY------------------------------${NC}"
sleep 0.5
echo -e "${CYAN}Folders Created${NC}: ${YELLOW}"`wc -l added_folders1.txt|awk '{print $1}'`"${NC}"
sleep 0.5
echo -e "${CYAN}Files Transferred${NC}: ${YELLOW}"`wc -l moved_files.txt|awk '{print $1}'`"${NC}"
sleep 0.5
echo -e "${CYAN}File Count in the Created Folders:${NC}"
for folder in $(cat extensions1.txt)
do
  count=$(ls "$dest/$folder" | wc -l)
  echo -e -n "${YELLOW}"
  printf "%-15s:" "$folder"
  echo -e -n "${RED}"
  printf "%-5d\n" "$count"
  sleep 0.2
done
sleep 0.5
echo -e "${RED}---------------------------------------------------------------${NC}"
sleep 0.5

if [ $create_logfile = "true" ]; then
  echo -ne "${YELLOW}Creating logfile\r"
  sleep 0.75
  echo -ne "${YELLOW}Creating logfile.\r"
  sleep 0.75
  echo -ne "${YELLOW}Creating logfile..\r"
  sleep 0.75
  echo -ne "${YELLOW}Creating logfile..."
  sleep 0.5
fi
echo 
if [ $delete = "true" ]; then
  echo -ne "${RED}Deleting Orignal Files\r"
  sleep 0.75
  echo -ne "Deleting Orignal Files.\r"
  sleep 0.75
  echo -ne "Deleting Orignal Files..\r"
  sleep 0.75
  echo -ne "Deleting Orignal Files...${NC}"
  sleep 0.5
fi
echo
rm moved_files.txt added_folders.txt extensions.txt all_files.txt extensions1.txt added_folders1.txt
echo -e "${RED}Removing temporary folder for unzipping Zipped files${NC}"
sleep 0.5
rm -r "$src/unzipped_files"

#trap - ERR