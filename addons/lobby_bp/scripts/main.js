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

function subscribeIfAvailable(signal, label, handler) {
  if (signal && typeof signal.subscribe === "function") {
    signal.subscribe(handler);
    return true;
  }
  console.warn(`[Nexora Lobby] Evento no disponible en esta versión estable: ${label}`);
  return false;
}

function safeName(name) {
  return `"${String(name).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

function modeReady(mode) {
  return NETWORK.ready?.[mode] !== false;
}

function modeSuffix(mode) {
  return modeReady(mode) ? "§aLISTO" : "§6PREPARANDO MAPA";
}

function transfer(player, mode, port) {
  if (!modeReady(mode)) {
    player.sendMessage(`§e${NPC[mode] ?? mode} todavía no está habilitado. §7El administrador debe terminar/importar su mapa.`);
    return;
  }
  try {
    player.dimension.runCommand(`transfer ${safeName(player.name)} ${NETWORK.host} ${port}`);
  } catch (error) {
    player.sendMessage(`§cNo se pudo transferir: ${error}`);
  }
}

async function showMainMenu(player) {
  const result = await new ActionFormData()
    .title("§l§bBEDROCK NETWORK")
    .body(`§7Servidor: §f${NETWORK.host}\n§7Selecciona un mundo o minijuego.`)
    .button(`§aSurvival\n§7Mundo principal · ${modeSuffix("survival")}`)
    .button(`§cPvP\n§71v1 · 2v2 · 4v4 · ${modeSuffix("pvp")}`)
    .button(`§eBedWars\n§7Equipos · ${modeSuffix("bedwars")}`)
    .button(`§dSkyWars\n§7Mapas rotativos · ${modeSuffix("skywars")}`)
    .show(player);

  if (result.canceled) return;
  if (result.selection === 0) transfer(player, "survival", NETWORK.survival);
  if (result.selection === 1) transfer(player, "pvp", NETWORK.pvp);
  if (result.selection === 2) transfer(player, "bedwars", NETWORK.bedwars);
  if (result.selection === 3) transfer(player, "skywars", NETWORK.skywars);
}

subscribeIfAvailable(world.afterEvents.playerSpawn, "afterEvents.playerSpawn", ({ player, initialSpawn }) => {
  if (!initialSpawn) return;
  system.run(() => {
    try {
      player.runCommand("gamemode adventure @s");
      player.runCommand("effect @s resistance infinite 255 true");
      player.runCommand("effect @s saturation infinite 1 true");
      player.sendMessage("§bBienvenido. §fUsa los NPC o el menú para elegir servidor.");
      if (!modeReady("bedwars") || !modeReady("skywars")) {
        player.sendMessage("§7Las modalidades en preparación aparecen bloqueadas para evitar enviarte a un servidor sin mapa.");
      }
    } catch {}
  });
});

subscribeIfAvailable(world.beforeEvents.playerBreakBlock, "beforeEvents.playerBreakBlock", (event) => {
  event.cancel = true;
});

const protectsPlacement = subscribeIfAvailable(world.beforeEvents.playerPlaceBlock, "beforeEvents.playerPlaceBlock", (event) => {
  event.cancel = true;
});
if (!protectsPlacement) {
  subscribeIfAvailable(world.beforeEvents.playerInteractWithBlock, "beforeEvents.playerInteractWithBlock", (event) => {
    event.cancel = true;
  });
}

subscribeIfAvailable(world.afterEvents.playerInteractWithEntity, "afterEvents.playerInteractWithEntity", (event) => {
  const { player, target } = event;
  const name = (target.nameTag ?? "").trim().toLowerCase();
  system.run(() => {
    if (name === NPC.survival.toLowerCase()) transfer(player, "survival", NETWORK.survival);
    else if (name === NPC.pvp.toLowerCase()) transfer(player, "pvp", NETWORK.pvp);
    else if (name === NPC.bedwars.toLowerCase()) transfer(player, "bedwars", NETWORK.bedwars);
    else if (name === NPC.skywars.toLowerCase()) transfer(player, "skywars", NETWORK.skywars);
  });
});

subscribeIfAvailable(world.afterEvents.itemUse, "afterEvents.itemUse", (event) => {
  const item = event.itemStack;
  if (!item || item.typeId !== "minecraft:compass") return;
  system.run(() => showMainMenu(event.source).catch(() => {}));
});

subscribeIfAvailable(world.beforeEvents.chatSend, "beforeEvents.chatSend", (event) => {
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
