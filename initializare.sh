#!/bin/bash

echo "=== CONFIGURARE INIȚIALĂ GIT ==="

# 1. Datele de identificare
echo "Introdu numele de utilizator GitHub:"
read username
echo "Introdu email-ul de GitHub:"
read email
echo "Introdu Personal Access Token (ghp_...):"
read token

git config --global user.name "$username"
git config --global user.email "$email"

# 2. Inițializare folder local
git init
git add .
git commit -m "Initial commit - configurare automata"

# 3. Legătura cu serverul (Include Token-ul pentru autentificare automată)
echo "Introdu numele repository-ului (ex: ballon-war):"
read repo_name

# Construim URL-ul cu token inclus: https://github.com
REMOTE_URL="https://$username:$token@://github.com"

# Ștergem 'origin' dacă există deja și îl adăugăm pe cel nou
git remote remove origin 2>/dev/null
git remote add origin "$REMOTE_URL"

# Setăm branch-ul principal pe 'main'
git branch -M main

# 4. Primul Push
echo "Se trimite codul pe GitHub..."
git push -u origin main

echo "=== GATA! Proiectul a fost legat și urcat pe GitHub ==="

