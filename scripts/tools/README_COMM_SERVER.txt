Server de comunicare pentru colaborare agenti

Fișiere:
- tools\comm_server.py  - server TCP JSON minimal (newline-delimited JSON)

Cum se rulează:
1. Deschide un terminal în rădăcina proiectului (C:\Users\teodo\Documents\ballon-war)
2. Rulează: python tools\comm_server.py [host] [port]
   - Exemplu: python tools\comm_server.py 127.0.0.1 8765

Protocol:
- Mesajele sunt obiecte JSON terminate cu \n.
- Handshake recomandat: {"type": "hello", "agent": "numele_tau"}
- Server va retransmite mesajele primite către ceilalți clienți.
- Tratează serverul ca un canal intern — nu-l expune public fără autentificare.

Observație: scriptul e intenționat simplu, fără autentificare sau criptare. Adaugă TLS/auth când e necesar.
