#!/bin/bash

# 1. Detectează automat branch-ul pe care ești (main/master/etc.)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "--- Se descarcă noutățile de pe server ($BRANCH) ---"

# 2. Execută comanda de pull
# Folosim --rebase pentru a păstra un istoric curat în cazul în care ai lucrat și tu local
git pull origin $BRANCH --rebase

# 3. Verificăm dacă a reușit
if [ $? -eq 0 ]; then
    echo "--- Succes! Proiectul tău este acum actualizat. ---"
else
    echo "--- A apărut o problemă (posibil conflicte). Verifică terminalul! ---"
fi
