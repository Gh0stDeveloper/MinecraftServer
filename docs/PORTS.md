# Puertos

| Servicio | IPv4/UDP | Uso |
|---|---:|---|
| Lobby | 19132 | Entrada principal |
| Survival | 19133 | Mundo avanzado |
| PvP | 19134 | PvP y colas |
| BedWars | 19135 | BedWars |
| SkyWars | 19136 | SkyWars |

Los puertos backend deben ser accesibles por los clientes porque `/transfer` conecta al cliente directamente al servidor destino. Si más adelante incorporamos un proxy compatible que mantenga una única conexión, podremos ocultarlos y usar una sola entrada pública.
