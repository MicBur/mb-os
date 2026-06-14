#!/bin/bash
# MB-OS Right-Click Context Menu
export DISPLAY=:0

ACTION=$(NEWT_COLORS='root=,black window=cyan,black border=cyan,black title=white,black button=black,cyan actbutton=black,white listbox=white,black actlistbox=black,cyan' \
whiptail --title "MB-OS" --menu "" 12 30 5 \
  "copy"   "  Kopieren       Ctrl+C" \
  "paste"  "  Einfuegen      Ctrl+V" \
  "cut"    "  Ausschneiden   Ctrl+X" \
  "selall" "  Alles markieren" \
  "---"    "  Abbrechen" \
  3>&1 1>&2 2>&3)

case "$ACTION" in
    copy)   xdotool key ctrl+c ;;
    paste)  xdotool key ctrl+v ;;
    cut)    xdotool key ctrl+x ;;
    selall) xdotool key ctrl+a ;;
esac
