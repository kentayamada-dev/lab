"use client";

import { useState } from "react";
import { Code, ConnectError } from "@connectrpc/connect";
import { timestampDate } from "@bufbuild/protobuf/wkt";
import { accountClient } from "./client";

// What a failed closing tells the reader. Unauthenticated is the wrong
// password rather than an expired session: reaching the procedure at all took
// a session the server accepted, and it is the password it asks for again
// (api/internal/account/service.go).
function errorMessage(code: Code): string {
  switch (code) {
    case Code.Unauthenticated:
      return "パスワードが違います";
    default:
      return "通信に失敗しました。しばらくしてからお試しください";
  }
}

// The button stays behind a confirmation step that asks for the password,
// which is the API's requirement and not the page's: what the step adds is
// telling the reader what they are about to spend before they spend it.
export function DeleteAccount({ onClosed }: { onClosed: (purgeAt: Date) => void }) {
  const [asking, setAsking] = useState(false);
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const close = () => {
    setAsking(false);
    setPassword("");
    setError("");
  };

  const submit = async () => {
    setBusy(true);
    setError("");
    try {
      const { purgeAt } = await accountClient.deleteAccount({ password });
      // The instant is what the server recorded, so the page states the
      // promise the API made rather than one of its own. An answer without one
      // is a server that changed shape, and there is nothing to show for it.
      onClosed(purgeAt ? timestampDate(purgeAt) : new Date());
    } catch (err) {
      setError(errorMessage(ConnectError.from(err).code));
    } finally {
      setBusy(false);
    }
  };

  if (!asking) {
    return (
      <button type="button" onClick={() => setAsking(true)} style={{ color: "crimson" }}>
        退会する
      </button>
    );
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
      style={{ display: "flex", flexDirection: "column", gap: 8 }}
    >
      <p style={{ margin: 0 }}>
        退会すると、登録したすべての todo が見られなくなり、ログインもできなくなります。確認のためパスワードを入力してください。
      </p>
      <input
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="パスワード"
        autoComplete="current-password"
        required
      />
      <div style={{ display: "flex", gap: 8 }}>
        <button type="submit" disabled={busy} style={{ color: "crimson" }}>
          退会する
        </button>
        <button type="button" onClick={close} disabled={busy}>
          やめる
        </button>
      </div>
      {error && <p style={{ color: "crimson", margin: 0 }}>{error}</p>}
    </form>
  );
}

// What is left to say once the account is closed. The session ended with it,
// so there is nothing to go back to but the login form.
export function AccountClosed({ purgeAt, onDone }: { purgeAt: Date; onDone: () => void }) {
  return (
    <main style={{ maxWidth: 480, margin: "40px auto", fontFamily: "sans-serif" }}>
      <h1>退会しました</h1>
      <p>
        {purgeAt.toLocaleDateString("ja-JP")} までは、問い合わせればアカウントを元に戻せます。それ以降はデータごと削除され、元に戻せません。
      </p>
      <button type="button" onClick={onDone}>
        最初の画面に戻る
      </button>
    </main>
  );
}
