# Puertos

| Servicio | IPv4/UDP | Uso |
|---|---:|---|
| Lobby | 19132 | Gateway RakNet → BDS local 20132 |
| Survival | 19133 | Gateway RakNet → BDS local 20133 |
| PvP | 19134 | PvP y colas |
| BedWars | 19135 | BedWars |
| SkyWars | 19136 | SkyWars |

Los puertos públicos `19132-19136/UDP` deben ser accesibles por los clientes
porque `/transfer` conecta directamente al servidor destino. Los backends BDS
`20132/UDP` y `20133/UDP` son internos: no los abras en Oracle, UFW ni iptables.
El gateway publica un anuncio MCPE completo en 19132/19133 y reenvía la sesión
al BDS correspondiente.
