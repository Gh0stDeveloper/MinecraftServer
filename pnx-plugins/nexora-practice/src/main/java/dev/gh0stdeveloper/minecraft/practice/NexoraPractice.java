package dev.gh0stdeveloper.minecraft.practice;

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
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class NexoraPractice extends PluginBase implements Listener {
    private static final Map<String, Integer> REQUIRED = Map.of("solo", 2, "duo", 4, "squad", 8);
    private final Map<String, LinkedHashSet<UUID>> queues = new HashMap<>();
    private final Map<UUID, PracticeMatch> playerMatches = new HashMap<>();
    private boolean[] arenaBusy;
    private Level level;
    private int baseY;
    private int firstTo;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        baseY = getConfig().getInt("arena-base-y", 180);
        firstTo = Math.max(1, getConfig().getInt("first-to", 3));
        int arenaSlots = Math.max(2, Math.min(16, getConfig().getInt("arena-slots", 8)));
        arenaBusy = new boolean[arenaSlots];
        REQUIRED.keySet().forEach(mode -> queues.put(mode, new LinkedHashSet<>()));
        getServer().getPluginManager().registerEvents(this, this);
        level = getServer().getDefaultLevel();
        getServer().getScheduler().scheduleDelayedTask(this, () -> {
            buildInfrastructure();
            for (Player player : getServer().getOnlinePlayers().values()) prepareWaitingPlayer(player);
        }, 20);
        getLogger().info("Nexora Practice 0.2 habilitado: 1v1, 2v2 y 4v4 con arenas reales.");
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

        String mode = args[0].toLowerCase(Locale.ROOT);
        if (mode.equals("leave") || mode.equals("salir")) {
            leaveEverything(player, true);
            return true;
        }
        if (mode.equals("status") || mode.equals("estado")) {
            sendStatus(player);
            return true;
        }
        if (mode.equals("rebuild") || mode.equals("reconstruir")) {
            if (!player.isOp()) {
                player.sendMessage(TextFormat.RED + "Solo un operador puede reconstruir las arenas.");
                return true;
            }
            if (!playerMatches.isEmpty()) {
                player.sendMessage(TextFormat.RED + "No se pueden reconstruir arenas mientras hay partidas activas.");
                return true;
            }
            buildInfrastructure();
            player.sendMessage(TextFormat.GREEN + "Arenas PvP reconstruidas.");
            return true;
        }
        if (!REQUIRED.containsKey(mode)) {
            sendHelp(player);
            return true;
        }

        joinQueue(player, mode);
        return true;
    }

    private void sendHelp(Player player) {
        player.sendMessage(TextFormat.AQUA + "Nexora PvP" + TextFormat.WHITE + " — /pvp <solo|duo|squad|leave|status>");
        player.sendMessage(TextFormat.GRAY + "solo=1v1 · duo=2v2 · squad=4v4 · first-to-" + firstTo);
    }

    private void sendStatus(Player player) {
        PracticeMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) {
            player.sendMessage(TextFormat.GOLD + "Partida " + match.mode + " · " + match.scoreA + "-" + match.scoreB + " · arena " + (match.slot + 1));
            return;
        }
        StringBuilder line = new StringBuilder(TextFormat.AQUA + "Colas: ");
        for (String mode : List.of("solo", "duo", "squad")) {
            line.append(TextFormat.WHITE).append(mode).append('=').append(queues.get(mode).size()).append('/').append(REQUIRED.get(mode)).append(' ');
        }
        player.sendMessage(line.toString());
    }

    private synchronized void joinQueue(Player player, String mode) {
        if (playerMatches.containsKey(player.getUniqueId())) {
            player.sendMessage(TextFormat.RED + "Ya estás en una partida. Usa /pvp leave para abandonarla.");
            return;
        }
        removeFromQueues(player.getUniqueId());
        LinkedHashSet<UUID> queue = queues.get(mode);
        queue.add(player.getUniqueId());
        player.sendMessage(TextFormat.GREEN + "Cola " + mode + ": " + queue.size() + "/" + REQUIRED.get(mode));
        tryStartMatches(mode);
    }

    private synchronized void tryStartMatches(String mode) {
        LinkedHashSet<UUID> queue = queues.get(mode);
        int required = REQUIRED.get(mode);
        while (queue.size() >= required) {
            int slot = allocateArena();
            if (slot < 0) {
                for (UUID id : queue) {
                    Player p = getServer().getPlayer(id).orElse(null);
                    if (p != null) p.sendMessage(TextFormat.YELLOW + "Todas las arenas están ocupadas; sigues en cola.");
                }
                return;
            }

            List<Player> selected = new ArrayList<>();
            Deque<UUID> stale = new ArrayDeque<>();
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
            PracticeMatch match = new PracticeMatch(mode, slot, selected);
            selected.forEach(p -> playerMatches.put(p.getUniqueId(), match));
            match.startRound();
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

    private void leaveEverything(Player player, boolean notify) {
        removeFromQueues(player.getUniqueId());
        PracticeMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.forfeit(player);
        if (notify) {
            prepareWaitingPlayer(player);
            player.sendMessage(TextFormat.GRAY + "Saliste de PvP.");
        }
    }

    private synchronized void removeFromQueues(UUID playerId) {
        for (Set<UUID> queue : queues.values()) queue.remove(playerId);
    }

    private void transferToLobby(Player player) {
        String host = getConfig().getString("lobby-host", "127.0.0.1");
        int port = getConfig().getInt("lobby-port", 19132);
        player.transfer(new InetSocketAddress(host, port));
    }

    private Position waitingSpawn() {
        return Position.fromObject(new Vector3(0.5, baseY + 2, 0.5), level);
    }

    private Position spectatorSpawn(int slot) {
        Vector3 c = arenaCenter(slot);
        return Position.fromObject(new Vector3(c.x, baseY + 10, c.z), level);
    }

    private Position teamSpawn(int slot, boolean teamA, int index, int teamSize) {
        Vector3 c = arenaCenter(slot);
        double spacing = 2.0;
        double start = -((teamSize - 1) * spacing) / 2.0;
        double x = c.x + start + index * spacing;
        double z = c.z + (teamA ? -13 : 13);
        return Position.fromObject(new Vector3(x + 0.5, baseY + 2, z + 0.5), level);
    }

    private Vector3 arenaCenter(int slot) {
        int columns = 4;
        int col = slot % columns;
        int row = slot / columns;
        return new Vector3((col - 1.5) * 70, baseY, 90 + row * 70);
    }

    private void buildInfrastructure() {
        if (level == null) level = getServer().getDefaultLevel();
        buildWaitingLobby();
        for (int i = 0; i < arenaBusy.length; i++) buildArena(i);
        getLogger().info("Infraestructura PvP construida: " + arenaBusy.length + " arenas.");
    }

    private void buildWaitingLobby() {
        Block floor = Block.get(Block.STONE);
        Block rail = Block.get(Block.GLASS);
        for (int x = -10; x <= 10; x++) {
            for (int z = -10; z <= 10; z++) level.setBlock(new Vector3(x, baseY, z), floor.clone());
        }
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
        Vector3 c = arenaCenter(slot);
        int cx = (int) Math.round(c.x);
        int cz = (int) Math.round(c.z);
        Block floor = Block.get(Block.STONE);
        Block wall = Block.get(Block.GLASS);
        Block edge = Block.get(Block.BEDROCK);
        for (int x = cx - 14; x <= cx + 14; x++) {
            for (int z = cz - 18; z <= cz + 18; z++) {
                Block material = (x == cx - 14 || x == cx + 14 || z == cz - 18 || z == cz + 18) ? edge : floor;
                level.setBlock(new Vector3(x, baseY, z), material.clone());
            }
        }
        for (int y = baseY + 1; y <= baseY + 5; y++) {
            for (int x = cx - 14; x <= cx + 14; x++) {
                level.setBlock(new Vector3(x, y, cz - 18), wall.clone());
                level.setBlock(new Vector3(x, y, cz + 18), wall.clone());
            }
            for (int z = cz - 18; z <= cz + 18; z++) {
                level.setBlock(new Vector3(cx - 14, y, z), wall.clone());
                level.setBlock(new Vector3(cx + 14, y, z), wall.clone());
            }
        }
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

    private void equipKit(Player player) {
        resetPlayer(player);
        player.getInventory().addItem(Item.get(Item.IRON_SWORD, 0, 1));
        player.getInventory().addItem(Item.get(Item.BOW, 0, 1));
        player.getInventory().addItem(Item.get(Item.ARROW, 0, 16));
    }

    private void prepareWaitingPlayer(Player player) {
        if (player == null || !player.isOnline()) return;
        resetPlayer(player);
        player.setGamemode(2);
        player.teleport(waitingSpawn());
        player.sendMessage(TextFormat.AQUA + "Nexora PvP: " + TextFormat.WHITE + "/pvp solo, /pvp duo o /pvp squad");
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        getServer().getScheduler().scheduleDelayedTask(this, () -> prepareWaitingPlayer(event.getPlayer()), 10);
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        removeFromQueues(player.getUniqueId());
        PracticeMatch match = playerMatches.get(player.getUniqueId());
        if (match != null) match.forfeit(player);
    }

    @EventHandler
    public void onDamage(EntityDamageEvent event) {
        if (!(event.getEntity() instanceof Player player)) return;
        PracticeMatch match = playerMatches.get(player.getUniqueId());
        if (match == null) {
            event.setCancelled();
            return;
        }
        if (!match.roundActive) {
            event.setCancelled();
            return;
        }
        if (event instanceof EntityDamageByEntityEvent byEntity && byEntity.getDamager() instanceof Player damager) {
            PracticeMatch other = playerMatches.get(damager.getUniqueId());
            if (other != match || match.sameTeam(player, damager)) {
                event.setCancelled();
                return;
            }
        }
        if (event.getFinalDamage() >= player.getHealth()) {
            event.setCancelled();
            match.eliminate(player);
        }
    }

    @EventHandler
    public void onDeath(PlayerDeathEvent event) {
        PracticeMatch match = playerMatches.get(event.getEntity().getUniqueId());
        if (match == null) return;
        event.setCancelled();
        match.eliminate(event.getEntity());
    }

    @EventHandler
    public void onMove(PlayerMoveEvent event) {
        PracticeMatch match = playerMatches.get(event.getPlayer().getUniqueId());
        if (match != null && match.roundActive && event.getTo().getY() < baseY - 8) match.eliminate(event.getPlayer());
    }

    @EventHandler
    public void onBreak(BlockBreakEvent event) {
        if (playerMatches.containsKey(event.getPlayer().getUniqueId())) event.setCancelled();
    }

    @EventHandler
    public void onPlace(BlockPlaceEvent event) {
        if (playerMatches.containsKey(event.getPlayer().getUniqueId())) event.setCancelled();
    }

    private final class PracticeMatch {
        private final String mode;
        private final int slot;
        private final List<Player> teamA = new ArrayList<>();
        private final List<Player> teamB = new ArrayList<>();
        private final Set<UUID> alive = new HashSet<>();
        private boolean roundActive;
        private boolean ended;
        private int scoreA;
        private int scoreB;

        private PracticeMatch(String mode, int slot, List<Player> players) {
            this.mode = mode;
            this.slot = slot;
            int teamSize = players.size() / 2;
            for (int i = 0; i < players.size(); i++) (i < teamSize ? teamA : teamB).add(players.get(i));
        }

        private void startRound() {
            if (ended) return;
            roundActive = false;
            alive.clear();
            teamA.forEach(p -> alive.add(p.getUniqueId()));
            teamB.forEach(p -> alive.add(p.getUniqueId()));
            int teamSize = teamA.size();
            for (int i = 0; i < teamA.size(); i++) prepareForRound(teamA.get(i), true, i, teamSize);
            for (int i = 0; i < teamB.size(); i++) prepareForRound(teamB.get(i), false, i, teamSize);
            broadcast(TextFormat.GOLD + "Ronda nueva · " + scoreA + " - " + scoreB + " · gana el primero en " + firstTo);
            getServer().getScheduler().scheduleDelayedTask(NexoraPractice.this, () -> {
                if (ended) return;
                roundActive = true;
                broadcastTitle(TextFormat.GREEN + "¡PELEA!", TextFormat.GRAY + mode.toUpperCase(Locale.ROOT));
            }, 40);
        }

        private void prepareForRound(Player player, boolean a, int index, int teamSize) {
            if (player == null || !player.isOnline()) return;
            equipKit(player);
            player.setGamemode(0);
            player.teleport(teamSpawn(slot, a, index, teamSize));
            player.sendTitle(a ? TextFormat.RED + "EQUIPO ROJO" : TextFormat.AQUA + "EQUIPO AZUL", TextFormat.GRAY + "Prepárate");
        }

        private boolean sameTeam(Player one, Player two) {
            return (teamA.contains(one) && teamA.contains(two)) || (teamB.contains(one) && teamB.contains(two));
        }

        private void eliminate(Player player) {
            if (!roundActive || ended || !alive.remove(player.getUniqueId())) return;
            resetPlayer(player);
            player.setGamemode(3);
            player.teleport(spectatorSpawn(slot));
            player.sendTitle(TextFormat.RED + "ELIMINADO", TextFormat.GRAY + "Observando la ronda");
            checkRoundWinner();
        }

        private void checkRoundWinner() {
            boolean aAlive = teamA.stream().anyMatch(p -> alive.contains(p.getUniqueId()));
            boolean bAlive = teamB.stream().anyMatch(p -> alive.contains(p.getUniqueId()));
            if (aAlive && bAlive) return;
            roundActive = false;
            if (aAlive) scoreA++; else if (bAlive) scoreB++; else return;
            broadcast(TextFormat.YELLOW + "Ronda terminada · " + scoreA + " - " + scoreB);
            if (scoreA >= firstTo || scoreB >= firstTo) {
                finish(scoreA > scoreB ? teamA : teamB, "victoria");
            } else {
                getServer().getScheduler().scheduleDelayedTask(NexoraPractice.this, this::startRound, 60);
            }
        }

        private void forfeit(Player quitter) {
            if (ended) return;
            List<Player> winner = teamA.contains(quitter) ? teamB : teamA;
            finish(winner, quitter.getName() + " abandonó");
        }

        private void finish(List<Player> winners, String reason) {
            if (ended) return;
            ended = true;
            roundActive = false;
            for (Player p : allPlayers()) {
                if (p == null || !p.isOnline()) continue;
                boolean win = winners.contains(p);
                p.sendTitle(win ? TextFormat.GOLD + "VICTORIA" : TextFormat.RED + "DERROTA", TextFormat.GRAY + reason);
            }
            getServer().getScheduler().scheduleDelayedTask(NexoraPractice.this, () -> {
                for (Player p : allPlayers()) {
                    playerMatches.remove(p.getUniqueId());
                    if (p.isOnline()) prepareWaitingPlayer(p);
                }
                releaseArena(slot);
                for (String queueMode : REQUIRED.keySet()) tryStartMatches(queueMode);
            }, 80);
        }

        private List<Player> allPlayers() {
            List<Player> all = new ArrayList<>(teamA);
            all.addAll(teamB);
            return all;
        }

        private void broadcast(String message) {
            for (Player p : allPlayers()) if (p != null && p.isOnline()) p.sendMessage(message);
        }

        private void broadcastTitle(String title, String subtitle) {
            for (Player p : allPlayers()) if (p != null && p.isOnline()) p.sendTitle(title, subtitle);
        }
    }
}
