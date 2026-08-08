import { system, world } from "@minecraft/server";
import { ActionFormData } from "@minecraft/server-ui";

const GAME = "BEDWARS";
const QUEUES = { solo: [], duo: [], squad: [] };
const REQUIRED = { solo: 2, duo: 4, squad: 8 };
const LABEL = { solo: "Solo", duo: "Duo", squad: "Escuadra" };

function livePlayer(id) { return world.getPlayers().find((p) => p.id === id); }
function purgeQueue(mode) { QUEUES[mode] = QUEUES[mode].filter((id) => !!livePlayer(id)); }
function removeFromAll(player) { for (const mode of Object.keys(QUEUES)) QUEUES[mode] = QUEUES[mode].filter((id) => id !== player.id); }
function joinQueue(player, mode) { removeFromAll(player); purgeQueue(mode); QUEUES[mode].push(player.id); player.sendMessage(`§aEntraste a la cola de ${GAME} ${LABEL[mode]}. §f${QUEUES[mode].length}/${REQUIRED[mode]}`); tryStart(mode); }
function tryStart(mode) {
  purgeQueue(mode);
  if (QUEUES[mode].length < REQUIRED[mode]) return;
  const ids = QUEUES[mode].splice(0, REQUIRED[mode]);
  const players = ids.map(livePlayer).filter(Boolean);
  for (const player of players) { player.sendMessage(`§6Partida encontrada: §f${GAME} ${LABEL[mode]}`); player.sendMessage("§7ArenaManager pendiente de configurar con el mapa físico."); }
}
async function menu(player) {
  const response = await new ActionFormData().title(`§l${GAME}`).body("Selecciona modalidad").button(`§aSolo\n§7${REQUIRED.solo} jugadores`).button(`§eDuo\n§7${REQUIRED.duo} jugadores`).button(`§cEscuadra\n§7${REQUIRED.squad} jugadores`).button("§7Salir de la cola").show(player);
  if (response.canceled) return;
  if (response.selection === 0) joinQueue(player, "solo");
  if (response.selection === 1) joinQueue(player, "duo");
  if (response.selection === 2) joinQueue(player, "squad");
  if (response.selection === 3) { removeFromAll(player); player.sendMessage("§7Saliste de todas las colas."); }
}
world.afterEvents.playerSpawn.subscribe(({ player, initialSpawn }) => { if (initialSpawn) system.run(() => menu(player).catch(() => {})); });
world.afterEvents.itemUse.subscribe((event) => { if (event.itemStack?.typeId === "minecraft:compass") system.run(() => menu(event.source).catch(() => {})); });
world.beforeEvents.chatSend.subscribe((event) => { const msg = event.message.trim().toLowerCase(); if (msg === "!play" || msg === "!menu") { event.cancel = true; const player = event.sender; system.run(() => menu(player).catch(() => {})); } });
world.afterEvents.playerLeave.subscribe(({ playerId }) => { for (const mode of Object.keys(QUEUES)) QUEUES[mode] = QUEUES[mode].filter((id) => id !== playerId); });
