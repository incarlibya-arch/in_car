// in car — يبعت إشعار Firebase لكل صف جديد في جدول notifications.
//
// الإعداد (مرة وحدة):
// 1) Firebase Console ← Project settings ← Service accounts ← Generate new private key
// 2) Supabase ← Edge Functions ← Secrets: زيد FIREBASE_SERVICE_ACCOUNT والصق فيه محتوى ملف JSON كامل
// 3) انشر الدالة: supabase functions deploy push --no-verify-jwt
//    (أو من لوحة Supabase ← Edge Functions ← Deploy new function، والصق هذا الملف)
// 4) Supabase ← Database ← Webhooks ← Create: الجدول notifications، الحدث Insert،
//    النوع Supabase Edge Functions، والدالة push.

import { createClient } from "npm:@supabase/supabase-js@2";

type ServiceAccount = { client_email: string; private_key: string; project_id: string };

const sa: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}");
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

let cached: { token: string; exp: number } | null = null;

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp > now + 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(sig)}`,
    }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error("Firebase auth failed: " + JSON.stringify(j));
  cached = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cached.token;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const n = payload.record;
    if (!n?.user_id) return new Response("ignored", { status: 200 });

    const { data: tokens } = await db.from("device_tokens").select("token").eq("user_id", n.user_id);
    if (!tokens?.length) return new Response("no tokens", { status: 200 });

    const at = await accessToken();
    const data: Record<string, string> = {};
    for (const [k, v] of Object.entries(n.data ?? {})) data[k] = String(v);

    let sent = 0;
    for (const { token } of tokens) {
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: n.title, body: n.body },
            data,
            android: { priority: "high", notification: { sound: "default" } },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (r.ok) sent++;
      // رمز منتهي أو محذوف ← نمسحه
      else if (r.status === 404 || r.status === 400) await db.from("device_tokens").delete().eq("token", token);
    }
    return new Response(JSON.stringify({ sent }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
