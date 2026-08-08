package dev.gh0stdeveloper.minecraft.bedwars;

import cn.nukkit.Player;
import cn.nukkit.block.Block;
import cn.nukkit.command.Command;
import cn.nukkit.command.CommandSender;
import cn.nukkit.event.EventHandler;
import cn.nukkit.event.Listener;
import cn.nukkit.event.block.BlockBreakEvent;
import cn.nukkit.event.block.BlockPlaceEvent;
import cn.nukkit.event.entity.EntityDamageByEntityEvent;
import cn.nukkit.event.entity.EntityDamageEvent;
import cn.nukkit.event.player.PlayerDeathEvent;
import cn.nukkit.event.player.PlayerJoinEvent;
import cn.nukkit.event.player.PlayerMoveEvent;
import cn.nukkit.event.player.PlayerQuitEvent;
import cn.nukkit.inventory.Inventory;
import cn.nukkit.item.Item;
import cn.nukkit.level.Level;
import cn.nukkit.level.Position;
import cn.nukkit.math.Vector3;
import cn.nukkit.plugin.PluginBase;
import cn.nukkit.utils.TextFormat;

import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class NexoraBedWars extends PluginBase implements Listener {
    private static final Map<String, Integer> REQUIRED = Map.of("solo", 2, "duo", 4, "squad", 8);
    private final Map<String, LinkedHashSet<UUID>> queues = new HashMap<>();
    private final Map<UUID, BedWarsMatch> playerMatches = new HashMap<>();
    private boolean[] arenaBusy;
    private Level level;
    private int baseY;
    private int ironPeriod;
    private int goldPeriodCycles;
    private int generatorCycle;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        baseY = getConfig().getInt("arena-base-y", 180);
        ironPeriod = Math.max(20, getConfig().getInt("iron-period-ticks", 40));
        goldPeriodCycles = Math.max(2, getConfig().getInt("gold-period-cycles", 5));
        int slots = Math.max(1, Math.min(8, getConfig().getInt("arena-slots", 4)));
        arenaBusy = new boolean[slots];
        REQUIRED.keySet().forEach(mode -> queues.put(mode, new LinkedHashSet<>()));
        getServer().getPluginManager().registerEvents(this, this);
        level = getServer().getDefaultLevel();
        getServer().getScheduler().scheduleDelayedTask(this, () -> {
            buildInfrastructure();
            for (Player player : getServer().getOnlinePlayers().values()) prepareWaitingPlayer(player);
            scheduleGeneratorTick();
        }, 20);
        getLogger().info("Nexora BedWars 0.1 habilitado: Solo, Duo y Escuadra con arenas nativas.");
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Este comando solo puede usarlo un jugador.");
            return true;
        }
        if (command.getName().equalsIgnoreCase("lobby")) {
            leaveEverything(player, false);
            transferToLobby(player);
            return true;
        }
        if (args.length == 0) {
            sendHelp(player);
            return true;
        }
        String action = args[0].toLowerCase(Locale.ROOT);
        if (REQUIRED.containsKey(action)) {
            joinQueue(player, action);
            return true;
        }
        switch (action) {
            case "leave", "salir" -> leaveEverything(player, true);
            case "status", "estado" -> sendStatus(player);
            case "shop", "tienda" -> {
                if (args.length < 2) sendShopHelp(player);
                else buy(player, args[1].toLowerCase(Locale.ROOT));
            }
            case "rebuild", "reconstruir" -> rebuild(player);
            default -> sendHelp(player);
        }
        return true;
    }

    private void sendHelp(Player player) {
        player.sendMessage(TextFormat.GOLD + "Nexora BedWars" + TextFormat.WHITE + " — /bw <solo|duo|squad|leave|status|shop>");
        player.sendMessage(TextFormat.GRAY + "Solo=1v1 · Duo=2v2 · Squad=4v4. Protege tu cama-núcleo y destruye la rival.");
    }

    private void sendShopHelp(Player player) {
        player.sendMessage(TextFormat.YELLOW + "Tienda: " + TextFormat.WHITE + "/bw shop <blocks|sword|pickaxe|bow>");
        player.sendMessage(TextFormat.GRAY + "blocks 4 hierro · sword 10 hierro · pickaxe 12 hierro · bow 8 oro");
    }

    private void sendStatus(Player player) {
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null) {
            player.sendMessage(TextFormat.AQUA + "Colas: " + TextFormat.WHITE
                    + "solo=" + queues.get("solo").size() + "/2 · duo=" + queues.get("duo").size() + "/4 · squad=" + queues.get("squad").size() + "/8");
            return;
        }
        Team team = match.teamOf(player);
        player.sendMessage(TextFormat.GOLD + "Partida " + match.mode + " · arena " + (match.slot + 1)
                + " · equipo " + team.label + " · cama roja=" + match.redBedAlive + " · cama azul=" + match.blueBedAlive);
    }

    private synchronized void joinQueue(Player player, String mode) {
        if (playerMatches.containsKey(player.getUniqueId())) {
            player.sendMessage(TextFormat.RED + "Ya estás en una partida.");
            return;
        }
        removeFromQueues(player.getUniqueId());
        LinkedHashSet<UUID> queue = queues.get(mode);
        queue.add(player.getUniqueId());
        player.sendMessage(TextFormat.GREEN + "Cola BedWars " + mode + ": " + queue.size() + "/" + REQUIRED.get(mode));
        tryStartMatches(mode);
    }

    private synchronized void tryStartMatches(String mode) {
        LinkedHashSet<UUID> queue = queues.get(mode);
        int required = REQUIRED.get(mode);
        while (queue.size() >= required) {
            int slot = allocateArena();
            if (slot < 0) return;
            List<Player> selected = new ArrayList<>();
            List<UUID> stale = new ArrayList<>();
            for (UUID id : new ArrayList<>(queue)) {
                Player p = getServer().getPlayer(id).orElse(null);
                if (p == null || !p.isOnline()) stale.add(id);
                else if (selected.size() < required) selected.add(p);
            }
            stale.forEach(queue::remove);
            if (selected.size() < required) {
                releaseArena(slot);
                return;
            }
            selected.forEach(p -> queue.remove(p.getUniqueId()));
            BedWarsMatch match = new BedWarsMatch(mode, slot, selected);
            selected.forEach(p -> playerMatches.put(p.getUniqueId(), match));
            match.start();
        }
    }

    private synchronized int allocateArena() {
        for (int i = 0; i < arenaBusy.length; i++) {
            if (!arenaBusy[i]) {
                arenaBusy[i] = true;
                return i;
            }
        }
        return -1;
    }

    private synchronized void releaseArena(int slot) {
        if (slot >= 0 && slot < arenaBusy.length) arenaBusy[slot] = false;
    }

    private synchronized void removeFromQueues(UUID id) {
        queues.values().forEach(queue -> queue.remove(id));
    }

    private void leaveEverything(Player player, boolean notify) {
        removeFromQueues(player.getUniqueId());
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.forfeit(player);
        if (notify) {
            prepareWaitingPlayer(player);
            player.sendMessage(TextFormat.GRAY + "Saliste de BedWars.");
        }
    }

    private void transferToLobby(Player player) {
        player.transfer(new InetSocketAddress(
                getConfig().getString("lobby-host", "127.0.0.1"),
                getConfig().getInt("lobby-port", 19132)));
    }

    private void rebuild(Player player) {
        if (!player.isOp()) {
            player.sendMessage(TextFormat.RED + "Solo un operador puede reconstruir arenas.");
            return;
        }
        if (!playerMatches.isEmpty()) {
            player.sendMessage(TextFormat.RED + "No puedes reconstruir mientras existen partidas activas.");
            return;
        }
        buildInfrastructure();
        player.sendMessage(TextFormat.GREEN + "Infraestructura BedWars reconstruida.");
    }

    private void buy(Player player, String type) {
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || match.eliminated.contains(player.getUniqueId())) {
            player.sendMessage(TextFormat.RED + "Solo puedes comprar durante una partida activa.");
            return;
        }
        Inventory inv = player.getInventory();
        switch (type) {
            case "blocks", "bloques" -> {
                if (!pay(inv, "iron_ingot", 4)) returnCost(player, "4 hierro");
                else {
                    String wool = match.teamOf(player) == Team.RED ? "red_wool" : "blue_wool";
                    inv.addItem(Item.get(wool, 0, 16));
                    player.sendMessage(TextFormat.GREEN + "+16 bloques de equipo.");
                }
            }
            case "sword", "espada" -> {
                if (!pay(inv, "iron_ingot", 10)) returnCost(player, "10 hierro");
                else inv.addItem(Item.get("stone_sword", 0, 1));
            }
            case "pickaxe", "pico" -> {
                if (!pay(inv, "iron_ingot", 12)) returnCost(player, "12 hierro");
                else inv.addItem(Item.get("iron_pickaxe", 0, 1));
            }
            case "bow", "arco" -> {
                if (!pay(inv, "gold_ingot", 8)) returnCost(player, "8 oro");
                else {
                    inv.addItem(Item.get("bow", 0, 1));
                    inv.addItem(Item.get("arrow", 0, 8));
                }
            }
            default -> sendShopHelp(player);
        }
    }

    private boolean pay(Inventory inventory, String itemId, int amount) {
        Item cost = Item.get(itemId, 0, amount);
        if (!inventory.contains(cost)) return false;
        inventory.removeItem(cost);
        return true;
    }

    private void returnCost(Player player, String cost) {
        player.sendMessage(TextFormat.RED + "Necesitas " + cost + ".");
    }

    private void scheduleGeneratorTick() {
        getServer().getScheduler().scheduleDelayedTask(this, () -> {
            generatorCycle++;
            for (BedWarsMatch match : new HashSet<>(playerMatches.values())) match.generateResources(generatorCycle);
            scheduleGeneratorTick();
        }, ironPeriod);
    }

    private Position waitingSpawn() {
        return Position.fromObject(new Vector3(0.5, baseY + 2, 0.5), level);
    }

    private Vector3 center(int slot) {
        int col = slot % 2;
        int row = slot / 2;
        return new Vector3((col == 0 ? -50 : 50), baseY, 120 + row * 100);
    }

    private Position teamSpawn(int slot, Team team, int index, int teamSize) {
        Vector3 c = center(slot);
        double spacing = 2.0;
        double start = -((teamSize - 1) * spacing) / 2.0;
        return Position.fromObject(new Vector3(c.x + start + index * spacing + 0.5, baseY + 2, c.z + (team == Team.RED ? -29 : 29) + 0.5), level);
    }

    private Position spectatorSpawn(int slot) {
        Vector3 c = center(slot);
        return Position.fromObject(new Vector3(c.x + 0.5, baseY + 14, c.z + 0.5), level);
    }

    private BlockPos corePos(int slot, Team team) {
        Vector3 c = center(slot);
        return new BlockPos((int) c.x, baseY + 1, (int) c.z + (team == Team.RED ? -25 : 25));
    }

    private void buildInfrastructure() {
        if (level == null) level = getServer().getDefaultLevel();
        buildWaitingLobby();
        for (int i = 0; i < arenaBusy.length; i++) buildArena(i);
    }

    private void buildWaitingLobby() {
        Block floor = Block.get(Block.STONE);
        Block rail = Block.get(Block.GLASS);
        for (int x = -10; x <= 10; x++) for (int z = -10; z <= 10; z++) level.setBlock(new Vector3(x, baseY, z), floor.clone());
        for (int y = baseY + 1; y <= baseY + 3; y++) {
            for (int x = -10; x <= 10; x++) {
                level.setBlock(new Vector3(x, y, -10), rail.clone());
                level.setBlock(new Vector3(x, y, 10), rail.clone());
            }
            for (int z = -10; z <= 10; z++) {
                level.setBlock(new Vector3(-10, y, z), rail.clone());
                level.setBlock(new Vector3(10, y, z), rail.clone());
            }
        }
    }

    private void buildArena(int slot) {
        Vector3 c = center(slot);
        int cx = (int) c.x;
        int cz = (int) c.z;
        Block stone = Block.get(Block.STONE);
        Block bedrock = Block.get(Block.BEDROCK);
        for (int zCenter : new int[]{cz - 27, cz, cz + 27}) {
            int rx = zCenter == cz ? 9 : 10;
            int rz = zCenter == cz ? 9 : 8;
            for (int x = cx - rx; x <= cx + rx; x++) {
                for (int z = zCenter - rz; z <= zCenter + rz; z++) {
                    boolean edge = x == cx - rx || x == cx + rx || z == zCenter - rz || z == zCenter + rz;
                    level.setBlock(new Vector3(x, baseY, z), (edge ? bedrock : stone).clone());
                }
            }
        }
        restoreCore(slot, Team.RED);
        restoreCore(slot, Team.BLUE);
    }

    private void restoreCore(int slot, Team team) {
        BlockPos p = corePos(slot, team);
        level.setBlock(new Vector3(p.x, p.y, p.z), Block.get(team == Team.RED ? Block.REDSTONE_BLOCK : Block.LAPIS_BLOCK));
    }

    private void removeCore(int slot, Team team) {
        BlockPos p = corePos(slot, team);
        level.setBlock(new Vector3(p.x, p.y, p.z), Block.get(Block.AIR));
    }

    private void resetPlayer(Player player) {
        player.getInventory().clearAll();
        player.getInventory().getArmorInventory().clearAll();
        player.removeAllEffects();
        player.setMaxHealth(20);
        player.setHealth(player.getMaxHealth());
        player.setExperience(0, 0);
        player.getFoodData().setFood(player.getFoodData().getMaxFood());
    }

    private void giveStarter(Player player) {
        resetPlayer(player);
        player.getInventory().addItem(Item.get("wooden_sword", 0, 1));
    }

    private void prepareWaitingPlayer(Player player) {
        if (player == null || !player.isOnline()) return;
        resetPlayer(player);
        player.setGamemode(2);
        player.teleport(waitingSpawn());
        player.sendMessage(TextFormat.GOLD + "Nexora BedWars: " + TextFormat.WHITE + "/bw solo, /bw duo o /bw squad");
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        getServer().getScheduler().scheduleDelayedTask(this, () -> prepareWaitingPlayer(event.getPlayer()), 10);
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        removeFromQueues(player.getUniqueId());
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.forfeit(player);
    }

    @EventHandler
    public void onDamage(EntityDamageEvent event) {
        if (!(event.getEntity() instanceof Player player)) return;
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        if (event instanceof EntityDamageByEntityEvent byEntity && byEntity.getDamager() instanceof Player damager) {
            BedWarsMatch other = playerMatches.get(damager.getUniqueId());
            if (other != match || match.teamOf(player) == match.teamOf(damager)) {
                event.setCancelled();
                return;
            }
        }
        if (event.getFinalDamage() >= player.getHealth()) {
            event.setCancelled();
            match.handleDeath(player);
        }
    }

    @EventHandler
    public void onDeath(PlayerDeathEvent event) {
        BedWarsMatch match = playerMatches.get(event.getEntity().getUniqueId());
        if (match == null) return;
        event.setCancelled();
        match.handleDeath(event.getEntity());
    }

    @EventHandler
    public void onMove(PlayerMoveEvent event) {
        BedWarsMatch match = playerMatches.get(event.getPlayer().getUniqueId());
        if (match != null && match.active && event.getTo().getY() < baseY - 10) match.handleDeath(event.getPlayer());
    }

    @EventHandler
    public void onPlace(BlockPlaceEvent event) {
        Player player = event.getPlayer();
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        Block block = event.getBlock();
        if (!match.insideArena(block)) {
            event.setCancelled();
            player.sendMessage(TextFormat.RED + "No puedes construir fuera de la arena.");
            return;
        }
        match.placedBlocks.add(BlockPos.of(block));
    }

    @EventHandler
    public void onBreak(BlockBreakEvent event) {
        Player player = event.getPlayer();
        BedWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        BlockPos pos = BlockPos.of(event.getBlock());
        Team playerTeam = match.teamOf(player);
        if (pos.equals(corePos(match.slot, Team.RED))) {
            event.setCancelled();
            match.breakCore(player, playerTeam, Team.RED);
            return;
        }
        if (pos.equals(corePos(match.slot, Team.BLUE))) {
            event.setCancelled();
            match.breakCore(player, playerTeam, Team.BLUE);
            return;
        }
        if (match.placedBlocks.remove(pos)) return;
        event.setCancelled();
        player.sendMessage(TextFormat.GRAY + "Solo puedes romper bloques colocados durante esta partida o la cama rival.");
    }

    private enum Team {
        RED("ROJO", TextFormat.RED.toString()), BLUE("AZUL", TextFormat.AQUA.toString());
        private final String label;
        private final String color;
        Team(String label, String color) { this.label = label; this.color = color; }
    }

    private record BlockPos(int x, int y, int z) {
        static BlockPos of(Block block) { return new BlockPos(block.getFloorX(), block.getFloorY(), block.getFloorZ()); }
    }

    private final class BedWarsMatch {
        private final String mode;
        private final int slot;
        private final List<Player> red = new ArrayList<>();
        private final List<Player> blue = new ArrayList<>();
        private final Set<UUID> eliminated = new HashSet<>();
        private final Set<UUID> respawning = new HashSet<>();
        private final Set<BlockPos> placedBlocks = new HashSet<>();
        private boolean redBedAlive = true;
        private boolean blueBedAlive = true;
        private boolean active;
        private boolean ended;

        private BedWarsMatch(String mode, int slot, List<Player> players) {
            this.mode = mode;
            this.slot = slot;
            int teamSize = players.size() / 2;
            for (int i = 0; i < players.size(); i++) (i < teamSize ? red : blue).add(players.get(i));
        }

        private void start() {
            cleanupPlacedBlocks();
            redBedAlive = true;
            blueBedAlive = true;
            restoreCore(slot, Team.RED);
            restoreCore(slot, Team.BLUE);
            active = true;
            spawnTeam(red, Team.RED);
            spawnTeam(blue, Team.BLUE);
            broadcast(TextFormat.GOLD + "BedWars " + mode + " iniciado. " + TextFormat.GRAY + "Recibes hierro automáticamente y oro cada " + goldPeriodCycles + " ciclos. Usa /bw shop.");
        }

        private void spawnTeam(List<Player> players, Team team) {
            for (int i = 0; i < players.size(); i++) {
                Player p = players.get(i);
                if (!p.isOnline()) continue;
                giveStarter(p);
                p.setGamemode(0);
                p.teleport(teamSpawn(slot, team, i, players.size()));
                p.sendTitle(team.color + "EQUIPO " + team.label, TextFormat.GRAY + "Protege tu cama-núcleo");
            }
        }

        private Team teamOf(Player player) { return red.contains(player) ? Team.RED : Team.BLUE; }
        private boolean bedAlive(Team team) { return team == Team.RED ? redBedAlive : blueBedAlive; }

        private void generateResources(int cycle) {
            if (!active || ended) return;
            for (Player player : allPlayers()) {
                if (!player.isOnline() || eliminated.contains(player.getUniqueId()) || respawning.contains(player.getUniqueId())) continue;
                player.getInventory().addItem(Item.get("iron_ingot", 0, 1));
                if (cycle % goldPeriodCycles == 0) player.getInventory().addItem(Item.get("gold_ingot", 0, 1));
            }
        }

        private void breakCore(Player player, Team playerTeam, Team targetTeam) {
            if (playerTeam == targetTeam) {
                player.sendMessage(TextFormat.RED + "No puedes destruir tu propia cama.");
                return;
            }
            if (!bedAlive(targetTeam)) {
                player.sendMessage(TextFormat.GRAY + "Esa cama ya fue destruida.");
                return;
            }
            if (targetTeam == Team.RED) redBedAlive = false; else blueBedAlive = false;
            removeCore(slot, targetTeam);
            broadcast(TextFormat.GOLD + player.getName() + TextFormat.WHITE + " destruyó la cama del equipo " + targetTeam.color + targetTeam.label + TextFormat.WHITE + ". Ya no podrán reaparecer.");
        }

        private void handleDeath(Player player) {
            if (!active || ended || eliminated.contains(player.getUniqueId()) || !respawning.add(player.getUniqueId())) return;
            Team team = teamOf(player);
            resetPlayer(player);
            player.setGamemode(3);
            player.teleport(spectatorSpawn(slot));
            if (bedAlive(team)) {
                player.sendTitle(TextFormat.YELLOW + "REAPARECIENDO", TextFormat.GRAY + "Tu cama sigue viva");
                getServer().getScheduler().scheduleDelayedTask(NexoraBedWars.this, () -> respawn(player, team), 60);
            } else {
                respawning.remove(player.getUniqueId());
                eliminated.add(player.getUniqueId());
                player.sendTitle(TextFormat.RED + "ELIMINADO", TextFormat.GRAY + "Tu cama fue destruida");
                checkWinner();
            }
        }

        private void respawn(Player player, Team team) {
            if (ended || !player.isOnline()) return;
            respawning.remove(player.getUniqueId());
            if (!bedAlive(team)) {
                eliminated.add(player.getUniqueId());
                player.sendTitle(TextFormat.RED + "ELIMINADO", TextFormat.GRAY + "La cama cayó mientras reaparecías");
                checkWinner();
                return;
            }
            List<Player> teamPlayers = team == Team.RED ? red : blue;
            int index = Math.max(0, teamPlayers.indexOf(player));
            giveStarter(player);
            player.setGamemode(0);
            player.teleport(teamSpawn(slot, team, index, teamPlayers.size()));
            player.sendTitle(TextFormat.GREEN + "REAPARECISTE", TextFormat.GRAY + "Protege tu cama");
        }

        private void forfeit(Player player) {
            if (ended) return;
            respawning.remove(player.getUniqueId());
            eliminated.add(player.getUniqueId());
            checkWinner();
        }

        private void checkWinner() {
            boolean redAlive = red.stream().anyMatch(p -> p.isOnline() && !eliminated.contains(p.getUniqueId()));
            boolean blueAlive = blue.stream().anyMatch(p -> p.isOnline() && !eliminated.contains(p.getUniqueId()));
            if (redAlive && blueAlive) return;
            finish(redAlive ? Team.RED : Team.BLUE);
        }

        private void finish(Team winner) {
            if (ended) return;
            ended = true;
            active = false;
            broadcastTitle(winner.color + "EQUIPO " + winner.label + " GANA", TextFormat.GRAY + "Partida terminada");
            getServer().getScheduler().scheduleDelayedTask(NexoraBedWars.this, () -> {
                cleanupPlacedBlocks();
                restoreCore(slot, Team.RED);
                restoreCore(slot, Team.BLUE);
                for (Player p : allPlayers()) {
                    playerMatches.remove(p.getUniqueId());
                    if (p.isOnline()) prepareWaitingPlayer(p);
                }
                releaseArena(slot);
                for (String queueMode : REQUIRED.keySet()) tryStartMatches(queueMode);
            }, 80);
        }

        private boolean insideArena(Block block) {
            Vector3 c = center(slot);
            int x = block.getFloorX(), y = block.getFloorY(), z = block.getFloorZ();
            return x >= c.x - 34 && x <= c.x + 34 && z >= c.z - 40 && z <= c.z + 40 && y >= baseY && y <= baseY + 28;
        }

        private void cleanupPlacedBlocks() {
            for (BlockPos pos : new HashSet<>(placedBlocks)) level.setBlock(new Vector3(pos.x, pos.y, pos.z), Block.get(Block.AIR));
            placedBlocks.clear();
        }

        private List<Player> allPlayers() {
            List<Player> all = new ArrayList<>(red);
            all.addAll(blue);
            return all;
        }

        private void broadcast(String message) {
            for (Player p : allPlayers()) if (p.isOnline()) p.sendMessage(message);
        }

        private void broadcastTitle(String title, String subtitle) {
            for (Player p : allPlayers()) if (p.isOnline()) p.sendTitle(title, subtitle);
        }
    }
}
