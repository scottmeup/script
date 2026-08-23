# Inputs: current Termux PATH and runtime mirror at /dev/user-script.
# Output: appends /dev/user-script to interactive Termux shells without duplicating it.
# Processing: checks colon-delimited PATH membership and exports the extended value only when absent.
case ":$PATH:" in
    *:/dev/user-script:*) ;;
    *) export PATH="$PATH:/dev/user-script" ;;
esac
