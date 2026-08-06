#!/usr/bin/env node
/**
 * Bot de Telegram — interfaz remota hacia el sistema de trading.
 * Modo long polling (no webhook: no necesita URL publica, corre bien dentro
 * de WSL2). Ver INVESTIGACION.md sección 4 y CLAUDE.md.
 *
 * Uso: npm run bot   (lee TELEGRAM_BOT_TOKEN y TELEGRAM_AUTHORIZED_CHAT_ID de .env)
 *
 * Estado actual: bot funcional y probado (comandos, botones inline,
 * lista blanca de chat_id). Lo que FALTA: conectarlo a Claude Code para que
 * las alertas de trading reales y las aprobaciones disparen ordenes de
 * verdad — hoy /testalert es solo una demostracion del patron, no ejecuta
 * nada en Robinhood.
 */
import "dotenv/config";
import { Bot, InlineKeyboard, type Context } from "grammy";

const token = process.env.TELEGRAM_BOT_TOKEN;
const authorizedChatId = process.env.TELEGRAM_AUTHORIZED_CHAT_ID;

if (!token) {
  console.error("Falta TELEGRAM_BOT_TOKEN en .env (copia .env.example y llénalo).");
  process.exit(1);
}
if (!authorizedChatId) {
  console.error("Falta TELEGRAM_AUTHORIZED_CHAT_ID en .env (copia .env.example y llénalo).");
  process.exit(1);
}

const bot = new Bot(token);

/** Lista blanca de un solo usuario — nunca procesar updates de otro chat_id. */
bot.use(async (ctx, next) => {
  const chatId = ctx.chat?.id?.toString();
  if (chatId !== authorizedChatId) {
    console.warn(`Update ignorado de chat_id no autorizado: ${chatId ?? "desconocido"}`);
    return; // silencio total — no revelar nada a quien no está en la lista blanca
  }
  await next();
});

bot.command("start", async (ctx) => {
  await ctx.reply(
    "Bot de mihael-trader conectado.\n\n" +
      "Comandos disponibles:\n" +
      "/status — estado del sistema\n" +
      "/testalert — probar el patrón de alerta con botones Aprobar/Rechazar (no ejecuta nada real)"
  );
});

bot.command("status", async (ctx) => {
  await ctx.reply(
    "Sistema: en construcción.\n" +
      "MCP de Robinhood: revisar con Claude Code si ya está autenticado.\n" +
      "Puente Claude Code <-> Telegram: todavía no conectado — este bot funciona, " +
      "pero las alertas reales de trading aún no lo disparan (ver CLAUDE.md)."
  );
});

/** Demostración del patrón de confirmación — NUNCA ejecutar una orden real
 *  sin este tipo de paso, con un pendingOrderId real detrás. */
bot.command("testalert", async (ctx) => {
  const fakeOrderId = `test-${Date.now()}`;
  const keyboard = new InlineKeyboard()
    .text("✅ Aprobar", `order:approve:${fakeOrderId}`)
    .text("❌ Rechazar", `order:reject:${fakeOrderId}`);
  await ctx.reply(
    "<b>[PRUEBA — no es una orden real]</b>\n" +
      "Señal: comprar 1 AAPL @ ~$230\n\n" +
      "Esto es solo para probar el patrón de botones. Nada se ejecuta.",
    { parse_mode: "HTML", reply_markup: keyboard }
  );
});

bot.callbackQuery(/^order:(approve|reject):(.+)$/, async (ctx) => {
  const [, decision, orderId] = ctx.match as unknown as [string, string, string];
  await ctx.answerCallbackQuery({
    text: decision === "approve" ? "Aprobado (prueba)" : "Rechazado (prueba)",
  });
  await ctx.editMessageText(
    `${ctx.callbackQuery.message?.text ?? ""}\n\n` +
      `→ ${decision === "approve" ? "✅ APROBADO" : "❌ RECHAZADO"} (orden de prueba ${orderId})`,
    { parse_mode: "HTML" }
  );
});

bot.catch((err) => {
  console.error("Error no manejado en el bot:", err.error);
});

async function main(): Promise<void> {
  const me = await bot.api.getMe();
  console.log(`Bot @${me.username} arrancando (long polling)...`);
  await bot.start({
    onStart: () => console.log("Bot corriendo. Ctrl+C para detener."),
  });
}

main();
