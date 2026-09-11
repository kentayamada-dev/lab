"use client";

import { useState } from "react";
import { Code, ConnectError } from "@connectrpc/connect";
import { authClient } from "./client";

// Both procedures take the same two fields, so one form serves them and the
// mode only decides which one is called.
type Mode = "logIn" | "signUp";

// The API answers in English, for the clients that read it themselves; what
// the page shows is written here instead, in the language of the rest of it.
// The code is what carries the meaning, so the wording is free to say what the
// reader can do about it rather than what the server found.
function errorMessage(code: Code): string {
  switch (code) {
    case Code.AlreadyExists:
      return "このメールアドレスは既に登録されています";
    case Code.InvalidArgument:
      return "メールアドレスの形式と、パスワードの長さ（8〜72 バイト）を確認してください";
    case Code.Unauthenticated:
      return "メールアドレスまたはパスワードが違います";
    default:
      return "通信に失敗しました。しばらくしてからお試しください";
  }
}

export function AuthForm({ onAuthenticated }: { onAuthenticated: () => void }) {
  const [mode, setMode] = useState<Mode>("logIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    setError("");
    try {
      // The answer carries a token as well, for clients that send it
      // themselves; the app ignores it and uses the cookie the same response
      // sets (client.ts).
      if (mode === "logIn") {
        await authClient.logIn({ email, password });
      } else {
        await authClient.signUp({ email, password });
      }
      onAuthenticated();
    } catch (err) {
      setError(errorMessage(ConnectError.from(err).code));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main style={{ maxWidth: 480, margin: "40px auto", fontFamily: "sans-serif" }}>
      <h1>{mode === "logIn" ? "ログイン" : "アカウント作成"}</h1>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
        style={{ display: "flex", flexDirection: "column", gap: 8 }}
      >
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="メールアドレス"
          autoComplete="username"
          required
        />
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="パスワード（8〜72 バイト）"
          autoComplete={mode === "logIn" ? "current-password" : "new-password"}
          required
        />
        <button type="submit" disabled={busy}>
          {mode === "logIn" ? "ログイン" : "作成"}
        </button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <button
        type="button"
        onClick={() => {
          setMode(mode === "logIn" ? "signUp" : "logIn");
          setError("");
        }}
        style={{ marginTop: 16 }}
      >
        {mode === "logIn" ? "アカウントを作成する" : "ログインに戻る"}
      </button>
    </main>
  );
}
