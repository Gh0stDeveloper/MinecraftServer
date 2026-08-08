const $ = (id) => document.getElementById(id);
let address = "";

function serverCard(server) {
  const players = Number.isInteger(server.players) ? server.players : "—";
  const max = Number.isInteger(server.max_players) ? server.max_players : "—";
  return `<article class="server"><div class="server-top"><h3>${server.id}</h3><span class="pill ${server.online ? "on" : "off"}">${server.online ? "ONLINE" : "OFFLINE"}</span></div><strong>${players}/${max}</strong><small>jugadores · UDP ${server.port}</small></article>`;
}

async function refresh() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    address = `${data.host}:${data.lobby_port}`;
    $("serverAddress").textContent = address;
    $("totalPlayers").textContent = data.players ?? "—";
    $("bdsVersion").textContent = data.bds_version || "—";
    const online = data.servers.filter((server) => server.online).length;
    $("networkState").textContent = `${online}/${data.servers.length}`;
    $("serverGrid").innerHTML = data.servers.map(serverCard).join("");
    $("updatedAt").textContent = `Actualizado ${new Date(data.generated_at * 1000).toLocaleTimeString()}`;
    document.querySelectorAll("[data-network]").forEach((node) => { node.textContent = data.network; });
    document.title = data.network;
  } catch (error) {
    $("networkState").textContent = "ERROR";
    $("updatedAt").textContent = "No se pudo obtener el estado de la red.";
  }
}

$("copyAddress").addEventListener("click", async () => {
  if (!address) return;
  await navigator.clipboard.writeText(address);
  const button = $("copyAddress");
  const old = button.textContent;
  button.textContent = "Copiado";
  setTimeout(() => { button.textContent = old; }, 1300);
});

refresh();
setInterval(refresh, 10000);
