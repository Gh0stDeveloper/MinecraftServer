import { system, world } from "@minecraft/server";
import { ActionFormData } from "@minecraft/server-ui";
import { NETWORK } from "./config.js";
import { buildHub } from "./hub_builder.js";

const NPC = Object.freeze({
  survival: "Survival",
  pvp: "PvP",
  bedwars: "BedWars",
  skywars: "SkyWars"
});

function safeName(name) {
  return `"${String(name).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

function transfer(player, port) {
  try {
    player.dimension.runCommand(`transfer ${safeName(player.name)} ${NETWORK.host} ${port}`);
  } catch (error) {
    player.sendMessage(`§cNo se pudo transferir: ${error}`);
  }
}

async function showMainMenu(player) {
  const result = await new ActionFormData()
    .title("§l§bBEDROCK NETWORK")
    .body("Selecciona un mundo o minijuego.")
    .button("§aSurvival\n§7Mundo principal")
    .button("§cPvP\n§71v1 · 2v2 · 4v4")
    .button("§eBedWars\n§7Solo · Duo · Escuadra")
    .button("§dSkyWars\n§7Solo · Duo · Escuadra")
    .show(player);

  if (result.canceled) return;
  if (result.selection === 0) transfer(player, NETWORK.survival);
  if (result.selection === 1) transfer(player, NETWORK.pvp);
  if (result.selection === 2) transfer(player, NETWORK.bedwars);
  if (result.selection === 3) transfer(player, NETWORK.skywars);
}

world.afterEvents.playerSpawn.subscribe(({ player, initialSpawn }) => {
  if (!initialSpawn) return;
  system.run(() => {
    try {
      player.runCommand("gamemode adventure @s");
      player.runCommand("effect @s resistance infinite 255 true");
      player.runCommand("effect @s saturation infinite 1 true");
      player.sendMessage("§bBienvenido. §fUsa los NPC o el menú para elegir servidor.");
    } catch {}
  });
});

world.beforeEvents.playerBreakBlock.subscribe((event) => {
  event.cancel = true;
});

world.beforeEvents.playerPlaceBlock.subscribe((event) => {
  event.cancel = true;
});

world.afterEvents.playerInteractWithEntity.subscribe((event) => {
  const { player, target } = event;
  const name = (target.nameTag ?? "").trim().toLowerCase();
  system.run(() => {
    if (name === NPC.survival.toLowerCase()) transfer(player, NETWORK.survival);
    else if (name === NPC.pvp.toLowerCase()) transfer(player, NETWORK.pvp);
    else if (name === NPC.bedwars.toLowerCase()) transfer(player, NETWORK.bedwars);
    else if (name === NPC.skywars.toLowerCase()) transfer(player, NETWORK.skywars);
  });
});

world.afterEvents.itemUse.subscribe((event) => {
  const item = event.itemStack;
  if (!item || item.typeId !== "minecraft:compass") return;
  system.run(() => showMainMenu(event.source).catch(() => {}));
});

world.beforeEvents.chatSend.subscribe((event) => {
  const message = event.message.trim().toLowerCase();
  const player = event.sender;

  if (message === "!menu") {
    event.cancel = true;
    system.run(() => showMainMenu(player).catch(() => {}));
    return;
  }

  if (message === "!buildhub") {
    event.cancel = true;
    system.run(() => buildHub(player));
  }
});
