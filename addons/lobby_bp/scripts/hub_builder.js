import { system } from "@minecraft/server";

const CENTER_Y = 160;
let activeBuild = undefined;

function diskCommands(y, radius, block) {
  const commands = [];
  for (let z = -radius; z <= radius; z += 1) {
    const x = Math.floor(Math.sqrt((radius * radius) - (z * z)));
    commands.push(`fill ${-x} ${y} ${z} ${x} ${y} ${z} ${block}`);
  }
  return commands;
}

function hubCommands() {
  const commands = [
    "gamerule doDaylightCycle false",
    "time set day",
    "gamerule doWeatherCycle false",
    "weather clear",
    "gamerule doMobSpawning false",
    "gamerule keepInventory true",
    `setworldspawn 0 ${CENTER_Y + 2} 0`,
  ];

  commands.push(...diskCommands(CENTER_Y, 30, "grass_block"));
  commands.push(...diskCommands(CENTER_Y - 1, 29, "dirt"));
  commands.push(...diskCommands(CENTER_Y - 2, 27, "stone"));
  commands.push(...diskCommands(CENTER_Y - 3, 24, "stone"));
  commands.push(...diskCommands(CENTER_Y - 4, 20, "stone"));
  commands.push(...diskCommands(CENTER_Y - 5, 16, "deepslate"));
  commands.push(...diskCommands(CENTER_Y - 6, 12, "deepslate"));
  commands.push(...diskCommands(CENTER_Y - 7, 8, "deepslate"));
  commands.push(...diskCommands(CENTER_Y - 8, 4, "bedrock"));

  commands.push(
    `fill -8 ${CENTER_Y + 1} -8 8 ${CENTER_Y + 1} 8 smooth_quartz`,
    `fill -2 ${CENTER_Y + 1} -29 2 ${CENTER_Y + 1} -9 smooth_quartz`,
    `fill -2 ${CENTER_Y + 1} 9 2 ${CENTER_Y + 1} 29 smooth_quartz`,
    `fill -29 ${CENTER_Y + 1} -2 -9 ${CENTER_Y + 1} 2 smooth_quartz`,
    `fill 9 ${CENTER_Y + 1} -2 29 ${CENTER_Y + 1} 2 smooth_quartz`,
    `fill -6 ${CENTER_Y + 1} -30 6 ${CENTER_Y + 1} -22 polished_andesite`,
    `fill 22 ${CENTER_Y + 1} -6 30 ${CENTER_Y + 1} 6 polished_andesite`,
    `fill -6 ${CENTER_Y + 1} 22 6 ${CENTER_Y + 1} 30 polished_andesite`,
    `fill -30 ${CENTER_Y + 1} -6 -22 ${CENTER_Y + 1} 6 polished_andesite`,
    `setblock 0 ${CENTER_Y + 1} 0 sea_lantern`,
    `setblock 0 ${CENTER_Y + 1} -26 sea_lantern`,
    `setblock 26 ${CENTER_Y + 1} 0 sea_lantern`,
    `setblock 0 ${CENTER_Y + 1} 26 sea_lantern`,
    `setblock -26 ${CENTER_Y + 1} 0 sea_lantern`,
    `fill -3 ${CENTER_Y + 2} -3 3 ${CENTER_Y + 6} 3 air`,
  );

  return commands;
}

export function isHubBuildRunning() {
  return activeBuild !== undefined;
}

export function buildHub(player) {
  if (!player.hasTag("network.admin")) {
    player.sendMessage("§cNecesitas la etiqueta network.admin para construir el lobby.");
    return;
  }
  if (activeBuild !== undefined) {
    player.sendMessage("§eLa isla del lobby ya se está construyendo.");
    return;
  }

  const queue = hubCommands();
  const dimension = player.dimension;
  let index = 0;

  player.sendMessage(`§bConstruyendo isla flotante del lobby: §f${queue.length} operaciones.`);
  activeBuild = system.runInterval(() => {
    try {
      for (let i = 0; i < 8 && index < queue.length; i += 1, index += 1) {
        dimension.runCommand(queue[index]);
      }

      if (index >= queue.length) {
        system.clearRun(activeBuild);
        activeBuild = undefined;
        player.teleport({ x: 0.5, y: CENTER_Y + 3, z: 0.5 });
        player.sendMessage("§aIsla del lobby construida. Coloca los cuatro NPC en sus plataformas.");
        player.sendMessage("§7Norte Survival · Este PvP · Sur BedWars · Oeste SkyWars");
      }
    } catch (error) {
      system.clearRun(activeBuild);
      activeBuild = undefined;
      player.sendMessage(`§cLa construcción se detuvo: ${error}`);
    }
  }, 1);
}
