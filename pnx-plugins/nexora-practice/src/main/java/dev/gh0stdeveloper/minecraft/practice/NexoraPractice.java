package dev.gh0stdeveloper.minecraft.practice;

import cn.nukkit.Player;
import cn.nukkit.command.Command;
import cn.nukkit.command.CommandSender;
import cn.nukkit.event.EventHandler;
import cn.nukkit.event.Listener;
import cn.nukkit.event.player.PlayerQuitEvent;
import cn.nukkit.plugin.PluginBase;
import cn.nukkit.utils.TextFormat;

import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public final class NexoraPractice extends PluginBase implements Listener {
    private static final Map<String, Integer> REQUIRED = Map.of("solo", 2, "duo", 4, "squad", 8);
    private final Map<String, LinkedHashSet<String>> queues = new ConcurrentHashMap<>();

    @Override
    public void onEnable() {
        saveDefaultConfig();
        REQUIRED.keySet().forEach(mode -> queues.put(mode, new LinkedHashSet<>()));
        getServer().getPluginManager().registerEvents(this, this);
        getLogger().info("Nexora Practice habilitado para Solo, Duo y Escuadra.");
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("Este comando solo puede usarlo un jugador.");
            return true;
        }

        if (command.getName().equalsIgnoreCase("lobby")) {
            removeFromQueues(player.getName());
            String host = getConfig().getString("lobby-host", "127.0.0.1");
            int port = getConfig().getInt("lobby-port", 19132);
            player.transfer(new InetSocketAddress(host, port));
            return true;
        }

        if (args.length == 0) {
            player.sendMessage(TextFormat.AQUA + "PvP: " + TextFormat.WHITE + "/pvp <solo|duo|squad|leave>");
            return true;
        }

        String mode = args[0].toLowerCase(Locale.ROOT);
        if (mode.equals("leave") || mode.equals("salir")) {
            removeFromQueues(player.getName());
            player.sendMessage(TextFormat.GRAY + "Saliste de las colas PvP.");
            return true;
        }
        if (!REQUIRED.containsKey(mode)) {
            player.sendMessage(TextFormat.RED + "Modalidad inválida. Usa solo, duo o squad.");
            return true;
        }

        joinQueue(player, mode);
        return true;
    }

    private synchronized void joinQueue(Player player, String mode) {
        removeFromQueues(player.getName());
        LinkedHashSet<String> queue = queues.get(mode);
        queue.add(player.getName());
        int required = REQUIRED.get(mode);
        player.sendMessage(TextFormat.GREEN + "Cola PvP " + mode + ": " + queue.size() + "/" + required);

        if (queue.size() >= required) {
            List<String> match = new ArrayList<>();
            while (!queue.isEmpty() && match.size() < required) {
                String next = queue.iterator().next();
                queue.remove(next);
                match.add(next);
            }
            for (String name : match) {
                Player matched = getServer().getPlayerExact(name);
                if (matched != null) {
                    matched.sendMessage(TextFormat.GOLD + "Partida PvP encontrada (" + mode + ").");
                    matched.sendMessage(TextFormat.GRAY + "ArenaManager PNX será la siguiente capa de configuración.");
                }
            }
        }
    }

    private synchronized void removeFromQueues(String playerName) {
        for (Set<String> queue : queues.values()) {
            queue.remove(playerName);
        }
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        removeFromQueues(event.getPlayer().getName());
    }
}
