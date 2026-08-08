package dev.gh0stdeveloper.minecraft.skywars;

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
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.UUID;

public final class NexoraSkyWars extends PluginBase implements Listener {
    private static final Map<String, Integer> REQUIRED = Map.of("solo", 4, "duo", 8, "squad", 16);
    private static final Map<String, Integer> TEAM_SIZE = Map.of("solo", 1, "duo", 2, "squad", 4);
    private final Map<String, LinkedHashSet<UUID>> queues = new HashMap<>();
    private final Map<UUID, SkyWarsMatch> playerMatches = new HashMap<>();
    private final Random random = new Random();
    private boolean[] arenaBusy;
    private Level level;
    private int baseY;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        baseY = getConfig().getInt("arena-base-y", 180);
        int slots = Math.max(1, Math.min(4, getConfig().getInt("arena-slots", 2)));
        arenaBusy = new boolean[slots];
        REQUIRED.keySet().forEach(mode -> queues.put(mode, new LinkedHashSet<>()));
        getServer().getPluginManager().registerEvents(this, this);
        level = getServer().getDefaultLevel();
        getServer().getScheduler().scheduleDelayedTask(this, () -> {
            buildInfrastructure();
            for (Player player : getServer().getOnlinePlayers().values()) prepareWaitingPlayer(player);
        }, 20);
        getLogger().info("Nexora SkyWars 0.1 habilitado: Solo, Duo y Escuadra con islas nativas.");
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
            case "rebuild", "reconstruir" -> rebuild(player);
            default -> sendHelp(player);
        }
        return true;
    }

    private void sendHelp(Player player) {
        player.sendMessage(TextFormat.LIGHT_PURPLE + "Nexora SkyWars" + TextFormat.WHITE + " — /sw <solo|duo|squad|leave|status>");
        player.sendMessage(TextFormat.GRAY + "Solo=4 jugadores · Duo=8 · Squad=16. Cuatro islas/equipos por partida.");
    }

    private void sendStatus(Player player) {
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null) {
            player.sendMessage(TextFormat.AQUA + "Colas: " + TextFormat.WHITE
                    + "solo=" + queues.get("solo").size() + "/4 · duo=" + queues.get("duo").size() + "/8 · squad=" + queues.get("squad").size() + "/16");
            return;
        }
        Team team = match.teamOf(player);
        player.sendMessage(TextFormat.LIGHT_PURPLE + "SkyWars " + match.mode + " · arena " + (match.slot + 1)
                + " · equipo " + team.color + team.label + TextFormat.WHITE + " · equipos vivos=" + match.livingTeams());
    }

    private synchronized void joinQueue(Player player, String mode) {
        if (playerMatches.containsKey(player.getUniqueId())) {
            player.sendMessage(TextFormat.RED + "Ya estás en una partida.");
            return;
        }
        removeFromQueues(player.getUniqueId());
        LinkedHashSet<UUID> queue = queues.get(mode);
        queue.add(player.getUniqueId());
        player.sendMessage(TextFormat.GREEN + "Cola SkyWars " + mode + ": " + queue.size() + "/" + REQUIRED.get(mode));
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
            SkyWarsMatch match = new SkyWarsMatch(mode, slot, selected);
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
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.eliminate(player, "abandonó");
        if (notify) {
            prepareWaitingPlayer(player);
            player.sendMessage(TextFormat.GRAY + "Saliste de SkyWars.");
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
            player.sendMessage(TextFormat.RED + "No puedes reconstruir con partidas activas.");
            return;
        }
        buildInfrastructure();
        player.sendMessage(TextFormat.GREEN + "Infraestructura SkyWars reconstruida.");
    }

    private Position waitingSpawn() {
        return Position.fromObject(new Vector3(0.5, baseY + 2, 0.5), level);
    }

    private Vector3 center(int slot) {
        return new Vector3(slot == 0 ? -70 : 70, baseY, 150);
    }

    private Vector3 islandCenter(int slot, Team team) {
        Vector3 c = center(slot);
        return switch (team) {
            case RED -> new Vector3(c.x, baseY, c.z - 30);
            case BLUE -> new Vector3(c.x + 30, baseY, c.z);
            case GREEN -> new Vector3(c.x, baseY, c.z + 30);
            case YELLOW -> new Vector3(c.x - 30, baseY, c.z);
        };
    }

    private Position teamSpawn(int slot, Team team, int index, int teamSize) {
        Vector3 island = islandCenter(slot, team);
        double spacing = 1.5;
        double start = -((teamSize - 1) * spacing) / 2.0;
        return Position.fromObject(new Vector3(island.x + start + index * spacing + 0.5, baseY + 2, island.z + 0.5), level);
    }

    private Position spectatorSpawn(int slot) {
        Vector3 c = center(slot);
        return Position.fromObject(new Vector3(c.x + 0.5, baseY + 15, c.z + 0.5), level);
    }

    private void buildInfrastructure() {
        if (level == null) level = getServer().getDefaultLevel();
        buildWaitingLobby();
        for (int i = 0; i < arenaBusy.length; i++) buildArena(i);
    }

    private void buildWaitingLobby() {
        Block stone = Block.get(Block.STONE);
        Block glass = Block.get(Block.GLASS);
        for (int x = -10; x <= 10; x++) for (int z = -10; z <= 10; z++) level.setBlock(new Vector3(x, baseY, z), stone.clone());
        for (int y = baseY + 1; y <= baseY + 3; y++) {
            for (int x = -10; x <= 10; x++) {
                level.setBlock(new Vector3(x, y, -10), glass.clone());
                level.setBlock(new Vector3(x, y, 10), glass.clone());
            }
            for (int z = -10; z <= 10; z++) {
                level.setBlock(new Vector3(-10, y, z), glass.clone());
                level.setBlock(new Vector3(10, y, z), glass.clone());
            }
        }
    }

    private void platform(Vector3 c, int radius) {
        Block stone = Block.get(Block.STONE);
        Block bedrock = Block.get(Block.BEDROCK);
        for (int x = (int) c.x - radius; x <= (int) c.x + radius; x++) {
            for (int z = (int) c.z - radius; z <= (int) c.z + radius; z++) {
                boolean edge = x == (int) c.x - radius || x == (int) c.x + radius || z == (int) c.z - radius || z == (int) c.z + radius;
                level.setBlock(new Vector3(x, baseY, z), (edge ? bedrock : stone).clone());
            }
        }
    }

    private void buildArena(int slot) {
        platform(center(slot), 8);
        for (Team team : Team.values()) platform(islandCenter(slot, team), 5);
        restoreCrates(slot);
    }

    private Set<BlockPos> islandCrates(int slot) {
        Set<BlockPos> out = new HashSet<>();
        for (Team team : Team.values()) {
            Vector3 c = islandCenter(slot, team);
            out.add(new BlockPos((int) c.x, baseY + 1, (int) c.z));
        }
        return out;
    }

    private Set<BlockPos> centerCrates(int slot) {
        Vector3 c = center(slot);
        return Set.of(
                new BlockPos((int) c.x - 2, baseY + 1, (int) c.z - 2),
                new BlockPos((int) c.x + 2, baseY + 1, (int) c.z - 2),
                new BlockPos((int) c.x - 2, baseY + 1, (int) c.z + 2),
                new BlockPos((int) c.x + 2, baseY + 1, (int) c.z + 2));
    }

    private void restoreCrates(int slot) {
        for (BlockPos p : islandCrates(slot)) level.setBlock(new Vector3(p.x, p.y, p.z), Block.get(Block.GOLD_BLOCK));
        for (BlockPos p : centerCrates(slot)) level.setBlock(new Vector3(p.x, p.y, p.z), Block.get(Block.DIAMOND_BLOCK));
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

    private void giveStarter(Player player, Team team) {
        resetPlayer(player);
        player.getInventory().addItem(Item.get("wooden_sword", 0, 1));
        player.getInventory().addItem(Item.get(team.wool, 0, 16));
    }

    private void giveLoot(Player player, boolean centerTier) {
        if (centerTier) {
            switch (random.nextInt(4)) {
                case 0 -> player.getInventory().addItem(Item.get("iron_sword", 0, 1));
                case 1 -> { player.getInventory().addItem(Item.get("bow", 0, 1)); player.getInventory().addItem(Item.get("arrow", 0, 16)); }
                case 2 -> player.getInventory().addItem(Item.get("ender_pearl", 0, 2));
                default -> player.getInventory().addItem(Item.get("golden_apple", 0, 2));
            }
            player.sendMessage(TextFormat.AQUA + "Loot central obtenido.");
        } else {
            switch (random.nextInt(4)) {
                case 0 -> player.getInventory().addItem(Item.get("stone_sword", 0, 1));
                case 1 -> player.getInventory().addItem(Item.get("iron_pickaxe", 0, 1));
                case 2 -> { player.getInventory().addItem(Item.get("bow", 0, 1)); player.getInventory().addItem(Item.get("arrow", 0, 8)); }
                default -> player.getInventory().addItem(Item.get("golden_apple", 0, 1));
            }
            player.sendMessage(TextFormat.YELLOW + "Loot de isla obtenido.");
        }
    }

    private void prepareWaitingPlayer(Player player) {
        if (player == null || !player.isOnline()) return;
        resetPlayer(player);
        player.setGamemode(2);
        player.teleport(waitingSpawn());
        player.sendMessage(TextFormat.LIGHT_PURPLE + "Nexora SkyWars: " + TextFormat.WHITE + "/sw solo, /sw duo o /sw squad");
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        getServer().getScheduler().scheduleDelayedTask(this, () -> prepareWaitingPlayer(event.getPlayer()), 10);
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        removeFromQueues(player.getUniqueId());
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.eliminate(player, "abandonó");
    }

    @EventHandler
    public void onDamage(EntityDamageEvent event) {
        if (!(event.getEntity() instanceof Player player)) return;
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        if (event instanceof EntityDamageByEntityEvent byEntity && byEntity.getDamager() instanceof Player damager) {
            SkyWarsMatch other = playerMatches.get(damager.getUniqueId());
            if (other != match || match.teamOf(player) == match.teamOf(damager)) {
                event.setCancelled();
                return;
            }
        }
        if (event.getFinalDamage() >= player.getHealth()) {
            event.setCancelled();
            match.eliminate(player, "fue eliminado");
        }
    }

    @EventHandler
    public void onDeath(PlayerDeathEvent event) {
        SkyWarsMatch match = playerMatches.get(event.getEntity().getUniqueId());
        if (match == null) return;
        event.setCancelled();
        match.eliminate(event.getEntity(), "fue eliminado");
    }

    @EventHandler
    public void onMove(PlayerMoveEvent event) {
        SkyWarsMatch match = playerMatches.get(event.getPlayer().getUniqueId());
        if (match != null && match.active && event.getTo().getY() < baseY - 10) match.eliminate(event.getPlayer(), "cayó al vacío");
    }

    @EventHandler
    public void onPlace(BlockPlaceEvent event) {
        Player player = event.getPlayer();
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        Block block = event.getBlock();
        if (!match.insideArena(block)) {
            event.setCancelled();
            return;
        }
        match.placedBlocks.add(BlockPos.of(block));
    }

    @EventHandler
    public void onBreak(BlockBreakEvent event) {
        Player player = event.getPlayer();
        SkyWarsMatch match = playerMatches.get(player.getUniqueId());
        if (match == null || !match.active || match.eliminated.contains(player.getUniqueId())) {
            event.setCancelled();
            return;
        }
        BlockPos pos = BlockPos.of(event.getBlock());
        if (match.openCrate(player, pos)) {
            event.setCancelled();
            return;
        }
        if (match.placedBlocks.remove(pos)) return;
        event.setCancelled();
        player.sendMessage(TextFormat.GRAY + "Solo puedes romper bloques colocados en la partida o loot-crates.");
    }

    private enum Team {
        RED("ROJO", TextFormat.RED.toString(), "red_wool"),
        BLUE("AZUL", TextFormat.AQUA.toString(), "blue_wool"),
        GREEN("VERDE", TextFormat.GREEN.toString(), "green_wool"),
        YELLOW("AMARILLO", TextFormat.YELLOW.toString(), "yellow_wool");
        private final String label;
        private final String color;
        private final String wool;
        Team(String label, String color, String wool) { this.label = label; this.color = color; this.wool = wool; }
    }

    private record BlockPos(int x, int y, int z) {
        static BlockPos of(Block block) { return new BlockPos(block.getFloorX(), block.getFloorY(), block.getFloorZ()); }
    }

    private final class SkyWarsMatch {
        private final String mode;
        private final int slot;
        private final Map<Team, List<Player>> teams = new LinkedHashMap<>();
        private final Set<UUID> eliminated = new HashSet<>();
        private final Set<BlockPos> placedBlocks = new HashSet<>();
        private final Set<BlockPos> openedCrates = new HashSet<>();
        private boolean active;
        private boolean ended;

        private SkyWarsMatch(String mode, int slot, List<Player> players) {
            this.mode = mode;
            this.slot = slot;
            int size = TEAM_SIZE.get(mode);
            int cursor = 0;
            for (Team team : Team.values()) {
                List<Player> members = new ArrayList<>();
                for (int i = 0; i < size; i++) members.add(players.get(cursor++));
                teams.put(team, members);
            }
        }

        private void start() {
            cleanupArena();
            restoreCrates(slot);
            active = true;
            for (Map.Entry<Team, List<Player>> entry : teams.entrySet()) {
                Team team = entry.getKey();
                List<Player> members = entry.getValue();
                for (int i = 0; i < members.size(); i++) {
                    Player p = members.get(i);
                    if (!p.isOnline()) continue;
                    giveStarter(p, team);
                    p.setGamemode(0);
                    p.teleport(teamSpawn(slot, team, i, members.size()));
                    p.sendTitle(team.color + "EQUIPO " + team.label, TextFormat.GRAY + "Abre tu loot-crate y llega al centro");
                }
            }
            broadcast(TextFormat.LIGHT_PURPLE + "SkyWars " + mode + " iniciado. " + TextFormat.GRAY + "No hay respawn; último equipo vivo gana.");
        }

        private Team teamOf(Player player) {
            for (Map.Entry<Team, List<Player>> entry : teams.entrySet()) if (entry.getValue().contains(player)) return entry.getKey();
            return Team.RED;
        }

        private boolean openCrate(Player player, BlockPos pos) {
            boolean island = islandCrates(slot).contains(pos);
            boolean centerTier = centerCrates(slot).contains(pos);
            if (!island && !centerTier) return false;
            if (!openedCrates.add(pos)) return true;
            level.setBlock(new Vector3(pos.x, pos.y, pos.z), Block.get(Block.AIR));
            giveLoot(player, centerTier);
            return true;
        }

        private void eliminate(Player player, String reason) {
            if (!active || ended || !eliminated.add(player.getUniqueId())) return;
            resetPlayer(player);
            if (player.isOnline()) {
                player.setGamemode(3);
                player.teleport(spectatorSpawn(slot));
                player.sendTitle(TextFormat.RED + "ELIMINADO", TextFormat.GRAY + reason);
            }
            broadcast(TextFormat.GRAY + player.getName() + " " + reason + ".");
            checkWinner();
        }

        private int livingTeams() {
            int count = 0;
            for (List<Player> members : teams.values()) if (members.stream().anyMatch(p -> p.isOnline() && !eliminated.contains(p.getUniqueId()))) count++;
            return count;
        }

        private void checkWinner() {
            Team winner = null;
            int alive = 0;
            for (Map.Entry<Team, List<Player>> entry : teams.entrySet()) {
                boolean teamAlive = entry.getValue().stream().anyMatch(p -> p.isOnline() && !eliminated.contains(p.getUniqueId()));
                if (teamAlive) { alive++; winner = entry.getKey(); }
            }
            if (alive > 1) return;
            if (winner != null) finish(winner);
            else finish(null);
        }

        private void finish(Team winner) {
            if (ended) return;
            ended = true;
            active = false;
            if (winner != null) broadcastTitle(winner.color + "EQUIPO " + winner.label + " GANA", TextFormat.GRAY + "SkyWars terminado");
            else broadcastTitle(TextFormat.GRAY + "SIN GANADOR", "Partida terminada");
            getServer().getScheduler().scheduleDelayedTask(NexoraSkyWars.this, () -> {
                cleanupArena();
                restoreCrates(slot);
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
            return x >= c.x - 45 && x <= c.x + 45 && z >= c.z - 45 && z <= c.z + 45 && y >= baseY && y <= baseY + 30;
        }

        private void cleanupArena() {
            for (BlockPos pos : new HashSet<>(placedBlocks)) level.setBlock(new Vector3(pos.x, pos.y, pos.z), Block.get(Block.AIR));
            for (BlockPos pos : new HashSet<>(openedCrates)) level.setBlock(new Vector3(pos.x, pos.y, pos.z), Block.get(Block.AIR));
            placedBlocks.clear();
            openedCrates.clear();
        }

        private List<Player> allPlayers() {
            List<Player> all = new ArrayList<>();
            teams.values().forEach(all::addAll);
            return all;
        }

        private void broadcast(String message) { for (Player p : allPlayers()) if (p.isOnline()) p.sendMessage(message); }
        private void broadcastTitle(String title, String subtitle) { for (Player p : allPlayers()) if (p.isOnline()) p.sendTitle(title, subtitle); }
    }
}
