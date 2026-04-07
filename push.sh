#!/bin/bash

# 1. Află automat branch-ul curent (main sau master)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "--- Lucrăm pe branch-ul: $BRANCH ---"

# 2. Descarcă eventuale modificări de pe server
git pull origin $BRANCH

# 3. Adaugă tot
git add .

# 4. Mesaj de commit
echo "Ce modificări ai făcut?"
read message

# Dacă mesajul e gol, pune unul default
if [ -z "$message" ]; then
  message="Update automat $(date +'%Y-%m-%d %H:%M')"
fi

# 5. Salvează și trimite
git commit -m "$message"
git push origin $BRANCH

echo "--- Gata! Totul este pe GitHub ---"
