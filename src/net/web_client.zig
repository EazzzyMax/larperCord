//! Identidade HTTP do cliente web do Discord.
//!
//! O app se apresenta como o cliente web (Chrome no Windows) porque é o
//! formato que o gateway e a API usam para um cliente que não é bot. Manter
//! tudo num lugar só evita o clássico "atualizei o User-Agent num arquivo e
//! esqueci no outro": inconsistência entre UA, `X-Super-Properties` e
//! `Sec-CH-UA` é justamente o que denuncia um cliente que não é navegador.
//!
//! Isto não é uma garantia contra banimento: cliente de terceiro viola os
//! Termos do Discord e a decisão final é sempre da conta. O objetivo aqui é
//! só não entregar de graça um fingerprint quebrado.
const std = @import("std");

/// Chrome 152 no Windows 10/11. É a mesma versão citada nas propriedades e
/// no `Sec-CH-UA`; mudar a maior aqui muda nos três lugares.
pub const browser_major = "152";
pub const user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" ++ browser_major ++ ".0.0.0 Safari/537.36";

/// Build number do bundle web do Discord. Confira em https://discord.com/login
/// (`buildNumber` no JS) de vez em quando: o cliente web manda o build dele,
/// e um número muito velho é mais um sinal de cliente que ficou parado.
pub const build_number = 667580;

/// `properties` do IDENTIFY e base do `X-Super-Properties` (que é este JSON
/// em base64). O `browser_user_agent` sai da mesma constante do UA.
pub const super_properties = std.fmt.comptimePrint(
    "{{\"os\":\"Windows\",\"browser\":\"Chrome\",\"device\":\"\",\"system_locale\":\"en-US\",\"has_client_mods\":false,\"browser_user_agent\":\"{s}\",\"browser_version\":\"{s}.0.0.0\",\"os_version\":\"10\",\"referrer\":\"\",\"referring_domain\":\"\",\"referrer_current\":\"\",\"referring_domain_current\":\"\",\"release_channel\":\"stable\",\"client_build_number\":{d},\"client_event_source\":null}}",
    .{ user_agent, browser_major, build_number },
);

/// `Sec-CH-UA` do Chrome. O "Not_A Brand" é o GREASE que o Chrome sorteia;
/// o valor não precisa ser o mesmo da versão exata, só existir e bater com a
/// versão maior do User-Agent.
pub const sec_ch_ua = std.fmt.comptimePrint(
    "\"Not_A Brand\";v=\"99\", \"Chromium\";v=\"{s}\", \"Google Chrome\";v=\"{s}\"",
    .{ browser_major, browser_major },
);

test "identidade web: UA, propriedades e client hints contam a mesma versão" {
    try std.testing.expect(std.mem.indexOf(u8, user_agent, browser_major) != null);
    try std.testing.expect(std.mem.indexOf(u8, super_properties, user_agent) != null);
    try std.testing.expect(std.mem.indexOf(u8, super_properties, "\"client_build_number\":667580") != null);
    try std.testing.expect(std.mem.indexOf(u8, sec_ch_ua, browser_major) != null);
}
