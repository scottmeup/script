if [[ "$1" == "$2" || -e "$2" ]]; then
  exit 1
else
  sed ′s/\r's/\r//' "$1" > "$2"
fi
